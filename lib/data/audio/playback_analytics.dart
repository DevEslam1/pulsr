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

  /// Tracks a buffer underrun event and triggers adaptive scaling if threshold is reached.
  void recordBufferUnderrun() {
    _recentEvents.add(PlaybackHealthEvent.bufferUnderrun);
    _bufferUnderrunCount++;

    if (_bufferUnderrunCount >= 3) {
      _bufferUnderrunCount = 0;
      onIncreaseBufferSizeRequested?.call();
      onReduceQualityRequested?.call();
    }
  }

  /// Tracks a stream resolution / playback failure and triggers self-healing recovery chain.
  void recordStreamFailure(String videoId, Object error) {
    _recentEvents.add(PlaybackHealthEvent.streamFailure);
    ErrorLogger.log('Stream failure recorded for $videoId: $error',
        category: 'PlaybackAnalytics');
    onStreamRecoveryRequested?.call(videoId, error);
  }

  /// Tracks a file decoding error.
  void recordDecodeError(String path, Object error) {
    _recentEvents.add(PlaybackHealthEvent.decodeError);
    ErrorLogger.log('Decode error recorded for $path: $error',
        category: 'PlaybackAnalytics');
    onCorruptedFileDetected?.call(path, error);
  }

  /// Resets error counters on successful track progress.
  void resetErrorCounters() {
    _bufferUnderrunCount = 0;
    if (_recentEvents.length > 1000) {
      _recentEvents.removeRange(0, _recentEvents.length - 1000);
    }
  }
}
