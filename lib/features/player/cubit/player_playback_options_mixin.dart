part of 'player_cubit.dart';

mixin PlayerPlaybackOptions on PulsrCubit<PlayerState> {
  // Sleep Timer
  void startSleepTimer(int minutes) {
    final duration = Duration(minutes: minutes);
    _audioHandler.startSleepTimer(duration);
    safeEmit(state.copyWith(sleepTimerRemaining: duration));
  }

  void startAbsoluteSleepTimer(DateTime stopTime) {
    _audioHandler.startAbsoluteSleepTimer(stopTime);
    final diff = stopTime.difference(DateTime.now());
    safeEmit(state.copyWith(
        sleepTimerRemaining:
            diff.isNegative ? diff + const Duration(days: 1) : diff));
  }

  void startEndOfTrackTimer() {
    _audioHandler.startEndOfTrackTimer();
    final remaining = state.duration > state.position
        ? state.duration - state.position
        : const Duration(minutes: 1);
    safeEmit(state.copyWith(sleepTimerRemaining: remaining));
  }

  void startAfterNTracksTimer(int trackCount) {
    _audioHandler.startAfterNTracksTimer(trackCount);
    safeEmit(state.copyWith(sleepTimerRemaining: null));
  }

  void startEndOfQueueTimer() {
    _audioHandler.startEndOfQueueTimer();
    safeEmit(state.copyWith(sleepTimerRemaining: null));
  }

  void cancelSleepTimer() {
    _audioHandler.cancelSleepTimer();
    safeEmit(state.copyWith(sleepTimerRemaining: null));
  }

  int? get sleepTimerRemainingTracks => _audioHandler.sleepTimerRemainingTracks;

  SleepTimerMode get sleepTimerMode => _audioHandler.sleepTimerMode;

  bool get isEndOfQueueSleepTimer =>
      sleepTimerMode == SleepTimerMode.endOfQueue;

  Stream<int?> get sleepTimerRemainingTracksStream =>
      _audioHandler.sleepTimerRemainingTracksStream;

  // Playback Speed
  double get minPlaybackSpeed => _audioHandler.minPlaybackSpeed;

  double get maxPlaybackSpeed => _audioHandler.maxPlaybackSpeed;

  Future<void> _loadPlaybackSpeed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getDouble(PrefsKeys.playbackSpeed) ?? 1.0;
      // Clamp to the engine's *current* range so a persisted extended speed
      // (0.1–8.0) is not silently rewritten to the 0.5–3.0 default band.
      final speed = raw.isFinite
          ? raw.clamp(
              _audioHandler.minPlaybackSpeed, _audioHandler.maxPlaybackSpeed)
          : 1.0;
      await _audioHandler.setSpeed(speed);
      safeEmit(state.copyWith(playbackSpeed: speed));
    } catch (e, st) {
      ErrorLogger.log('Failed to load playback speed from SharedPreferences',
          error: e, stackTrace: st, category: 'PlayerCubit');
    }
  }

  Future<void> setPlaybackSpeed(double speed) async {
    if (!speed.isFinite) return;
    // Honour the engine's active range (0.25–4.0, or 0.1–8.0 when the
    // advanced-speed setting is on) instead of a hardcoded band.
    final clamped = speed
        .clamp(_audioHandler.minPlaybackSpeed, _audioHandler.maxPlaybackSpeed);
    _lastSpeedPushed = clamped;
    _lastSpeedPushAt = DateTime.now();
    try {
      await _audioHandler.setSpeed(clamped);
    } catch (e, st) {
      ErrorLogger.log('Set playback speed failed',
          error: e, stackTrace: st, category: 'PlayerCubit');
      if (!isClosed) {
        safeEmit(state.copyWith(errorMessage: 'Speed change failed'));
      }
      return;
    }
    safeEmit(state.copyWith(playbackSpeed: clamped));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(PrefsKeys.playbackSpeed, clamped);
    _setQueueSlot(
      state.activeQueueSlot,
      songs: state.queue,
      currentIndex: state.currentIndex,
      position: state.position,
      speed: clamped,
    );
    _debouncedPersistQueueSlots();
  }

  // Playback Pitch / Tone Control (PowerAmp parity)
  Future<void> _loadPlaybackPitch() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getDouble(PrefsKeys.playbackPitch) ?? 1.0;
      final pitch = raw.isFinite ? raw.clamp(0.5, 2.0) : 1.0;
      await _audioHandler.setPitch(pitch);
      safeEmit(state.copyWith(playbackPitch: pitch));
    } catch (e, st) {
      ErrorLogger.log('Failed to load playback pitch from SharedPreferences',
          error: e, stackTrace: st, category: 'PlayerCubit');
    }
  }

  Future<void> setPlaybackPitch(double pitch) async {
    if (!pitch.isFinite) return;
    final clamped = pitch.clamp(0.5, 2.0);
    try {
      await _audioHandler.setPitch(clamped);
    } catch (e, st) {
      ErrorLogger.log('Set playback pitch failed',
          error: e, stackTrace: st, category: 'PlayerCubit');
      if (!isClosed) {
        safeEmit(state.copyWith(errorMessage: 'Pitch change failed'));
      }
      return;
    }
    safeEmit(state.copyWith(playbackPitch: clamped));
  }

  // Per-Song Star Rating (1 to 5 stars, 0 = unrated)
  Future<void> setSongRating(int songId, int rating) async {
    await _songRatingStore.setRating(songId.toString(), rating);
    if (state.currentSong?.id == songId) {
      safeEmit(state.copyWith(currentSongRating: rating));
    }
  }

  // Per-Song EQ Preset Override
  Future<void> setSongEqOverride(int songId, String? presetName) async {
    await _perSongEqStore.setPresetForTrack(songId.toString(), presetName);
    if (state.currentSong?.id != songId) return;

    if (presetName == null) {
      safeEmit(state.copyWith(currentSongEqOverride: null));
      if (_perSongOverrideActive && _globalEqBackup != null) {
        final restore = _globalEqBackup!;
        final profileRestore = _globalHeadphoneProfileBackup;
        _globalEqBackup = null;
        _globalHeadphoneProfileBackup = null;
        _perSongOverrideActive = false;
        // Re-apply the AutoEQ profile as a profile (not a plain preset), so the
        // global headphone selection is not silently deselected in the UI.
        if (profileRestore != null) {
          await applyHeadphoneProfile(profileRestore, isPerSongRestore: true);
        } else {
          await applyPreset(restore, isPerSongRestore: true);
        }
      }
      return;
    }

    // Resolve BEFORE reporting: emitting currentSongEqOverride for a name that
    // matches nothing would show a phantom override with no audible effect.
    final lower = presetName.toLowerCase();
    final match = EqPreset.defaultPresets
        .where((p) => p.name.toLowerCase() == lower)
        .firstOrNull;
    final HeadphoneProfile? profile =
        match == null ? await _headphoneProfileByName(presetName) : null;
    if (match == null && profile == null) {
      if (!isClosed) {
        safeEmit(state.copyWith(
          currentSongEqOverride: null,
          errorMessage: 'Unknown EQ preset: $presetName',
        ));
      }
      return;
    }

    safeEmit(state.copyWith(currentSongEqOverride: presetName));
    // Assigning an override mid-song must mark it active and snapshot the
    // pre-override preset, otherwise clearing it (or the next song without an
    // override) has nothing to restore and the per-song curve leaks into the
    // rest of the queue.
    if (!_perSongOverrideActive) {
      _globalEqBackup = state.eqPreset;
      _globalHeadphoneProfileBackup = state.selectedHeadphoneProfile;
      _perSongOverrideActive = true;
    }
    if (match != null) {
      await applyPreset(match, isPerSongRestore: true);
    } else {
      await applyHeadphoneProfile(profile, isPerSongRestore: true);
    }
  }

  // Per-Song Volume Override (-12.0 to +6.0 dB)
  Future<void> setSongVolumeOverride(int songId, double gainDb) async {
    await _perSongVolumeStore.setGainDbForTrack(songId.toString(), gainDb);
    if (state.currentSong?.id == songId) {
      safeEmit(state.copyWith(currentSongVolumeOverrideDb: gainDb));
      await _audioHandler.setVolume(_audioHandler.volume);
    }
  }

  // EQ Preset JSON Import & Export
  String exportCurrentEqPreset() {
    return _audioHandler.exportPresetToJson(state.eqPreset);
  }

  Future<bool> importEqPreset(String jsonString) async {
    final success = await _audioHandler.importPresetFromJson(jsonString);
    if (success) {
      _syncAudioEffects();
    }
    return success;
  }

  // Volume Control (handler-owned; no PlayerState.volume by design)
  Future<void> setVolume(double volume) async {
    try {
      await _audioHandler.setVolume(volume);
    } catch (e, st) {
      ErrorLogger.log('Set volume failed',
          error: e, stackTrace: st, category: 'PlayerCubit');
      if (!isClosed) {
        safeEmit(state.copyWith(errorMessage: 'Volume change failed'));
      }
    }
  }

  Future<void> adjustVolume(double delta) async {
    try {
      final current = _audioHandler.volume;
      final target = (current + delta).clamp(0.0, 1.0);
      await _audioHandler.setVolume(target);
    } catch (e, st) {
      ErrorLogger.log('Adjust volume failed',
          error: e, stackTrace: st, category: 'PlayerCubit');
      if (!isClosed) {
        safeEmit(state.copyWith(errorMessage: 'Volume change failed'));
      }
    }
  }

  // Overlay toggles (Lyrics / Queue)
  void toggleLyricsVisibility() {
    safeEmit(state.copyWith(
      isLyricsVisible: !state.isLyricsVisible,
      isQueueVisible: false,
    ));
  }

  void toggleQueueVisibility() {
    safeEmit(state.copyWith(
      isQueueVisible: !state.isQueueVisible,
      isLyricsVisible: false,
    ));
  }

  void resetOverlayViews() {
    if (state.isLyricsVisible || state.isQueueVisible) {
      safeEmit(state.copyWith(
        isLyricsVisible: false,
        isQueueVisible: false,
      ));
    }
  }

  // Requires: provided by the composing class (same library).
  PulsrAudioHandler get _audioHandler;

  // Requires: provided by the composing class (same library).
  void _debouncedPersistQueueSlots();

  // Requires: provided by the composing class (same library).
  EqPreset? get _globalEqBackup;
  set _globalEqBackup(EqPreset? value);

  // Requires: provided by the composing class (same library).
  HeadphoneProfile? get _globalHeadphoneProfileBackup;
  set _globalHeadphoneProfileBackup(HeadphoneProfile? value);

  // Requires: provided by the composing class (same library).
  // ignore: unused_element
  DateTime? get _lastSpeedPushAt;
  set _lastSpeedPushAt(DateTime? value);

  // Requires: provided by the composing class (same library).
  // ignore: unused_element
  double? get _lastSpeedPushed;
  set _lastSpeedPushed(double? value);

  // Requires: provided by the composing class (same library).
  PerSongEqStore get _perSongEqStore;

  // Requires: provided by the composing class (same library).
  bool get _perSongOverrideActive;
  set _perSongOverrideActive(bool value);

  // Requires: provided by the composing class (same library).
  PerSongVolumeStore get _perSongVolumeStore;

  // Requires: provided by the composing class (same library).
  void _setQueueSlot(
    int slot, {
    required List<SongsTableData> songs,
    required int currentIndex,
    required Duration position,
    required double speed,
  });

  // Requires: provided by the composing class (same library).
  SongRatingStore get _songRatingStore;

  // Requires: provided by the composing class (same library).
  void _syncAudioEffects();

  // Requires: provided by the composing class (same library).
  Future<void> applyHeadphoneProfile(HeadphoneProfile? profile, {bool isPerSongRestore = false});

  // Requires: provided by the composing class (same library).
  Future<HeadphoneProfile?> _headphoneProfileByName(String name);

  // Requires: provided by the composing class (same library).
  Future<void> applyPreset(EqPreset preset, {bool isPerSongRestore = false});
}
