// lib/data/audio/equalizer_manager.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/prefs_keys.dart';
import '../../core/utils/error_logger.dart';
import '../../domain/models/audio_effects_config.dart';
import '../../domain/models/eq_preset.dart';
import '../../domain/models/headphone_profile.dart';
import 'audio_effects_channel.dart';
import 'headphone_profiles_repository.dart';

class EqualizerManager {
  final AndroidLoudnessEnhancer? loudnessEnhancerA;
  final AndroidLoudnessEnhancer? loudnessEnhancerB;
  final AudioEffectsChannel _effectsChannel = AudioEffectsChannel();
  Timer? _saveDebounce;

  EqPreset currentPreset = EqPreset.defaultPresets.first;
  bool isEnabled = false;

  double volumeBoost = 0.0; // 0.0 -> 1.0, maps to 0-1000 mB

  bool isVirtualizerEnabled = false;
  double virtualizerStrength = 0.0; // 0.0 to 1.0

  bool isDynamicsEnabled = false;
  DynamicsPreset dynamicsPreset = DynamicsPreset.off;

  bool isSpatializerEnabled = false;

  HeadphoneProfile? selectedHeadphoneProfile;

  EqualizerManager({
    this.loudnessEnhancerA,
    this.loudnessEnhancerB,
  });

