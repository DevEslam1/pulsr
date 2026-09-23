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
      preampDb: s.selectedHeadphoneProfile?.preampGain ?? 0.0,
    );
  }

  Future<void> setQuranModeEnabled(bool enabled) async {
    final s = _getState();
    if (enabled == s.isQuranModeEnabled) return;
    if (enabled) {
      final snapshot = _captureQuranRestoreSnapshot(s);
      await _persistQuranSnapshot(snapshot);
      _emit(s.copyWith(dsp: s.dsp.copyWith(isQuranModeEnabled: true)));
      final profile = QuranModeProfile.forStyle(s.quranReciterStyle);
      await _applyQuranProfile(profile);
    } else {
      final snapshot = await loadQuranSnapshot();
      if (snapshot != null) {
        await _restoreFromSnapshot(snapshot);
      }
      await _clearQuranSnapshot();
      final current = _getState();
      _emit(current.copyWith(dsp: current.dsp.copyWith(isQuranModeEnabled: false)));
    }
  }

  void setQuranReciterStyle(QuranReciterStyle style) {
    final s = _getState();
    _emit(s.copyWith(dsp: s.dsp.copyWith(quranReciterStyle: style)));
    if (s.isQuranModeEnabled) {
      final profile = QuranModeProfile.forStyle(style);
      unawaited(_applyQuranProfile(profile));
    }
  }

  Future<void> setQuranAmbience(double v) async {
    final s = _getState();
    // Only enable reverb when Quran Mode is actively enabled and slider has a positive value.
    // If set to 0 or if Quran mode is inactive, do not unconditionally force reverb on.
    final enable = s.isQuranModeEnabled ? (v > 0.001) : s.isReverbEnabled;
    _emit(s.copyWith(
      dsp: s.dsp.copyWith(isReverbEnabled: enable, reverbWetDry: v),
    ));
    await _audioHandler.setReverb(enable, wetDry: v);
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
      ),
      playback: s.playback.copyWith(
        playbackSpeed: snapshot.playbackSpeed,
        isShuffle: snapshot.isShuffle,
      ),
    ));

    try {
      await _audioHandler.setEqualizerEnabled(snapshot.isEqEnabled);
      await _audioHandler.applyPreset(snapshot.eqPreset);
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
      ),
      playback: s.playback.copyWith(
        playbackSpeed: profile.playbackSpeed,
      ),
    ));

    try {
      await _audioHandler.setEqualizerEnabled(true);
      await _audioHandler.applyPreset(eqPreset);
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
    final snapshot = await loadQuranSnapshot();
    if (snapshot != null) {
      await _restoreFromSnapshot(snapshot);
      return;
    }
    final s = _getState();
    final profile = QuranModeProfile.forStyle(s.quranReciterStyle);
    await _applyQuranProfile(profile);
  }
}
