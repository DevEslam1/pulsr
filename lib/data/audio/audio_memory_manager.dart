// lib/data/audio/audio_memory_manager.dart
import 'dart:collection';
import 'package:just_audio/just_audio.dart';

/// Item stored in preloaded stream head cache.
class PreloadedHead {
  final String key;
  final int sizeBytes;
  final DateTime timestamp;

  PreloadedHead({
    required this.key,
    required this.sizeBytes,
    required this.timestamp,
  });
}

/// Aggressive memory and audio buffer management with strict LRU cleanup
/// and hard 32MB budget capping for preloaded stream heads.
class AudioMemoryManager {
  static const int maxStreamCacheEntries = 64;
  static const int maxPreloadBudgetBytes = 32 * 1024 * 1024; // 32MB hard cap
  static const int defaultHeadSizeBytes = 2 * 1024 * 1024; // 2MB default head

  final LinkedHashMap<String, PreloadedHead> _headCache = LinkedHashMap();
  int _currentPreloadBytes = 0;

  final void Function()? onEvictOldestCacheRequested;
  final void Function()? onBackgroundReleaseRequested;

  AudioMemoryManager({
    this.onEvictOldestCacheRequested,
    this.onBackgroundReleaseRequested,
  });

  int get currentPreloadBytes => _currentPreloadBytes;
  int get preloadedHeadCount => _headCache.length;

  /// Calculates stream head size in bytes sized by duration (e.g. 10s) and bitrate.
  static int calculateHeadSize(
      {int? bitrateKbps, int? sampleRate, int? bitDepth}) {
    if (bitrateKbps != null && bitrateKbps > 0) {
      // 10 seconds of compressed stream
      return (bitrateKbps * 1000 ~/ 8) * 10;
    }
    if (sampleRate != null && bitDepth != null) {
      // 10 seconds of uncompressed/lossless audio: sampleRate * channels(2) * (bitDepth / 8) * 10
      final bytesPerSec = sampleRate * 2 * (bitDepth ~/ 8);
      return (bytesPerSec * 10).clamp(1 * 1024 * 1024, 4 * 1024 * 1024);
    }
    return defaultHeadSizeBytes;
  }

  /// Determines whether preloading is permitted based on battery status and memory budget.
  bool canPreload(
      {required bool isBatteryConstrained,
      int estimatedBytes = defaultHeadSizeBytes}) {
    if (isBatteryConstrained) return false;
    return (_currentPreloadBytes + estimatedBytes) <= maxPreloadBudgetBytes ||
        _headCache.isNotEmpty;
  }

  /// Registers a preloaded stream head and evicts oldest items if exceeding 32MB cap.
  void registerPreload(String key, int sizeBytes) {
    if (_headCache.containsKey(key)) {
      final existing = _headCache.remove(key)!;
      _currentPreloadBytes -= existing.sizeBytes;
    }

    // Evict LRU entries until we fit within 32MB budget
    while (_headCache.isNotEmpty &&
        (_currentPreloadBytes + sizeBytes) > maxPreloadBudgetBytes) {
      final oldestKey = _headCache.keys.first;
      final oldest = _headCache.remove(oldestKey)!;
      _currentPreloadBytes -= oldest.sizeBytes;
      onEvictOldestCacheRequested?.call();
    }

    final entry = PreloadedHead(
      key: key,
      sizeBytes: sizeBytes,
      timestamp: DateTime.now(),
    );
    _headCache[key] = entry;
    _currentPreloadBytes += sizeBytes;
  }

  /// Releases a specific preloaded head from cache.
  void evict(String key) {
    if (_headCache.containsKey(key)) {
      final entry = _headCache.remove(key)!;
      _currentPreloadBytes -= entry.sizeBytes;
    }
  }

  /// Clears all preloaded heads immediately.
  void clearAll() {
    _headCache.clear();
    _currentPreloadBytes = 0;
  }

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
