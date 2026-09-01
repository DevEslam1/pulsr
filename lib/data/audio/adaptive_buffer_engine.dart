// lib/data/audio/adaptive_buffer_engine.dart
import 'dart:math' as math;

/// Dynamic buffer sizing calculator based on real-time network conditions,
/// connection type, and track bitrate.
class AdaptiveBufferEngine {
  static const int minBufferMs = 2000; // 2s minimum
  static const int maxBufferMs = 30000; // 30s maximum
  static const int targetBufferMs = 8000; // 8s sweet spot

  final List<int> _recentBitrates = [];
  double _avgNetworkSpeedMbps = 10.0;

  double get averageNetworkSpeedMbps => _avgNetworkSpeedMbps;

  /// Calculates initial start buffer duration before playback begins.
  Duration calculateStartBuffer({
    required bool isWifi,
    required bool isLocalFile,
  }) {
    if (isLocalFile) {
      return const Duration(milliseconds: 100);
    }
    // Fast WiFi (≥25 Mbps) or very fast mobile: minimal start buffer so
    // ExoPlayer starts decoding as quickly as possible.
    if (_avgNetworkSpeedMbps >= 25.0) {
      return const Duration(milliseconds: 500);
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
  /// and storage locality.
  Duration calculateOptimalBuffer({
    required int bitrateKbps,
    required bool isWifi,
    required bool isLocalFile,
  }) {
    if (isLocalFile) {
      return Duration.zero; // Local disk I/O requires no network buffering
    }

    final safeBitrate = bitrateKbps <= 0 ? 320 : bitrateKbps;
    final safeSpeed = _avgNetworkSpeedMbps <= 0
        ? (isWifi ? 10.0 : 2.0)
        : _avgNetworkSpeedMbps;

    // Time to download 1 track at current speed (estimate 4 minutes)
    const trackDurationSec = 240.0;
    final dataNeededMb = (safeBitrate * trackDurationSec) / 1000.0;
    final downloadTimeSec = dataNeededMb / math.max(0.1, safeSpeed);

    // Buffer target = 1.5x download time, clamped between min and max bounds
    final targetSec = (downloadTimeSec * 1.5).ceil();
    final clampedSec = targetSec.clamp(
      minBufferMs ~/ 1000,
      maxBufferMs ~/ 1000,
    );

    return Duration(seconds: clampedSec);
  }

  /// Updates rolling network throughput average in Mbps.
  void updateNetworkSpeed(double speedMbps) {
    if (speedMbps <= 0) return;
    _recentBitrates.add((speedMbps * 1000).toInt());
    if (_recentBitrates.length > 10) {
      _recentBitrates.removeAt(0);
    }
    final sum = _recentBitrates.reduce((a, b) => a + b);
    _avgNetworkSpeedMbps = (sum / _recentBitrates.length) / 1000.0;
  }

  /// Resets network history to default baseline.
  void reset() {
    _recentBitrates.clear();
    _avgNetworkSpeedMbps = 10.0;
  }
}
