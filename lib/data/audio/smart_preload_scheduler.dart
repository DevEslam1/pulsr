import 'dart:async';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/network/connectivity_guard.dart';
import '../db/app_database.dart';
import 'artwork_uri_resolver.dart';

/// Preload behavior policy per connection type.
enum PreloadNetworkPolicy {
  always,
  conservativeOnMetered,
  wifiOnly,
  never,
}

/// Intelligent queue analysis and preload scheduler.
class SmartPreloadScheduler {
  final Future<void> Function(SongsTableData song, {required int priority})
      onPreloadRequested;
  final String Function()? qualityProvider;
  final void Function()? onCancelRequested;

  /// Optional custom provider for metered connection detection. Defaults to [ConnectivityGuard.isMeteredConnection].
  final Future<bool> Function()? isMeteredConnectionProvider;

  /// Policy controlling preload behavior based on network type.
  PreloadNetworkPolicy networkPolicy;

  static const String _prefDataUsageKey = 'preload_data_usage_bytes';
  static int _preloadDataUsageBytes = 0;

  /// Total estimated bytes used for ahead-of-time preloading.
  static int get preloadDataUsageBytes => _preloadDataUsageBytes;

  static Future<void> initDataUsage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _preloadDataUsageBytes = prefs.getInt(_prefDataUsageKey) ?? 0;
    } catch (_) {}
  }

  static Future<void> resetPreloadDataUsage() async {
    _preloadDataUsageBytes = 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefDataUsageKey, 0);
    } catch (_) {}
  }

  static void recordPreloadDataUsage(int bytes) {
    if (bytes <= 0) return;
    _preloadDataUsageBytes += bytes;
    unawaited(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_prefDataUsageKey, _preloadDataUsageBytes);
      } catch (_) {}
    }());
  }

  final Map<String, DateTime> _scheduledKeys = {};
  static const _keyTtl = Duration(hours: 4);
  int _generation = 0;
  int get generation => _generation;

  SmartPreloadScheduler({
    required this.onPreloadRequested,
    this.qualityProvider,
    this.onCancelRequested,
    this.isMeteredConnectionProvider,
    this.networkPolicy = PreloadNetworkPolicy.conservativeOnMetered,
  });

  String _dedupKey(SongsTableData song) {
    final videoId = song.remoteId;
    if (videoId != null && videoId.isNotEmpty) {
      final q = (qualityProvider?.call() ?? 'high').toLowerCase();
      return '$videoId:$q';
    }
    return '${song.id}_${song.remoteId}';
  }

  /// Evaluates the current playback progress and schedules ahead-of-time preloads.
  ///
  /// [explicitNextSong] pins the single track to preload for the non-gapless
  /// shuffle case: the state machine's pre-committed next pick, which neither
  /// the gapless [shuffleIndices] path nor the random fallback would match.
  void schedulePreloads({
    required List<SongsTableData> queue,
    required int currentIndex,
    required bool isShuffle,
    required Duration position,
    required Duration duration,
    List<int>? shuffleIndices,
    SongsTableData? explicitNextSong,
    int preloadCount = 3,
  }) {
    if (networkPolicy == PreloadNetworkPolicy.never) return;
    if (queue.isEmpty || currentIndex < 0 || currentIndex >= queue.length) {
      return;
    }

    if (duration > Duration.zero) {
      final timeRemaining = duration - position;
      final isPastThreshold =
          position.inMilliseconds >= (duration.inMilliseconds * 0.7);
      final shouldPreload =
          timeRemaining < const Duration(seconds: 60) || isPastThreshold;
      if (!shouldPreload) {
        return; // Too early to preload
      }
    }

    final meterProbe = isMeteredConnectionProvider;
    if (meterProbe == null) {
      // No injected probe: dispatch synchronously (assume unmetered) and refresh
      // the cached state in the background for subsequent scheduling passes.
      unawaited(_refreshMeteredState());
      _dispatchPreloads(
        queue: queue,
        currentIndex: currentIndex,
        isShuffle: isShuffle,
        shuffleIndices: shuffleIndices,
        explicitNextSong: explicitNextSong,
        preloadCount: preloadCount,
        isMetered: _meteredCache,
      );
      return;
    }

    final gen = _generation;
    unawaited(() async {
      bool isMetered;
      try {
        isMetered = await meterProbe();
      } catch (_) {
        isMetered = false;
      }
      // A queue change (clear()) bumps _generation while the probe awaited;
      // bail so we don't dispatch preloads for a stale queue (item 14).
      if (gen != _generation) return;
      _dispatchPreloads(
        queue: queue,
        currentIndex: currentIndex,
        isShuffle: isShuffle,
        shuffleIndices: shuffleIndices,
        explicitNextSong: explicitNextSong,
        preloadCount: preloadCount,
        isMetered: isMetered,
      );
    }());
  }

  bool _meteredCache = false;

  Future<void> _refreshMeteredState() async {
    try {
      _meteredCache = await ConnectivityGuard.isMeteredConnection();
    } catch (_) {
      // Keep the last known state on failure.
    }
  }

  void _dispatchPreloads({
    required List<SongsTableData> queue,
    required int currentIndex,
    required bool isShuffle,
    required List<int>? shuffleIndices,
    SongsTableData? explicitNextSong,
    required int preloadCount,
    required bool isMetered,
  }) {
    if (isMetered && networkPolicy == PreloadNetworkPolicy.wifiOnly) {
      return;
    }

    int effectiveCount = preloadCount.clamp(1, 5);
    if (isMetered &&
        networkPolicy == PreloadNetworkPolicy.conservativeOnMetered) {
      // Metered connection: limit preload to at most 1 item.
      effectiveCount = 1;
    }

    if (isShuffle) {
      if (shuffleIndices != null && shuffleIndices.isNotEmpty) {
        final pos = shuffleIndices.indexOf(currentIndex);
        if (pos >= 0) {
          for (int i = 1; i <= effectiveCount; i++) {
            final p = pos + i;
            if (p >= shuffleIndices.length) break;
            final idx = shuffleIndices[p];
            if (idx >= 0 && idx < queue.length) {
              _preloadTrack(queue[idx], priority: i, isMetered: isMetered);
            }
          }
          return;
        }
      }
      // Non-gapless shuffle: warm the state machine's pre-committed next pick
      // (the track the next advance will actually play) instead of a random
      // guess that would almost never match.
      if (explicitNextSong != null) {
        _preloadTrack(explicitNextSong, priority: 1, isMetered: isMetered);
        return;
      }
      _preloadRandomTracks(queue, currentIndex,
          count: effectiveCount, isMetered: isMetered);
    } else {
      for (int i = 1; i <= effectiveCount; i++) {
        final idx = currentIndex + i;
        if (idx < queue.length) {
          _preloadTrack(queue[idx], priority: i, isMetered: isMetered);
        }
      }
    }
  }

  void _preloadRandomTracks(
    List<SongsTableData> queue,
    int currentIndex, {
    required int count,
    required bool isMetered,
  }) {
    final availableIndices = List.generate(queue.length, (i) => i)
      ..remove(currentIndex);
    if (availableIndices.isEmpty) return;

    final random = math.Random();
    availableIndices.shuffle(random);
    final chosen = availableIndices.take(count);

    int priority = 1;
    for (final idx in chosen) {
      _preloadTrack(queue[idx], priority: priority++, isMetered: isMetered);
    }
  }

  void _preloadTrack(
    SongsTableData song, {
    required int priority,
    bool isMetered = false,
  }) {
    // Local files are fast disk I/O, no network resolution required
    if (song.source == SongSource.local) return;

    // Skip preloading long tracks (> 10 minutes) on metered connections to conserve data
    if (isMetered &&
        networkPolicy == PreloadNetworkPolicy.conservativeOnMetered &&
        song.durationMs > 10 * 60 * 1000) {
      return;
    }

    final key = _dedupKey(song);
    final scheduledAt = _scheduledKeys[key];
    if (scheduledAt != null &&
        DateTime.now().difference(scheduledAt) < _keyTtl) {
      return;
    }
    _scheduledKeys[key] = DateTime.now();
    // Bound map growth (queues churn across sessions).
    if (_scheduledKeys.length > 500) {
      final oldest = _scheduledKeys.keys.first;
      _scheduledKeys.remove(oldest);
    }

    // Estimate data usage: ~20 KB/sec based on 160 kbps stream, minimum 1.5MB
    final durationSecs = (song.durationMs / 1000).clamp(30, 600);
    final estimatedBytes = math.max(1500000, (durationSecs * 20000).toInt());
    recordPreloadDataUsage(estimatedBytes);

    unawaited(ArtworkUriResolver.resolveArtworkUri(song));

    onPreloadRequested(song, priority: priority);
  }

  /// Clears scheduled cache keys and cancels in-flight preloads on queue changes.
  void clear() {
    _scheduledKeys.clear();
    _generation++;
    onCancelRequested?.call();
  }

  /// Cancels in-flight preloads and clears state.
  void cancel() => clear();
}
