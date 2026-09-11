// lib/data/audio/playback_analytics.dart
import 'dart:async';
import '../../core/utils/error_logger.dart';

/// Events emitted during playback lifecycle for health tracking and self-healing.
enum PlaybackHealthEvent {
  bufferUnderrun,
  streamFailure,
  decodeError,
  audioTrackStarvation,
  recovered,
}

/// Real-time playback analytics tracker with self-healing recovery actions.
class PlaybackAnalytics {
  final List<PlaybackHealthEvent> _recentEvents = [];
  int _bufferUnderrunCount = 0;
  int _underrunEpoch = 0;

  final void Function()? onIncreaseBufferSizeRequested;
  final void Function()? onReduceQualityRequested;
  final Future<void> Function(String videoId, Object error)?
      onStreamRecoveryRequested;
  final void Function(String path, Object error)? onCorruptedFileDetected;

  PlaybackAnalytics({
    this.onIncreaseBufferSizeRequested,
    this.onReduceQualityRequested,
    this.onStreamRecoveryRequested,
    this.onCorruptedFileDetected,
  });

  void _addEvent(PlaybackHealthEvent event) {
    _recentEvents.add(event);
    if (_recentEvents.length > 500) {
      _recentEvents.removeRange(0, _recentEvents.length - 500);
    }
  }

  /// Tracks a buffer underrun event and triggers adaptive scaling if threshold is reached.
  /// Staggered healing: first widen the buffer (cheap, no quality loss);
  /// only step quality down if underruns persist after the buffer widened.
  void recordBufferUnderrun() {
    _addEvent(PlaybackHealthEvent.bufferUnderrun);
    _bufferUnderrunCount++;

    if (_bufferUnderrunCount == 3) {
      _bufferUnderrunCount = 0;
      _underrunEpoch++;
      onIncreaseBufferSizeRequested?.call();
    } else if (_bufferUnderrunCount >= 3) {
      // Defensive: counter should have reset above; heal conservatively.
      _bufferUnderrunCount = 0;
      onIncreaseBufferSizeRequested?.call();
    }
    if (_underrunEpoch >= 2) {
      _underrunEpoch = 0;
      onReduceQualityRequested?.call();
    }
  }

  /// Tracks a stream resolution / playback failure and triggers self-healing recovery chain.
  void recordStreamFailure(String videoId, Object error) {
    _addEvent(PlaybackHealthEvent.streamFailure);
    ErrorLogger.log('Stream failure recorded for $videoId: $error',
        category: 'PlaybackAnalytics');
    onStreamRecoveryRequested?.call(videoId, error);
  }

  /// Tracks a file decoding error.
  void recordDecodeError(String path, Object error) {
    _addEvent(PlaybackHealthEvent.decodeError);
    ErrorLogger.log('Decode error recorded for $path: $error',
        category: 'PlaybackAnalytics');
    onCorruptedFileDetected?.call(path, error);
  }

  /// Resets error counters on successful track progress.
  void resetErrorCounters() {
    _bufferUnderrunCount = 0;
    _underrunEpoch = 0;
    if (_recentEvents.length > 500) {
      _recentEvents.removeRange(0, _recentEvents.length - 500);
    }
  }
}
