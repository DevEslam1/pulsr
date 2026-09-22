// lib/features/player/cubit/controllers/player_dsp_controller.dart
// FIX-A1: Focused PlayerDspController coordinating EQ and Effects engines
import 'dart:async';
import '../../../../core/constants/audio_feature_info.dart';
import '../../../../data/audio/audio_handler.dart';
import '../../../../domain/models/audio_quality_info.dart';
import '../../../../domain/models/eq_preset.dart';
import '../../../../domain/models/headphone_profile.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../player_state.dart';
import 'dsp_effects_engine.dart';
import 'dsp_eq_engine.dart';

/// Orchestrates all audio DSP effects, equalizer presets, and bit-perfect conflict gating.
class PlayerDspController {
  final PulsrAudioHandler _audioHandler;
  final SettingsCubit? _settingsCubit;
  final PlayerState Function() _getState;
  final void Function(PlayerState state) _emit;

  late final DspEqEngine _eqEngine;
  late final DspEffectsEngine _effectsEngine;

  PlayerDspController({
    required PulsrAudioHandler audioHandler,
    required SettingsCubit? settingsCubit,
    required PlayerState Function() getState,
    required void Function(PlayerState state) emit,
  })  : _audioHandler = audioHandler,
        _settingsCubit = settingsCubit,
        _getState = getState,
        _emit = emit {
    _eqEngine = DspEqEngine(
      audioHandler: _audioHandler,
      getState: _getState,
      emit: _emit,
      guardDsp: guardDsp,
    );
    _effectsEngine = DspEffectsEngine(
      audioHandler: _audioHandler,
      getState: _getState,
      emit: _emit,
      guardDsp: guardDsp,
    );
  }

  String? dspBlockedReason() {
    final s = _settingsCubit?.state;
    if (s == null) return null;
    return AudioConflicts.dspBlockedByBitPerfect(
      bitPerfectOutput: s.bitPerfectOutput,
      bypassDspOnBitPerfect: s.bypassDspOnBitPerfect,
      device: s.currentOutputDevice,
      aaudioEnabled: s.aaudioOutputEnabled,
      dsdDopActive: AudioQualityInfo.dsdDopActive,
    );
  }

  bool guardDsp(String feature, {bool showError = true}) {
    final reason = dspBlockedReason();
    if (reason != null) {
      if (showError) {
        _emit(_getState().copyWith(errorMessage: '$feature blocked: $reason'));
      }
      return false;
    }
    return true;
  }

  // Equalizer Delegation
  Future<void> setEqualizerEnabled(bool enabled) => _eqEngine.setEqualizerEnabled(enabled);
  Future<void> applyPreset(EqPreset preset) => _eqEngine.applyPreset(preset);
  Future<void> resetEqualizer() => _eqEngine.resetEqualizer();
  Future<void> applyHeadphoneProfile(HeadphoneProfile? profile) => _eqEngine.applyHeadphoneProfile(profile);
  Future<void> setBandGain(int bandIndex, double gain) => _eqEngine.setBandGain(bandIndex, gain);
  Future<void> resetToFlat() => _eqEngine.resetToFlat();

  // Audio Effects Delegation
  Future<void> setBassBoost(double amount) => _effectsEngine.setBassBoost(amount);
  Future<void> setVirtualizerEnabled(bool enabled) => _effectsEngine.setVirtualizerEnabled(enabled);
  Future<void> setVirtualizerStrength(double strength) => _effectsEngine.setVirtualizerStrength(strength);
  Future<void> setReverbEnabled(bool enabled) => _effectsEngine.setReverbEnabled(enabled);
  Future<void> setReverbPreset(int preset) => _effectsEngine.setReverbPreset(preset);
  Future<void> setLimiterEnabled(bool enabled) => _effectsEngine.setLimiterEnabled(enabled);
  Future<void> setCrossfeedEnabled(bool enabled) => _effectsEngine.setCrossfeedEnabled(enabled);
}
