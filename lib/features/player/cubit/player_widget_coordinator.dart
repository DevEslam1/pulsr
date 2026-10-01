import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../widgets/widget_service.dart';
import 'player_constants.dart';
import 'player_state.dart';

/// Owns the home-screen widget push throttles and the "next 3 titles" cache so
/// [PlayerCubit] only has to hand over a state snapshot and its queue version
/// (I1). Extracted from the God-object without changing the cubit's public API.
class PlayerWidgetCoordinator {
  PlayerWidgetCoordinator(this._widgetService);

  final WidgetService? _widgetService;

  // B16: monotonic clock so widget-push throttling is immune to system clock
  // changes (matches PlayerScrobbleCoordinator).
  final Stopwatch _clock = Stopwatch()..start();
  int? _lastUpdateMs;
  int? _lastProgressUpdateMs;
  int? _cachedNextTitlesIndex;
  int? _cachedQueueLength;
  int? _cachedCurrentSongId;
  int? _cachedQueueVersion;
  int? _cachedNextIdsHash;
  List<String>? _cachedNextTitles;

  // FIX-L05: Extract nextTitlesCount constant and middle dot separator
  static const int nextTitlesCount = 3;

  /// Explicitly invalidates the next-titles cache (e.g. after a queue reorder or replace).
  void invalidateNextTitlesCache() {
    _cachedNextTitles = null;
    _cachedNextTitlesIndex = null;
    _cachedQueueLength = null;
    _cachedCurrentSongId = null;
    _cachedQueueVersion = null;
    _cachedNextIdsHash = null;
  }

  @visibleForTesting
  List<String>? nextTitles(PlayerState s, int queueVersion) {
    if (s.queue.isEmpty || s.currentIndex + 1 >= s.queue.length) {
      invalidateNextTitlesCache();
      _cachedQueueLength = 0;
      return null;
    }
    final nextIdsHash = Object.hashAll(
      s.queue.skip(s.currentIndex + 1).take(nextTitlesCount).map(
            (item) => Object.hash(
                item.id, item.title, item.artist, item.remoteId, item.path),
          ),
    );
    if (_cachedQueueVersion == queueVersion &&
        _cachedNextTitlesIndex == s.currentIndex &&
        _cachedQueueLength == s.queue.length &&
        _cachedCurrentSongId == s.currentSong?.id &&
        _cachedNextIdsHash == nextIdsHash) {
      return _cachedNextTitles;
    }
    _cachedQueueVersion = queueVersion;
    _cachedNextTitlesIndex = s.currentIndex;
    _cachedQueueLength = s.queue.length;
    _cachedCurrentSongId = s.currentSong?.id;
    _cachedNextIdsHash = nextIdsHash;
    _cachedNextTitles = s.queue
        .skip(s.currentIndex + 1)
        .take(nextTitlesCount)
        .map((item) => item.artist.isNotEmpty && item.artist != 'Unknown Artist'
            ? '${item.title} · ${item.artist}'
            : item.title)
        .toList();
    return _cachedNextTitles;
  }

  void updateThrottled(PlayerState s, int queueVersion, {bool force = false}) {
    if (!_clock.isRunning) _clock.start();
    final now = _clock.elapsedMilliseconds;
    if (!force &&
        _lastUpdateMs != null &&
        now - _lastUpdateMs! <
            PlayerConstants.widgetThrottleDuration.inMilliseconds) {
      return;
    }
    _lastUpdateMs = now;
    _lastProgressUpdateMs = now;
    String? queueCover;
    if (s.queue.isNotEmpty && s.currentIndex + 1 < s.queue.length) {
      final nextSong = s.queue[s.currentIndex + 1];
      queueCover = nextSong.artworkUri ?? nextSong.remoteArtworkUrl;
    }
    _widgetService?.updateNowPlaying(
      song: s.currentSong,
      isPlaying: s.isPlaying,
      position: s.position,
      duration: s.duration,
      isFavorite: s.currentSong?.isFavorite ?? false,
      isShuffle: s.isShuffle,
      repeatMode: switch (s.repeatMode) {
        PlayerRepeatMode.one => 'one',
        PlayerRepeatMode.all => 'all',
        PlayerRepeatMode.off => 'off',
      },
      nextQueueTitles: nextTitles(s, queueVersion),
      queueCover: queueCover,
    );
  }

  void updateProgressThrottled(PlayerState s) {
    if (!_clock.isRunning) _clock.start();
    final now = _clock.elapsedMilliseconds;
    if (_lastProgressUpdateMs != null &&
        now - _lastProgressUpdateMs! <
            PlayerConstants.widgetThrottleDuration.inMilliseconds) {
      return;
    }
    _lastProgressUpdateMs = now;
    try {
      unawaited(_widgetService?.updateProgress(
        isPlaying: s.isPlaying,
        position: s.position,
        duration: s.duration,
      ));
    } catch (_) {}
  }

  @visibleForTesting
  bool get isClockRunning => _clock.isRunning;

  void reset() {
    _clock.reset();
    _lastUpdateMs = null;
    _lastProgressUpdateMs = null;
    _cachedNextTitles = null;
    _cachedNextTitlesIndex = null;
    _cachedQueueLength = null;
    _cachedCurrentSongId = null;
    _cachedQueueVersion = null;
    _cachedNextIdsHash = null;
  }

  void dispose() {
    _clock.stop();
    _clock.reset();
    _lastUpdateMs = null;
    _lastProgressUpdateMs = null;
    _cachedNextTitles = null;
    _cachedNextTitlesIndex = null;
    _cachedQueueLength = null;
    _cachedCurrentSongId = null;
    _cachedQueueVersion = null;
    _cachedNextIdsHash = null;
  }
}
