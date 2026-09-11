import 'dart:async';
import 'dart:math' as math;
import '../db/app_database.dart';
import 'artwork_uri_resolver.dart';

/// Intelligent queue analysis and preload scheduler.
class SmartPreloadScheduler {
  final Future<void> Function(SongsTableData song, {required int priority})
      onPreloadRequested;

  final Set<String> _scheduledKeys = {};

  SmartPreloadScheduler({required this.onPreloadRequested});

  /// Evaluates the current playback progress and schedules ahead-of-time preloads.
  void schedulePreloads({
    required List<SongsTableData> queue,
    required int currentIndex,
    required bool isShuffle,
    required Duration position,
    required Duration duration,
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

    final key = '${song.id}_${song.remoteId}';
    if (_scheduledKeys.contains(key)) return;
    _scheduledKeys.add(key);

    unawaited(ArtworkUriResolver.resolveArtworkUri(song));

    onPreloadRequested(song, priority: priority);
  }

  /// Clears scheduled cache keys on queue changes.
  void clear() {
    _scheduledKeys.clear();
  }
}
