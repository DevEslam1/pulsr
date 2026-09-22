// lib/features/player/cubit/controllers/dsp_effects_engine.dart
// FIX-A1: Modular DSP Effects Engine
import 'dart:async';
import '../../../../data/audio/audio_handler.dart';
import '../../../../domain/models/eq_preset.dart';
import '../player_state.dart';

class DspEffectsEngine {
  final PulsrAudioHandler _audioHandler;
  final PlayerState Function() _getState;
  final void Function(PlayerState state) _emit;
  final bool Function(String feature, {bool showError}) _guardDsp;

  DspEffectsEngine({
    required PulsrAudioHandler audioHandler,
    required PlayerState Function() getState,
    required void Function(PlayerState state) emit,
    required bool Function(String feature, {bool showError}) guardDsp,
  })  : _audioHandler = audioHandler,
        _getState = getState,
        _emit = emit,
        _guardDsp = guardDsp;

  Future<void> setBassBoost(double amount) async {
    if (amount > 0.01 && !_guardDsp('Bass Boost')) return;
    final clamped = amount.clamp(0.0, 1.0);
    final state = _getState();
    _emit(state.copyWith(
      dsp: state.dsp.copyWith(
        eqPreset: EqPreset(
          name: state.dsp.eqPreset.name,
          gains: state.dsp.eqPreset.gains,
          bassBoost: clamped,
        ),
      ),
      playback: state.playback.copyWith(errorMessage: null),
    ));
    await _audioHandler.setBassBoost(clamped);
  }

  Future<void> setVirtualizerEnabled(bool enabled) async {
    if (enabled && !_guardDsp('Virtualizer')) return;
    final state = _getState();
    _emit(state.copyWith(
      dsp: state.dsp.copyWith(isVirtualizerEnabled: enabled),
      playback: state.playback.copyWith(errorMessage: null),
    ));
    await _audioHandler.setVirtualizerEnabled(enabled);
  }

  Future<void> setVirtualizerStrength(double strength) async {
    if (!_guardDsp('Virtualizer', showError: false)) return;
    final clamped = strength.clamp(0.0, 1.0);
    final state = _getState();
    _emit(state.copyWith(
      dsp: state.dsp.copyWith(virtualizerStrength: clamped),
      playback: state.playback.copyWith(errorMessage: null),
    ));
    await _audioHandler.setVirtualizerStrength(clamped);
  }

  Future<void> setReverbEnabled(bool enabled) async {
    if (enabled && !_guardDsp('Reverb')) return;
    final state = _getState();
    _emit(state.copyWith(
      dsp: state.dsp.copyWith(isReverbEnabled: enabled),
      playback: state.playback.copyWith(errorMessage: null),
    ));
    await _audioHandler.setReverb(enabled);
  }

  Future<void> setReverbPreset(int preset) async {
    final state = _getState();
    _emit(state.copyWith(
      dsp: state.dsp.copyWith(reverbPreset: preset),
      playback: state.playback.copyWith(errorMessage: null),
    ));
    await _audioHandler.setReverb(state.isReverbEnabled, preset: preset);
  }

  Future<void> setLimiterEnabled(bool enabled) async {
    if (enabled && !_guardDsp('Limiter')) return;
    final state = _getState();
    _emit(state.copyWith(
      dsp: state.dsp.copyWith(isLimiterEnabled: enabled),
      playback: state.playback.copyWith(errorMessage: null),
    ));
    await _audioHandler.setLookaheadLimiter(enabled);
  }

  Future<void> setCrossfeedEnabled(bool enabled) async {
    if (enabled && !_guardDsp('Crossfeed')) return;
    final state = _getState();
    _emit(state.copyWith(
      dsp: state.dsp.copyWith(isCrossfeedEnabled: enabled),
      playback: state.playback.copyWith(errorMessage: null),
    ));
    await _audioHandler.setCrossfeed(enabled);
  }
}
