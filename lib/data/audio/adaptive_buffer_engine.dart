import 'dart:async';
import 'dart:math' as math;

/// Coarse buffering buckets mapped to distinct ExoPlayer LoadControl profiles.
enum BufferBucket {
  minimal,
  standard,
  generous;

  Duration get minBufferDuration {
    switch (this) {
      case BufferBucket.minimal:
        return const Duration(seconds: 10);
      case BufferBucket.standard:
        return const Duration(seconds: 30);
      case BufferBucket.generous:
        return const Duration(seconds: 50);
    }
  }

  Duration get maxBufferDuration {
    switch (this) {
      case BufferBucket.minimal:
        return const Duration(seconds: 20);
      case BufferBucket.standard:
        return const Duration(seconds: 60);
      case BufferBucket.generous:
        return const Duration(seconds: 90);
    }
  }

  Duration get bufferForPlaybackDuration => const Duration(milliseconds: 250);

  Duration get bufferForPlaybackAfterRebufferDuration {
    switch (this) {
      case BufferBucket.minimal:
        return const Duration(milliseconds: 500);
      case BufferBucket.standard:
        return const Duration(milliseconds: 800);
      case BufferBucket.generous:
        return const Duration(milliseconds: 1500);
    }
  }
}

/// Dynamic buffer sizing calculator based on real-time network conditions,
/// connection type, and track bitrate.
class AdaptiveBufferEngine {
  static const int minBufferMs = 2000; // 2s minimum
  static const int maxBufferMs = 50000; // 50s maximum (ExoPlayer aligned)
  static const int targetBufferMs = 8000; // 8s sweet spot

  static const double _alpha = 0.3; // EWMA weight for recent throughput
  bool _isInitialized = false;
  double _ewmaMbps = 10.0;
  double _varianceMbps = 0.0;
  double _avgNetworkSpeedMbps = 10.0;
  BufferBucket? _forcedBucket;
  BufferBucket _currentBucket = BufferBucket.standard;

  final StreamController<BufferBucket> _bucketController =
      StreamController<BufferBucket>.broadcast();
  Stream<BufferBucket> get onBucketChanged => _bucketController.stream;
  BufferBucket get currentBucket => _forcedBucket ?? _currentBucket;

  final StreamController<String> _qualityStepDownController =
      StreamController<String>.broadcast();
  Stream<String> get onStepDownQualityRequested => _qualityStepDownController.stream;

  final List<DateTime> _recentUnderruns = [];

  double get averageNetworkSpeedMbps => _avgNetworkSpeedMbps;
  double get varianceMbps => _varianceMbps;

  /// Forces a specific bucket (e.g. from battery optimization policy).
  void forceBucket(BufferBucket bucket) {
    if (_forcedBucket != bucket) {
      _forcedBucket = bucket;
      if (!_bucketController.isClosed) _bucketController.add(bucket);
    }
  }

  /// Releases an active forced bucket override.
  void releaseForce() {
    if (_forcedBucket != null) {
      _forcedBucket = null;
      if (!_bucketController.isClosed) _bucketController.add(_currentBucket);
    }
  }

  /// Computes the recommended [BufferBucket] given network and storage type.
  /// Honours an active force; use [_environmentBucket] for the raw network-
  /// derived value that ignores the override.
  BufferBucket bucketFor({required bool isWifi, required bool isLocal}) {
    if (_forcedBucket != null) return _forcedBucket!;
    return _environmentBucket(isWifi: isWifi, isLocal: isLocal);
  }

  /// The bucket derived purely from network/storage conditions, ignoring any
  /// active force. Kept separate so [evaluateBucket] can track the real
  /// environment bucket in `_currentBucket` while a force is held — otherwise
  /// `bucketFor` returned the forced value, `evaluateBucket` wrote that back
  /// into `_currentBucket`, and `releaseForce` then emitted the stale forced
  /// value instead of the true environment bucket.
  BufferBucket _environmentBucket({required bool isWifi, required bool isLocal}) {
    if (isLocal) return BufferBucket.minimal;
    final stdDev = math.sqrt(_varianceMbps);
    final jittery = stdDev > _ewmaMbps * 0.4; // swinging link -> larger buffer
    if (jittery) return BufferBucket.generous;
    if (isWifi && _ewmaMbps >= 8.0) return BufferBucket.standard;
    if (_ewmaMbps < 2.0) return BufferBucket.generous;
    return BufferBucket.standard;
  }

