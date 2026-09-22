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
    } else {
      await _clearQuranSnapshot();
      _emit(s.copyWith(dsp: s.dsp.copyWith(isQuranModeEnabled: false)));
    }
  }

  void setQuranReciterStyle(QuranReciterStyle style) {
    final s = _getState();
    _emit(s.copyWith(dsp: s.dsp.copyWith(quranReciterStyle: style)));
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

  Future<void> reapplyQuranProfile() async {}
}
