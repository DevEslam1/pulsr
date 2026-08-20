// lib/data/audio/equalizer_manager.dart
import 'dart:io';
import 'package:just_audio/just_audio.dart';
import '../../domain/models/eq_preset.dart';

class EqualizerManager {
  final AndroidEqualizer? equalizerA;
  final AndroidLoudnessEnhancer? loudnessEnhancerA;
  final AndroidEqualizer? equalizerB;
  final AndroidLoudnessEnhancer? loudnessEnhancerB;

  EqPreset currentPreset = EqPreset.defaultPresets.first;
  bool isEnabled = false;

  EqualizerManager({
    this.equalizerA,
    this.loudnessEnhancerA,
    this.equalizerB,
    this.loudnessEnhancerB,
  });

  Future<void> setEqualizerEnabled(bool enabled) async {
    isEnabled = enabled;
    if (Platform.isAndroid) {
      for (final eq in [equalizerA, equalizerB]) {
        if (eq != null) {
          try {
            await eq.setEnabled(enabled);
          } catch (_) {}
        }
      }
      for (final le in [loudnessEnhancerA, loudnessEnhancerB]) {
        if (le != null) {
          try {
            await le.setEnabled(enabled);
          } catch (_) {}
        }
      }
    }
  }

  Future<void> setBandGain(int bandIndex, double gain) async {
    final updatedGains = List<double>.from(currentPreset.gains);
    if (bandIndex >= 0 && bandIndex < updatedGains.length) {
      updatedGains[bandIndex] = gain;
      currentPreset = currentPreset.copyWith(name: 'Custom', gains: updatedGains);
    }
    for (final eq in [equalizerA, equalizerB]) {
      if (eq != null) {
        try {
          final parameters = await eq.parameters;
          if (bandIndex < parameters.bands.length) {
            await parameters.bands[bandIndex].setGain(gain);
          }
        } catch (_) {}
      }
    }
  }

  Future<void> setBassBoost(double value) async {
    currentPreset = currentPreset.copyWith(bassBoost: value);
    for (final le in [loudnessEnhancerA, loudnessEnhancerB]) {
      if (le != null) {
        try {
          await le.setTargetGain(value * 0.5);
        } catch (_) {}
      }
    }
  }

  Future<void> applyPreset(EqPreset preset) async {
    currentPreset = preset;
    for (final eq in [equalizerA, equalizerB]) {
      if (eq != null) {
        try {
          final parameters = await eq.parameters;
          for (int i = 0; i < preset.gains.length && i < parameters.bands.length; i++) {
            await parameters.bands[i].setGain(preset.gains[i]);
          }
        } catch (_) {}
      }
    }
    await setBassBoost(preset.bassBoost);
  }
}
