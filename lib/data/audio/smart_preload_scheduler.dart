import 'dart:async';
import 'dart:math' as math;
import '../db/app_database.dart';
import 'artwork_uri_resolver.dart';

/// Intelligent queue analysis and preload scheduler.
class SmartPreloadScheduler {
  final Future<void> Function(SongsTableData song, {required int priority})
      onPreloadRequested;
  final String Function()? qualityProvider;

  final Map<String, DateTime> _scheduledKeys = {};
  static const _keyTtl = Duration(hours: 4);

  SmartPreloadScheduler({required this.onPreloadRequested, this.qualityProvider});

  String _dedupKey(SongsTableData song) {
    // Unified with AudioHandler's `videoId:quality` cache keys so a quality
    // change re-resolves instead of hitting a stale scheduled-key block.
    final videoId = song.remoteId;
    if (videoId != null && videoId.isNotEmpty) {
      final q = (qualityProvider?.call() ?? 'high').toLowerCase();
      return '$videoId:$q';
    }
    return '${song.id}_${song.remoteId}';
  }

  /// Evaluates the current playback progress and schedules ahead-of-time preloads.
  void schedulePreloads({
    required List<SongsTableData> queue,
    required int currentIndex,
    required bool isShuffle,
    required Duration position,
    required Duration duration,
    List<int>? shuffleIndices,
    int preloadCount = 3,
  }) {
    if (queue.isEmpty || currentIndex < 0 || currentIndex >= queue.length) {
      return;
    }

    if (duration > Duration.zero) {
      final timeRemaining = duration - position;
      final isPastThreshold =
          position.inMilliseconds >= (duration.inMilliseconds * 0.7);
      final shouldPreload = timeRemaining < const Duration(seconds: 60) || isPastThreshold;
      if (!shouldPreload) {
        return; // Too early to preload
      }
    }

    final effectiveCount = preloadCount.clamp(1, 5);
    if (isShuffle) {
      // Preload the tracks that actually play next in shuffle order when the
      // shuffle mapping is known. Falling back to random picks warmed tracks
      // that mostly won't play next and missed the real next track.
      if (shuffleIndices != null && shuffleIndices.isNotEmpty) {
        final pos = shuffleIndices.indexOf(currentIndex);
        if (pos >= 0) {
          for (int i = 1; i <= effectiveCount; i++) {
            final p = pos + i;
            if (p >= shuffleIndices.length) break;
            final idx = shuffleIndices[p];
            if (idx >= 0 && idx < queue.length) {
              _preloadTrack(queue[idx], priority: i);
            }
          }
          return;
        }
      }
      _preloadRandomTracks(queue, currentIndex, count: effectiveCount);
    } else {
      for (int i = 1; i <= effectiveCount; i++) {
        final idx = currentIndex + i;
        if (idx < queue.length) {
          _preloadTrack(queue[idx], priority: i);
        }
      }
    }
  }

  void _preloadRandomTracks(
    List<SongsTableData> queue,
    int currentIndex, {
    required int count,
  }) {
    final availableIndices = List.generate(queue.length, (i) => i)
      ..remove(currentIndex);
    if (availableIndices.isEmpty) return;

    final random = math.Random();
    availableIndices.shuffle(random);
    final chosen = availableIndices.take(count);

    int priority = 1;
    for (final idx in chosen) {
      _preloadTrack(queue[idx], priority: priority++);
    }
  }

  void _preloadTrack(SongsTableData song, {required int priority}) {
    // Local files are fast disk I/O, no network resolution required
    if (song.source == SongSource.local) return;

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

    unawaited(ArtworkUriResolver.resolveArtworkUri(song));

    onPreloadRequested(song, priority: priority);
  }

  /// Clears scheduled cache keys on queue changes.
  void clear() {
    _scheduledKeys.clear();
  }
}
