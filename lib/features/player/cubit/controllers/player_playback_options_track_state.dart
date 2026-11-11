// lib/features/player/cubit/controllers/player_playback_options_track_state.dart
part of 'player_playback_options_controller.dart';

/// Track-change surface of the playback options controller: AB-loop state
/// mirroring/restoration and the per-track delay, plus the controller's
/// subscription disposal. Split out of player_playback_options_controller.dart
/// (pure code movement) to keep that file within the controller size budget.
extension PlayerPlaybackOptionsTrackState on PlayerPlaybackOptionsController {
  void _watchAbLoopChanges() {
    final manager = _abLoopManagerOrNull;
    if (manager == null) return;
    _abLoopSub = manager.changes.listen((_) => _syncAbLoopFromHandler());
  }

  /// The AB loop manager, or null when the handler does not expose one (partial
  /// test doubles). The dynamic boundary keeps a mock's null return for the
  /// non-nullable getter from throwing into the UI.
  AbLoopManager? get _abLoopManagerOrNull {
    try {
      final dynamic manager = _audioHandler.abLoopManager;
      return manager is AbLoopManager ? manager : null;
    } catch (_) {
      return null;
    }
  }

  /// Mirrors the engine's AB loop state into [PlaybackSlice] so the UI reflects
  /// what the loop manager will actually do (including persisted-loop restores).
  void _syncAbLoopFromHandler() {
    if (_isClosed()) return;
    final manager = _abLoopManagerOrNull;
    if (manager == null) return;
    final s = _getState();
    _emit(s.copyWith(
      playback: s.playback.copyWith(
        abPointA: manager.pointA,
        abPointB: manager.pointB,
        abLoopEnabled: manager.isEnabled,
      ),
    ));
  }

  /// Track-change hook: clears a stale loop scoped to the previous track,
  /// restores any persisted loop for [song], seeds the per-track delay, rating,
  /// volume override, and bookmark prompt from the engine/stores, and mirrors
  /// them into state so previous-track values never leak onto [song].
  Future<void> onCurrentSongChanged(SongsTableData song) async {
    _syncPerTrackState(song);
    _syncTrackDelayFromHandler();
    if (_abLoopManagerOrNull != null) {
      try {
        await _audioHandler.restoreAbLoopForCurrentSong(songId: song.id);
      } catch (e, st) {
        ErrorLogger.log('Failed to restore AB loop on track change',
            error: e,
            stackTrace: st,
            category: 'PlayerPlaybackOptionsController');
      }
    }
    _syncAbLoopFromHandler();
    await handleTrackChangeQuranMode(song);
    await _applyPerSongEqForTrack(song);
  }

  /// Resets and loads per-track rating, volume override, and bookmark position
  /// for [song] so values from the previous track cannot leak across transitions.
  void _syncPerTrackState(SongsTableData song) {
    if (_isClosed()) return;
    final s = _getState();
    if (s.currentSong != null && s.currentSong!.id != song.id) return;
    final key = song.id.toString();
    int rating = 0;
    try {
      rating = _songRatingStore.getRating(key);
    } catch (e, st) {
      ErrorLogger.log('Failed to read song rating for $key',
          error: e, stackTrace: st, category: 'PlayerPlaybackOptionsController');
    }
    double gainDb = 0.0;
    try {
      gainDb = _perSongVolumeStore.getGainDbForTrack(key);
    } catch (e, st) {
      ErrorLogger.log('Failed to read per-song volume gain for $key',
          error: e, stackTrace: st, category: 'PlayerPlaybackOptionsController');
    }
    final bookmark = storedBookmarkFor(song);
    final bookmarkPos = (bookmark != null && bookmark.positionMs > 0)
        ? Duration(milliseconds: bookmark.positionMs)
        : null;
    _emit(s.copyWith(
      playback: s.playback.copyWith(
        currentSongRating: rating,
        currentSongVolumeOverrideDb: gainDb,
        bookmarkPosition: bookmarkPos,
      ),
    ));
  }

  /// Mirrors the stored per-song EQ override into state and hands it to the
  /// EQ engine. Runs on every real track change so a stored override is
  /// actually applied (and the global preset restored when there is none).
  Future<void> _applyPerSongEqForTrack(SongsTableData song) async {
    final presetName =
        await _perSongEqStore.getPresetForTrackWhenReady(song.id.toString());
    if (_isClosed()) return;
    final s = _getState();
    if (s.currentSong?.id == song.id) {
      _emit(s.copyWith(
          playback: s.playback.copyWith(currentSongEqOverride: presetName)));
    }
    final applyOverride = _onPerSongEqOverride;
    if (applyOverride != null) {
      await applyOverride(song, presetName);
    }
  }

  Future<void> setSongEqOverrideById(int songId, String? presetName) async {
    await _perSongEqStore.setPresetForTrack(songId.toString(), presetName);
    final s = _getState();
    final currentSong = s.currentSong;
    if (currentSong?.id == songId) {
      _emit(s.copyWith(
          playback: s.playback.copyWith(currentSongEqOverride: presetName)));
      final applyOverride = _onPerSongEqOverride;
      if (applyOverride != null) {
        unawaited(applyOverride(currentSong!, presetName));
      }
    }
  }

  Future<void> setCurrentSongEqOverride(String? presetName) async {
    final songId = _getState().currentSong?.id;
    if (songId != null) {
      await setSongEqOverrideById(songId, presetName);
    }
  }

  /// Accepts either `(songId, presetName)` or `(presetName)` for the current
  /// track, matching the two call shapes the equalizer UI has always used.
  Future<void> setSongEqOverride(Object? songIdOrPreset,
      [String? presetName]) async {
    if (songIdOrPreset is int) {
      await setSongEqOverrideById(songIdOrPreset, presetName);
    } else if (songIdOrPreset is String) {
      await setCurrentSongEqOverride(songIdOrPreset);
    } else if (songIdOrPreset == null && presetName == null) {
      await setCurrentSongEqOverride(null);
    }
  }

  void _syncTrackDelayFromHandler() {
    final int delay;
    try {
      delay = _audioHandler.currentTrackDelayMs;
    } catch (_) {
      return;
    }
    if (_isClosed()) return;
    final s = _getState();
    _emit(s.copyWith(playback: s.playback.copyWith(trackDelayMs: delay)));
  }

  Future<void> setTrackBpm(SongsTableData song, double? bpm) =>
      _audioHandler.setTrackBpm(song, bpm);

  Future<void> setTrackDelayMs(int delayMs) async {
    final clamped =
        delayMs.clamp(TrackDelayManager.minMs, TrackDelayManager.maxMs);
    final s = _getState();
    _emit(s.copyWith(playback: s.playback.copyWith(trackDelayMs: clamped)));
    try {
      await _audioHandler.setCurrentTrackDelay(clamped);
    } catch (e, st) {
      ErrorLogger.log('Failed to set per-track delay',
          error: e,
          stackTrace: st,
          category: 'PlayerPlaybackOptionsController');
    }
  }

  void dispose() {
    _abLoopSub?.cancel();
    _abLoopSub = null;
  }
}
