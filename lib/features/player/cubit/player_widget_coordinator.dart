// lib/features/player/cubit/player_widget_coordinator.dart
import 'package:flutter/foundation.dart';

import '../../widgets/widget_service.dart';
import 'player_state.dart';

/// Owns the home-screen widget push throttles and the "next 3 titles" cache so
/// [PlayerCubit] only has to hand over a state snapshot and its queue version
/// (I1). Extracted from the God-object without changing the cubit's public API.
class PlayerWidgetCoordinator {
  PlayerWidgetCoordinator(this._widgetService);

  final WidgetService? _widgetService;

  DateTime? _lastUpdateTime;
  DateTime? _lastProgressUpdateTime;
  int? _cachedNextTitlesIndex;
  int? _cachedQueueLength;
  int? _cachedCurrentSongId;
  int? _cachedQueueVersion;
  List<String>? _cachedNextTitles;

  // FIX-L05: Extract nextTitlesCount constant and middle dot separator
  static const int nextTitlesCount = 3;

  @visibleForTesting
  List<String>? nextTitles(PlayerState s, int queueVersion) {
    if (s.queue.isEmpty || s.currentIndex + 1 >= s.queue.length) {
      _cachedNextTitles = null;
      _cachedNextTitlesIndex = null;
      _cachedQueueLength = 0;
      _cachedCurrentSongId = null;
      return null;
    }
    if (_cachedQueueVersion == queueVersion &&
        _cachedNextTitlesIndex == s.currentIndex &&
        _cachedQueueLength == s.queue.length &&
        _cachedCurrentSongId == s.currentSong?.id) {
      return _cachedNextTitles;
    }
    _cachedQueueVersion = queueVersion;
    _cachedNextTitlesIndex = s.currentIndex;
    _cachedQueueLength = s.queue.length;
    _cachedCurrentSongId = s.currentSong?.id;
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
    final now = DateTime.now();
    if (!force &&
        _lastUpdateTime != null &&
        now.difference(_lastUpdateTime!).inMilliseconds < 1000) {
      return;
    }
    _lastUpdateTime = now;
    _lastProgressUpdateTime = now;
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
    );
  }

  void updateProgressThrottled(PlayerState s) {
    final now = DateTime.now();
    if (_lastProgressUpdateTime != null &&
        now.difference(_lastProgressUpdateTime!).inMilliseconds < 1000) {
      return;
    }
    _lastProgressUpdateTime = now;
    _widgetService?.updateProgress(
      isPlaying: s.isPlaying,
      position: s.position,
      duration: s.duration,
    );
  }
}
