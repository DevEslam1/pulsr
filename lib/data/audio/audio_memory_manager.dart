// lib/data/audio/audio_memory_manager.dart
import 'package:just_audio/just_audio.dart';

/// Aggressive memory and audio buffer management with LRU cleanup.
class AudioMemoryManager {
  static const int maxStreamCacheEntries = 64;

  final void Function()? onEvictOldestCacheRequested;
  final void Function()? onBackgroundReleaseRequested;

  AudioMemoryManager({
    this.onEvictOldestCacheRequested,
    this.onBackgroundReleaseRequested,
  });

  /// Called when a track finishes playback to release completed audio buffers.
  void onTrackCompleted(int trackId) {
    onEvictOldestCacheRequested?.call();
  }

  /// Called when the application moves to background state to trim idle buffers.
  void onAppBackgrounded({
    required AudioPlayer inactivePlayer,
    AudioPlayer? prefetchPlayer,
  }) {
    try {
      if (!inactivePlayer.playing) {
        inactivePlayer.stop().catchError((_) {});
      }
      if (prefetchPlayer != null && !prefetchPlayer.playing) {
        prefetchPlayer.stop().catchError((_) {});
      }
    } catch (_) {}
    onBackgroundReleaseRequested?.call();
  }

  /// Trims stream cache map to [maxStreamCacheEntries].
  static void trimStreamCache<T>(Map<String, T> cache) {
    if (cache.length > maxStreamCacheEntries) {
      final excess = cache.length - maxStreamCacheEntries;
      final keysToRemove = cache.keys.take(excess).toList();
      for (final key in keysToRemove) {
        cache.remove(key);
      }
    }
  }
}
