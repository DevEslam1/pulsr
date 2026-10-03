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
    if (_isTogglingQuranMode) return;
    _isTogglingQuranMode = true;
    try {
      final s = _getState();
      if (enabled == s.isQuranModeEnabled) return;
      if (enabled && !checkDspGuard('Quran Mode')) return;

      final persisted = await _quranManager.setEnabled(enabled);
      if (!persisted) {
        if (!isClosed) {
          final current = _getState();
          _emit(current.copyWith(
            playback: current.playback.copyWith(
                errorMessage: 'Failed to save Quran Mode setting'),
          ));
        }
        return;
      }
      if (isClosed) return;

      if (enabled) {
        final snapshot = _captureQuranRestoreSnapshot(_getState());
        _quranManager.setRestoreSnapshot(snapshot);
        await _persistQuranSnapshot(snapshot);
        if (isClosed) return;
        final current = _getState();
        _emit(current.copyWith(dsp: current.dsp.copyWith(isQuranModeEnabled: true)));
        final profile = QuranModeProfile.forStyle(current.quranReciterStyle);
        await _applyQuranProfile(profile);
      } else {
        final snapshot = await loadQuranSnapshot() ?? _quranManager.restoreSnapshot;
        if (snapshot != null) {
          final restored = await _restoreFromSnapshot(snapshot);
          if (!restored) {
            if (!isClosed) {
              final current = _getState();
              _emit(current.copyWith(
                playback: current.playback.copyWith(
                    errorMessage: 'Failed to restore audio settings from Quran Mode'),
              ));
            }
            return;
          }
        } else {
          await _restoreSafeDefaults();
        }
        _quranManager.setRestoreSnapshot(null);
        await _clearQuranSnapshot();
        if (isClosed) return;
        final current = _getState();
        _emit(current.copyWith(dsp: current.dsp.copyWith(isQuranModeEnabled: false)));
      }
    } finally {
      _isTogglingQuranMode = false;
    }
  }

  Future<void> setQuranReciterStyle(QuranReciterStyle style) async {
    final gen = ++_reciterStyleGen;
    final s = _getState();
    _emit(s.copyWith(dsp: s.dsp.copyWith(quranReciterStyle: style)));
    try {
      await _quranManager.setStyle(style);
      if (isClosed || gen != _reciterStyleGen) return;
      if (_getState().isQuranModeEnabled) {
        if (!checkDspGuard('Quran Mode')) return;
        final profile = QuranModeProfile.forStyle(style);
        await _applyQuranProfile(profile);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to set Quran reciter style',
          error: e, stackTrace: st, category: 'PlayerPlaybackOptionsQuran');
    }
  }

  Future<void> setQuranAmbience(double v) async {
    final s = _getState();
    if (!s.isQuranModeEnabled) return;
    final clamped = v.clamp(0.0, 0.6);
    if (clamped > 0.001 && !checkDspGuard('Quran Ambience')) return;
    final enable = clamped > 0.001;
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

  Future<bool> _restoreFromSnapshot(QuranRestoreSnapshot snapshot) async {
    final s = _getState();
    final eqPreset = snapshot.eqPreset;
    _emit(s.copyWith(
      dsp: s.dsp.copyWith(
        isEqEnabled: eqPreset != null ? snapshot.isEqEnabled : s.isEqEnabled,
        eqPreset: eqPreset ?? s.eqPreset,
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
      ),
    ));

    try {
      if (eqPreset != null) {
        await _audioHandler.setEqualizerEnabled(snapshot.isEqEnabled);
        await _audioHandler.applyPreset(eqPreset);
      }
      await _audioHandler.applyHeadphoneProfile(snapshot.headphoneProfile);
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
      await _audioHandler.setSpeed(snapshot.playbackSpeed);
      return true;
    } catch (e, st) {
      ErrorLogger.log('Failed to restore from Quran snapshot',
          error: e,
          stackTrace: st,
          category: 'PlayerPlaybackOptionsQuran');
      return false;
    }
  }

  /// Fallback used when Quran Mode is disabled but no restorable snapshot
  /// exists (neither persisted nor in memory). Resets all Quran-controlled
  /// DSP stages to safe defaults, including neutral preamp and flat preset.
  Future<void> _restoreSafeDefaults() async {
    final s = _getState();
    final defaultPreset = EqPreset.defaultPresets.first;
    _emit(s.copyWith(
      dsp: s.dsp.copyWith(
        isEqEnabled: false,
        eqPreset: defaultPreset,
        selectedHeadphoneProfile: null,
        preampDb: 0.0,
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
      await _audioHandler.setPreamp(0.0);
      await _audioHandler.applyPreset(defaultPreset);
      await _audioHandler.applyHeadphoneProfile(null);
      await _audioHandler.setEqualizerEnabled(false);
      await _audioHandler.setReverb(false, wetDry: 0.0);
      await _audioHandler.setSaturation(false);
      await _audioHandler.setDynamicsPreset(s.dynamicsPreset, enabled: false);
      await _audioHandler.setSpeed(1.0);
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
        selectedHeadphoneProfile: null,
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
      // Clear headphone profile in engine so AutoEQ curves don't conflict with Quran EQ
      await _audioHandler.applyHeadphoneProfile(null);
      await _audioHandler.setPreamp(profile.preampDb);
      await _audioHandler.applyPreset(eqPreset);
      await _audioHandler.setEqualizerEnabled(true);
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
      await _audioHandler.setSpeed(profile.playbackSpeed);
    } catch (e, st) {
      ErrorLogger.log('Failed to apply Quran profile',
          error: e,
          stackTrace: st,
          category: 'PlayerPlaybackOptionsQuran');
    }
  }

  Future<void> reapplyQuranProfile() async {
    final s = _getState();
    if (s.isQuranModeEnabled) {
      if (!checkDspGuard('Quran Mode')) return;
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
