// lib/features/player/cubit/controllers/dsp_eq_engine.dart
// FIX-A1: Modular DSP Equalizer Engine
import 'dart:async';
import '../../../../core/utils/error_logger.dart';
import '../../../../data/audio/audio_handler.dart';
import '../../../../domain/models/eq_preset.dart';
import '../../../../domain/models/headphone_profile.dart';
import '../player_state.dart';

class DspEqEngine {
  final PulsrAudioHandler _audioHandler;
  final PlayerState Function() _getState;
  final void Function(PlayerState state) _emit;
  final bool Function(String feature, {bool showError}) _guardDsp;

  DspEqEngine({
    required PulsrAudioHandler audioHandler,
    required PlayerState Function() getState,
    required void Function(PlayerState state) emit,
    required bool Function(String feature, {bool showError}) guardDsp,
  })  : _audioHandler = audioHandler,
        _getState = getState,
        _emit = emit,
        _guardDsp = guardDsp;

  Future<void> setEqualizerEnabled(bool enabled) async {
    if (enabled && !_guardDsp('EQ')) return;
    _emit(_getState().copyWith(isEqEnabled: enabled, errorMessage: null));
    await _audioHandler.setEqualizerEnabled(enabled);
  }

  Future<void> applyPreset(EqPreset preset) async {
    if (!_guardDsp('Preset')) return;
    _emit(_getState().copyWith(
      isEqEnabled: true,
      eqPreset: preset,
      selectedHeadphoneProfile: null,
      errorMessage: null,
    ));
    await _audioHandler.setEqualizerEnabled(true);
    await _audioHandler.applyPreset(preset);
  }

  Future<void> resetEqualizer() async {
    final flat = EqPreset.defaultPresets.first;
    await applyPreset(flat);
  }

  Future<void> applyHeadphoneProfile(HeadphoneProfile? profile) async {
    if (profile != null && !_guardDsp('AutoEQ')) return;
    if (profile != null) {
      _emit(_getState().copyWith(
        isEqEnabled: true,
        eqPreset: EqPreset(
          name: profile.name,
          gains: profile.gains,
          bassBoost: profile.bassBoost,
        ),
        selectedHeadphoneProfile: profile,
        errorMessage: null,
      ));
      await _audioHandler.setEqualizerEnabled(true);
    } else {
      _emit(_getState().copyWith(
        eqPreset: EqPreset.defaultPresets.first,
        selectedHeadphoneProfile: null,
      ));
    }
    try {
      await _audioHandler.applyHeadphoneProfile(profile);
    } catch (e, st) {
      ErrorLogger.log('Failed to apply headphone profile',
          error: e, stackTrace: st, category: 'DspEqEngine');
      _emit(_getState().copyWith(
          errorMessage: 'Failed to apply headphone profile: $e'));
    }
  }

  Future<void> setBandGain(int bandIndex, double gain) async {
    if (gain.abs() > 0.1 && !_guardDsp('EQ Band')) return;
    final clamped = gain.clamp(-15.0, 15.0);
    final state = _getState();
    final gains = List<double>.from(state.eqPreset.gains);
    if (bandIndex >= 0 && bandIndex < gains.length) {
      final hadProfile = state.selectedHeadphoneProfile != null;
      gains[bandIndex] = clamped;
      _emit(state.copyWith(
        eqPreset: EqPreset(
          name: 'Custom',
          gains: gains,
          bassBoost: hadProfile ? 0.0 : state.eqPreset.bassBoost,
        ),
        selectedHeadphoneProfile: null,
      ));
    }
    await _audioHandler.setBandGain(bandIndex, clamped);
  }

  Future<void> resetToFlat() async {
    _emit(_getState().copyWith(
      eqPreset: EqPreset.defaultPresets.first,
      selectedHeadphoneProfile: null,
    ));
    await _audioHandler.resetToFlat();
  }
}
