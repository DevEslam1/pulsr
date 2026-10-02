// lib/features/player/cubit/controllers/player_playback_options_quran.dart
part of 'player_playback_options_controller.dart';

/// Quran Mode DSP application and its restore-snapshot persistence. Extracted
/// from [PlayerPlaybackOptionsController] to keep that controller <= 400 lines.
extension PlayerPlaybackOptionsQuran on PlayerPlaybackOptionsController {
  Future<void> _persistQuranSnapshot(QuranRestoreSnapshot snapshot) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          PrefsKeys.quranRestoreSnapshot, jsonEncode(snapshot.toJson()));
    } catch (e, st) {
      ErrorLogger.log('Failed to persist Quran Mode restore snapshot',
          error: e,
          stackTrace: st,
          category: 'PlayerPlaybackOptionsController');
    }
  }

  Future<QuranRestoreSnapshot?> loadQuranSnapshot() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(PrefsKeys.quranRestoreSnapshot);
      if (raw == null || raw.isEmpty) return null;
      return QuranRestoreSnapshot.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (e, st) {
      ErrorLogger.log('Failed to load Quran Mode restore snapshot',
          error: e,
          stackTrace: st,
          category: 'PlayerPlaybackOptionsController');
      return null;
    }
  }

  Future<void> _clearQuranSnapshot() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(PrefsKeys.quranRestoreSnapshot);
    } catch (_) {}
  }

  QuranRestoreSnapshot _captureQuranRestoreSnapshot(PlayerState s) {
    return QuranRestoreSnapshot(
      eqPreset: s.eqPreset,
      isEqEnabled: s.isEqEnabled,
      headphoneProfile: s.selectedHeadphoneProfile,
      isReverbEnabled: s.isReverbEnabled,
      reverbPreset: s.reverbPreset,
      reverbWetDry: s.reverbWetDry,
      isDynamicsEnabled: s.isDynamicsEnabled,
      dynamicsPreset: s.dynamicsPreset,
      isSaturationEnabled: s.isSaturationEnabled,
      saturationDrive: s.saturationDrive,
      saturationMix: s.saturationMix,
      saturationTilt: s.saturationTilt,
      playbackSpeed: s.playbackSpeed,
      isShuffle: s.isShuffle,
      preampDb: s.preampDb,
    );
  }

  /// Restores the persisted Quran Mode selection on startup. When the mode was
  /// on at last exit, re-captures a pre-Quran snapshot and re-applies the saved
  /// reciter profile so the live DSP matches the toggle.
  Future<void> restoreQuranMode() async {
    try {
      final profile = await _quranManager.restoreInitialState();
      if (profile == null || isClosed) return;
      final s = _getState();
      if (s.isQuranModeEnabled) return;
      // Keep the snapshot captured when the mode was turned on; only capture a
      // fresh one when there is none (e.g. prefs were cleared) so a relaunch
      // never snapshots an already-Quran-shaped native DSP state.
      final persisted = await loadQuranSnapshot();
      final snapshot = persisted ?? _captureQuranRestoreSnapshot(s);
      _quranManager.setRestoreSnapshot(snapshot);
      if (persisted == null) await _persistQuranSnapshot(snapshot);
      if (isClosed) return;
      final restored = _getState();
      _emit(restored.copyWith(
        dsp: restored.dsp.copyWith(
          isQuranModeEnabled: true,
          quranReciterStyle: profile.style,
        ),
      ));
      await _applyQuranProfile(profile);
    } catch (e, st) {
      ErrorLogger.log('Failed to restore Quran Mode on init',
          error: e, stackTrace: st, category: 'PlayerPlaybackOptionsQuran');
    }
  }

  Future<void> setQuranModeEnabled(bool enabled) async {
    final s = _getState();
    if (enabled == s.isQuranModeEnabled) return;
    await _quranManager.setEnabled(enabled);
    if (enabled) {
      final snapshot = _captureQuranRestoreSnapshot(s);
      // Keep the snapshot on the manager as well as persisting it: a
      // failed/corrupt prefs write must not leave disabling unable to restore
      // the real DSP.
      _quranManager.setRestoreSnapshot(snapshot);
      await _persistQuranSnapshot(snapshot);
      _emit(s.copyWith(dsp: s.dsp.copyWith(isQuranModeEnabled: true)));
      final profile = QuranModeProfile.forStyle(s.quranReciterStyle);
      await _applyQuranProfile(profile);
    } else {
      // Prefer the persisted snapshot; fall back to the in-memory copy when the
      // persisted one is missing or corrupt (loadQuranSnapshot returns null).
      final snapshot = await loadQuranSnapshot() ?? _quranManager.restoreSnapshot;
      if (snapshot != null) {
        await _restoreFromSnapshot(snapshot);
      } else {
        // Neither source is available: never flip the toggle off while Quran
        // DSP stays applied. Reset the Quran-controlled effects to safe
        // defaults so the toggle and the real effect chain agree.
        await _restoreSafeDefaults();
      }
      _quranManager.setRestoreSnapshot(null);
      await _clearQuranSnapshot();
      final current = _getState();
      _emit(current.copyWith(dsp: current.dsp.copyWith(isQuranModeEnabled: false)));
    }
  }

  void setQuranReciterStyle(QuranReciterStyle style) {
    final s = _getState();
    _emit(s.copyWith(dsp: s.dsp.copyWith(quranReciterStyle: style)));
    unawaited(_quranManager.setStyle(style));
    if (s.isQuranModeEnabled) {
      final profile = QuranModeProfile.forStyle(style);
      unawaited(_applyQuranProfile(profile));
    }
  }

  Future<void> setQuranAmbience(double v) async {
    final clamped = v.clamp(0.0, 0.6);
    final s = _getState();
    // Only enable reverb when Quran Mode is actively enabled and slider has a positive value.
    // If set to 0 or if Quran mode is inactive, do not unconditionally force reverb on.
    final enable =
        s.isQuranModeEnabled ? (clamped > 0.001) : s.isReverbEnabled;
    _emit(s.copyWith(
      dsp: s.dsp.copyWith(isReverbEnabled: enable, reverbWetDry: clamped),
    ));
    try {
      await _audioHandler.setReverb(enable, wetDry: clamped);
    } catch (e, st) {
      ErrorLogger.log('Failed to set Quran ambience',
          error: e, stackTrace: st, category: 'PlayerPlaybackOptionsQuran');
    }
  }

  Future<void> _restoreFromSnapshot(QuranRestoreSnapshot snapshot) async {
    final s = _getState();
    _emit(s.copyWith(
      dsp: s.dsp.copyWith(
        isEqEnabled: snapshot.isEqEnabled,
        eqPreset: snapshot.eqPreset,
        selectedHeadphoneProfile: snapshot.headphoneProfile,
        isReverbEnabled: snapshot.isReverbEnabled,
        reverbPreset: snapshot.reverbPreset,
        reverbWetDry: snapshot.reverbWetDry,
        isSaturationEnabled: snapshot.isSaturationEnabled,
        saturationDrive: snapshot.saturationDrive,
        saturationMix: snapshot.saturationMix,
        saturationTilt: snapshot.saturationTilt,
        isDynamicsEnabled: snapshot.isDynamicsEnabled,
        dynamicsPreset: snapshot.dynamicsPreset,
        preampDb: snapshot.preampDb,
      ),
      playback: s.playback.copyWith(
        playbackSpeed: snapshot.playbackSpeed,
        isShuffle: snapshot.isShuffle,
      ),
    ));

    try {
      await _audioHandler.setEqualizerEnabled(snapshot.isEqEnabled);
      await _audioHandler.applyPreset(snapshot.eqPreset);
      await _audioHandler.setPreamp(snapshot.preampDb);
      await _audioHandler.setReverb(
        snapshot.isReverbEnabled,
        preset: snapshot.reverbPreset,
        wetDry: snapshot.reverbWetDry,
      );
      await _audioHandler.setSaturation(
        snapshot.isSaturationEnabled,
        drive: snapshot.saturationDrive,
        mix: snapshot.saturationMix,
        tilt: snapshot.saturationTilt,
      );
      await _audioHandler.setDynamicsPreset(
        snapshot.dynamicsPreset,
        enabled: snapshot.isDynamicsEnabled,
      );
      await setPlaybackSpeed(snapshot.playbackSpeed);
      if (snapshot.isShuffle != s.isShuffle) {
        await _audioHandler.setShuffleMode(
          snapshot.isShuffle
              ? AudioServiceShuffleMode.all
              : AudioServiceShuffleMode.none,
        );
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to restore from Quran snapshot',
          error: e,
          stackTrace: st,
          category: 'PlayerPlaybackOptionsQuran');
    }
  }

  /// Fallback used when Quran Mode is disabled but no restorable snapshot
  /// exists (neither persisted nor in memory). Turns the Quran-applied DSP
  /// back off so the toggle and the real effect chain agree, rather than
  /// leaving Quran EQ/reverb/saturation/dynamics/speed applied. Mirrors the
  /// "off" half of [_restoreFromSnapshot] without captured values; shuffle is
  /// intentionally left untouched since Quran Mode does not change it.
  Future<void> _restoreSafeDefaults() async {
    final s = _getState();
    _emit(s.copyWith(
      dsp: s.dsp.copyWith(
        isEqEnabled: false,
        isReverbEnabled: false,
        reverbWetDry: 0.0,
        isSaturationEnabled: false,
        isDynamicsEnabled: false,
      ),
      playback: s.playback.copyWith(
        playbackSpeed: 1.0,
      ),
    ));

    try {
      await _audioHandler.setEqualizerEnabled(false);
      await _audioHandler.setReverb(false, wetDry: 0.0);
      await _audioHandler.setSaturation(false);
      await _audioHandler.setDynamicsPreset(s.dynamicsPreset, enabled: false);
      await setPlaybackSpeed(1.0);
    } catch (e, st) {
      ErrorLogger.log('Failed to restore safe defaults while disabling Quran Mode',
          error: e,
          stackTrace: st,
          category: 'PlayerPlaybackOptionsQuran');
    }
  }

  Future<void> _applyQuranProfile(QuranModeProfile profile) async {
    final s = _getState();
    final eqPreset = profile.toEqPreset();

    _emit(s.copyWith(
      dsp: s.dsp.copyWith(
        isEqEnabled: true,
        eqPreset: eqPreset,
        isReverbEnabled: profile.reverbEnabled,
        reverbPreset: profile.reverbPreset.wireValue,
        reverbWetDry: profile.reverbWetDry,
        isSaturationEnabled: profile.saturationEnabled,
        saturationDrive: profile.saturationDrive,
        saturationMix: profile.saturationMix,
        saturationTilt: profile.saturationTilt,
        isDynamicsEnabled: profile.dynamicsEnabled,
        dynamicsPreset: profile.dynamicsPreset,
        preampDb: profile.preampDb,
      ),
      playback: s.playback.copyWith(
        playbackSpeed: profile.playbackSpeed,
      ),
    ));

    try {
      await _audioHandler.setEqualizerEnabled(true);
      await _audioHandler.applyPreset(eqPreset);
      await _audioHandler.setPreamp(profile.preampDb);
      await _audioHandler.setReverb(
        profile.reverbEnabled,
        preset: profile.reverbPreset.wireValue,
        wetDry: profile.reverbWetDry,
      );
      await _audioHandler.setSaturation(
        profile.saturationEnabled,
        drive: profile.saturationDrive,
        mix: profile.saturationMix,
        tilt: profile.saturationTilt,
      );
      await _audioHandler.setDynamicsPreset(
        profile.dynamicsPreset,
        enabled: profile.dynamicsEnabled,
      );
      await setPlaybackSpeed(profile.playbackSpeed);
    } catch (e, st) {
      ErrorLogger.log('Failed to apply Quran profile',
          error: e,
          stackTrace: st,
          category: 'PlayerPlaybackOptionsQuran');
    }
  }

  Future<void> reapplyQuranProfile() async {
    final s = _getState();
    // "Reset Profile" must re-apply the reciter's Quran profile while the mode
    // is on. The pre-Quran snapshot is only meaningful when the mode is being
    // disabled (or is already off), never for a reset.
    if (s.isQuranModeEnabled) {
      final profile = QuranModeProfile.forStyle(s.quranReciterStyle);
      await _applyQuranProfile(profile);
      return;
    }
    final snapshot = await loadQuranSnapshot() ?? _quranManager.restoreSnapshot;
    if (snapshot != null) {
      await _restoreFromSnapshot(snapshot);
    }
  }
}