  void _debouncedSavePreferences() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 350), () {
      _savePreferences();
    });
  }

  Future<void> init() async {
    await _effectsChannel.init();
    // Push the fixed 10-band ISO layout so native builds the postEq correctly.
    await _effectsChannel.setEqBands(EqPreset.centerFrequencies);
    await _restorePreferences();
  }

  Future<void> _restorePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      isEnabled = prefs.getBool(PrefsKeys.eqEnabled) ?? false;
      final presetName = prefs.getString(PrefsKeys.eqPresetName) ?? 'Flat';
      final gainsJson = prefs.getString(PrefsKeys.eqGains);
      final bass = prefs.getDouble(PrefsKeys.eqBassBoost) ?? 0.0;
      volumeBoost = prefs.getDouble(PrefsKeys.eqVolumeBoost) ?? 0.0;

      List<double> gains = List<double>.filled(EqPreset.centerFrequencies.length, 0.0);
      if (gainsJson != null) {
        try {
          final decoded = json.decode(gainsJson) as List<dynamic>;
          // Migrate any legacy (5-band) persisted gains up to the 10 ISO centers.
          gains = EqPreset.interpolateGains(
            decoded.map((e) => (e as num).toDouble()).toList(),
          );
        } catch (e, st) {
          ErrorLogger.log('Failed to decode equalizer gains from prefs', error: e, stackTrace: st, category: 'EqualizerManager');
        }
      } else {
        final match = EqPreset.defaultPresets.where((p) => p.name == presetName);
        if (match.isNotEmpty) {
          gains = match.first.gains;
        }
      }

      currentPreset = EqPreset(name: presetName, gains: gains, bassBoost: bass);

      isVirtualizerEnabled = prefs.getBool(PrefsKeys.eqVirtualizerEnabled) ?? false;
      virtualizerStrength = prefs.getDouble(PrefsKeys.eqVirtualizerStrength) ?? 0.0;

      final dynPresetStr = prefs.getString(PrefsKeys.eqDynamicsPreset) ?? DynamicsPreset.off.name;
      dynamicsPreset = DynamicsPreset.values.firstWhere(
        (d) => d.name == dynPresetStr,
        orElse: () => DynamicsPreset.off,
      );
      isDynamicsEnabled = prefs.getBool(PrefsKeys.eqDynamicsEnabled) ?? false;

      isSpatializerEnabled = prefs.getBool(PrefsKeys.eqSpatializerEnabled) ?? false;

      final profileId = prefs.getString(PrefsKeys.eqHeadphoneProfileId);
      if (profileId != null) {
        await HeadphoneProfilesRepository().loadProfiles();
        selectedHeadphoneProfile = HeadphoneProfilesRepository().getProfileById(profileId);
      }

      if (isEnabled) {
        await setEqualizerEnabled(true);
        await applyPreset(currentPreset);
      }
      if (volumeBoost > 0) {
        await setVolumeBoost(volumeBoost);
      }
      if (isVirtualizerEnabled) {
        await setVirtualizerEnabled(true);
        await setVirtualizerStrength(virtualizerStrength);
      }
      if (isDynamicsEnabled && dynamicsPreset != DynamicsPreset.off) {
        await setDynamicsPreset(dynamicsPreset, enabled: isDynamicsEnabled);
      }
      if (isSpatializerEnabled) {
        await setSpatializerEnabled(true);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to restore equalizer preferences', error: e, stackTrace: st, category: 'EqualizerManager');
    }
  }

  Future<void> _savePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(PrefsKeys.eqEnabled, isEnabled);
      await prefs.setString(PrefsKeys.eqPresetName, currentPreset.name);
      await prefs.setString(PrefsKeys.eqGains, json.encode(currentPreset.gains));
      await prefs.setDouble(PrefsKeys.eqBassBoost, currentPreset.bassBoost);
      await prefs.setDouble(PrefsKeys.eqVolumeBoost, volumeBoost);
      await prefs.setBool(PrefsKeys.eqVirtualizerEnabled, isVirtualizerEnabled);
      await prefs.setDouble(PrefsKeys.eqVirtualizerStrength, virtualizerStrength);
      await prefs.setString(PrefsKeys.eqDynamicsPreset, dynamicsPreset.name);
      await prefs.setBool(PrefsKeys.eqDynamicsEnabled, isDynamicsEnabled);
      await prefs.setBool(PrefsKeys.eqSpatializerEnabled, isSpatializerEnabled);
      if (selectedHeadphoneProfile != null) {
        await prefs.setString(PrefsKeys.eqHeadphoneProfileId, selectedHeadphoneProfile!.id);
      } else {
        await prefs.remove(PrefsKeys.eqHeadphoneProfileId);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to save equalizer preferences', error: e, stackTrace: st, category: 'EqualizerManager');
    }
  }

  Future<void> setEqualizerEnabled(bool enabled) async {
    isEnabled = enabled;
    if (Platform.isAndroid) {
      // The just_audio loudness enhancers are kept only as inert session
      // anchors; the real EQ runs through the native DynamicsProcessing postEq.
      for (final le in [loudnessEnhancerA, loudnessEnhancerB]) {
        if (le != null) {
          try {
            await le.setEnabled(enabled);
          } catch (e, st) {
            ErrorLogger.log('Failed to set loudness enhancer enabled state', error: e, stackTrace: st, category: 'EqualizerManager');
          }
        }
      }
      await _effectsChannel.setEqEnabled(enabled);
      if (!enabled) {
        await _effectsChannel.setVolumeBoost(0);
        await _effectsChannel.setBassBoost(0);
      } else {
        await _effectsChannel.setEqBandGains(currentPreset.gains);
        await _effectsChannel.setEqPreamp(selectedHeadphoneProfile?.preampGain ?? 0.0);
        await setVolumeBoost(volumeBoost);
        await setBassBoost(currentPreset.bassBoost);
      }
    }
    await _savePreferences();
  }

  Future<void> setBandGain(int bandIndex, double gain) async {
    final updatedGains = List<double>.from(currentPreset.gains);
    if (bandIndex >= 0 && bandIndex < updatedGains.length) {
      final hadProfile = selectedHeadphoneProfile != null;
      updatedGains[bandIndex] = gain;
      currentPreset = currentPreset.copyWith(name: 'Custom', gains: updatedGains);
      selectedHeadphoneProfile = null;
      await _effectsChannel.setEqBandGain(bandIndex, gain);
      // A hand tweak abandons any profile preamp; drop back to unity headroom.
      if (hadProfile) await _effectsChannel.setEqPreamp(0.0);
    }
    _debouncedSavePreferences();
  }

  Future<void> setVolumeBoost(double value) async {
    volumeBoost = value.clamp(0.0, 1.0);
    final milliBels = (volumeBoost * 1000).round();
    await _effectsChannel.setVolumeBoost(milliBels);
    _debouncedSavePreferences();
  }

  Future<void> setBassBoost(double value) async {
    currentPreset = currentPreset.copyWith(bassBoost: value);
    final strength = (value.clamp(0.0, 1.0) * 1000).round();
    await _effectsChannel.setBassBoost(strength);
    _debouncedSavePreferences();
  }

  Future<void> applyPreset(EqPreset preset) async {
    currentPreset = preset;
    selectedHeadphoneProfile = null;
    await _effectsChannel.setEqBandGains(preset.gains);
    // Built-in presets carry no preamp; keep headroom at unity.
    await _effectsChannel.setEqPreamp(0.0);
    await setBassBoost(preset.bassBoost);
    await _savePreferences();
  }

  Future<void> applyHeadphoneProfile(HeadphoneProfile? profile) async {
    selectedHeadphoneProfile = profile;
    if (profile != null) {
      currentPreset = EqPreset(
        name: profile.name,
        gains: profile.gains,
        bassBoost: profile.bassBoost,
      );
      await _effectsChannel.setEqBandGains(profile.gains);
      // Apply the profile preamp as real headroom — negative attenuates
      // (protects against EQ-boost clipping) instead of being discarded.
      await _effectsChannel.setEqPreamp(profile.preampGain);
      await setBassBoost(profile.bassBoost);
    }
    await _savePreferences();
  }

  void dispose() {
    _saveDebounce?.cancel();
    _saveDebounce = null;
  }

  Future<void> setVirtualizerEnabled(bool enabled) async {
    isVirtualizerEnabled = enabled;
    await _effectsChannel.setVirtualizerEnabled(enabled);
    await _savePreferences();
  }

  Future<void> setVirtualizerStrength(double strength) async {
    virtualizerStrength = strength.clamp(0.0, 1.0);
    await _effectsChannel.setVirtualizerStrength(virtualizerStrength);
    await _savePreferences();
  }

  Future<void> setDynamicsPreset(DynamicsPreset preset, {bool? enabled}) async {
    dynamicsPreset = preset;
    if (enabled != null) {
      isDynamicsEnabled = enabled;
    } else if (preset == DynamicsPreset.off) {
      isDynamicsEnabled = false;
    } else {
      isDynamicsEnabled = true;
    }
    await _effectsChannel.setDynamicsPreset(dynamicsPreset, isDynamicsEnabled);
    await _savePreferences();
  }

  bool get isSpatializerSupported => _effectsChannel.isSpatializerSupported;

  Future<void> setSpatializerEnabled(bool enabled) async {
    isSpatializerEnabled = enabled;
    await _effectsChannel.setSpatializerEnabled(enabled);
    if (enabled && !_effectsChannel.isSpatializerSupported) {
      if (!isVirtualizerEnabled) {
        await setVirtualizerEnabled(true);
        if (virtualizerStrength < 0.3) {
          await setVirtualizerStrength(0.7);
        }
      }
    }
    await _savePreferences();
  }
}