  /// Evaluates and updates the current bucket based on environment.
  void evaluateBucket({required bool isWifi, required bool isLocal}) {
    final next = _environmentBucket(isWifi: isWifi, isLocal: isLocal);
    if (_currentBucket != next) {
      _currentBucket = next;
      if (_forcedBucket == null && !_bucketController.isClosed) {
        _bucketController.add(next);
      }
    }
  }

  /// Samples real throughput from bytes received over an observed duration.
  void sampleThroughput(int bytes, Duration elapsed) {
    if (elapsed.inMilliseconds < 200 || bytes <= 0) return;
    final mbps = (bytes * 8.0) / (elapsed.inMilliseconds / 1000.0) / 1000000.0;
    updateNetworkSpeed(mbps);
  }

  /// Calculates initial start buffer duration before playback begins.
  Duration calculateStartBuffer({
    required bool isWifi,
    required bool isLocalFile,
  }) {
    if (isLocalFile) {
      return const Duration(milliseconds: 100);
    }
    if (isWifi && _avgNetworkSpeedMbps >= 8.0) {
      return const Duration(milliseconds: 800);
    } else if (_avgNetworkSpeedMbps >= 2.0) {
      return const Duration(milliseconds: 1200);
    } else {
      return const Duration(milliseconds: 2500);
    }
  }

  /// Calculates optimal buffer duration based on bitrate, network connection,
  /// storage locality, and track duration.
  Duration calculateOptimalBuffer({
    required int bitrateKbps,
    required bool isWifi,
    required bool isLocalFile,
    Duration? trackDuration,
  }) {
    if (isLocalFile) {
      return Duration.zero; // Local disk I/O requires no network buffering
    }

    final safeBitrate = bitrateKbps <= 0 ? 320 : bitrateKbps;
    final safeSpeed = _avgNetworkSpeedMbps <= 0
        ? (isWifi ? 10.0 : 2.0)
        : _avgNetworkSpeedMbps;

    final trackDurationSec =
        (trackDuration != null && trackDuration.inSeconds > 0)
            ? trackDuration.inSeconds.toDouble()
            : 240.0;
    final dataNeededMb = (safeBitrate * trackDurationSec) / 1000.0;
    final downloadTimeSec = dataNeededMb / math.max(0.1, safeSpeed);
    // Buffer target = safetyMultiplier * download time, clamped between min and max bounds
    final stdDev = math.sqrt(_varianceMbps);
    final jitterFactor =
        (_ewmaMbps > 0 && stdDev > 0) ? (stdDev / _ewmaMbps).clamp(0.0, 2.0) : 0.0;
    final safetyMultiplier = 1.5 + jitterFactor;
    final targetSec = (downloadTimeSec * safetyMultiplier).ceil();
    final clampedSec = targetSec.clamp(
      minBufferMs ~/ 1000,
      maxBufferMs ~/ 1000,
    );

    return Duration(seconds: clampedSec);
  }

  /// Updates rolling network throughput average with EWMA and tracks variance.
  void updateNetworkSpeed(double speedMbps) {
    if (speedMbps <= 0) return;
    if (!_isInitialized) {
      _ewmaMbps = speedMbps;
      _varianceMbps = 0.0;
      _avgNetworkSpeedMbps = _ewmaMbps;
      _isInitialized = true;
    } else {
      final delta = speedMbps - _ewmaMbps;
      _ewmaMbps += _alpha * delta;
      _varianceMbps = (1 - _alpha) * (_varianceMbps + _alpha * delta * delta);
      _avgNetworkSpeedMbps = _ewmaMbps;
    }
  }

  /// Records a buffer underrun/rebuffer event. If 2 or more underruns occur
  /// within 30 seconds, requests a streaming quality step-down.
  void recordBufferUnderrun({String currentQuality = 'high'}) {
    final now = DateTime.now();
    _recentUnderruns.removeWhere((t) => now.difference(t).inSeconds > 30);
    _recentUnderruns.add(now);

    if (_recentUnderruns.length >= 2) {
      _recentUnderruns.clear();
      final q = currentQuality.toLowerCase();
      if (q == 'low') return;

      final target = switch (q) {
        'high' => 'medium',
        'medium' => 'low',
        _ => null,
      };
      if (target != null && !_qualityStepDownController.isClosed) {
        _qualityStepDownController.add(target);
      }
    }
  }

  /// Resets network history to default baseline.
  void reset() {
    _recentUnderruns.clear();
    _isInitialized = false;
    _ewmaMbps = 10.0;
    _varianceMbps = 0.0;
    _avgNetworkSpeedMbps = 10.0;
  }

  /// Disposes stream controllers and cleans up resources.
  void dispose() {
    _bucketController.close();
    _qualityStepDownController.close();
  }
}
