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
  /// restores any persisted loop for [song], seeds the per-track delay from the
  /// engine, and mirrors both into state.
  Future<void> onCurrentSongChanged(SongsTableData song) async {
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
