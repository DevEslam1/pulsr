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
  bool _isDynamicsBypassed = false;
  bool get isDynamicsBypassed => _isDynamicsBypassed;

  bool isSpatializerEnabled = false;

  HeadphoneProfile? selectedHeadphoneProfile;

  List<double> customFrequencies = List.from(EqPreset.centerFrequencies);
  List<double> _abComparisonGains = [];
  bool isAbComparisonActive = false;

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
    await _restorePreferences();
  }

  Future<void> _restorePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // 1. Read all stored configuration
      isEnabled = prefs.getBool(PrefsKeys.eqEnabled) ?? false;
      final presetName = prefs.getString(PrefsKeys.eqPresetName) ?? 'Flat';
      final gainsJson = prefs.getString(PrefsKeys.eqGains);
      final bass = prefs.getDouble(PrefsKeys.eqBassBoost) ?? 0.0;
      volumeBoost = prefs.getDouble(PrefsKeys.eqVolumeBoost) ?? 0.0;

      // Custom frequencies if persisted
      final customFreqsJson = prefs.getString(PrefsKeys.eqCustomFrequencies);
      if (customFreqsJson != null) {
        try {
          final decodedFreqs = (json.decode(customFreqsJson) as List<dynamic>)
              .map((e) => (e as num).toDouble())
              .toList();
          if (decodedFreqs.length == 10) {
            customFrequencies = decodedFreqs;
          }
        } catch (e, st) {
          ErrorLogger.log('Failed to decode custom EQ frequencies', error: e, stackTrace: st, category: 'EqualizerManager');
        }
      }

      List<double> gains = List<double>.filled(customFrequencies.length, 0.0);
      if (gainsJson != null) {
        try {
          final decoded = json.decode(gainsJson) as List<dynamic>;
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
      _isDynamicsBypassed = prefs.getBool(PrefsKeys.eqDynamicsBypassed) ?? false;

      isSpatializerEnabled = prefs.getBool(PrefsKeys.eqSpatializerEnabled) ?? false;

      final profileId = prefs.getString(PrefsKeys.eqHeadphoneProfileId);
      if (profileId != null) {
        await HeadphoneProfilesRepository().loadProfiles();
        selectedHeadphoneProfile = HeadphoneProfilesRepository().getProfileById(profileId);
      }

      // 2. Apply to native audio engine in strict ordered sequence
      if (Platform.isAndroid) {
        // a. Configure band center frequencies first
        await _effectsChannel.setEqBands(customFrequencies);

        // b. Enable EQ engine if active
        if (isEnabled) {
          await _effectsChannel.setEqEnabled(true);
        }

        // c. Apply gains and preamp after enabling
        await _effectsChannel.setEqBandGains(currentPreset.gains);
        await _effectsChannel.setEqPreamp(selectedHeadphoneProfile?.preampGain ?? 0.0);

        // d. Apply other effects
        if (currentPreset.bassBoost > 0) {
          await _effectsChannel.setBassBoost((currentPreset.bassBoost * 1000).round());
        }
        if (volumeBoost > 0) {
          await setVolumeBoost(volumeBoost);
        }
        if (isVirtualizerEnabled) {
          await setVirtualizerEnabled(true);
          await setVirtualizerStrength(virtualizerStrength);
        }
        if (isDynamicsEnabled && dynamicsPreset != DynamicsPreset.off && !_isDynamicsBypassed) {
          await setDynamicsPreset(dynamicsPreset, enabled: isDynamicsEnabled);
        }
        if (isSpatializerEnabled) {
          await setSpatializerEnabled(true);
        }
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
      await prefs.setBool(PrefsKeys.eqDynamicsBypassed, _isDynamicsBypassed);
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

  void onAppPaused() {
    _saveDebounce?.cancel();
    _savePreferences();
  }

  Future<void> setEqualizerEnabled(bool enabled) async {
    final previousState = isEnabled;
    isEnabled = enabled;
    try {
      if (Platform.isAndroid) {
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
    } catch (e, st) {
      isEnabled = previousState;
      ErrorLogger.log('Failed to set EQ enabled state', error: e, stackTrace: st, category: 'EqualizerManager');
    }
  }

  Future<void> setBandGain(int bandIndex, double gain) async {
    final clamped = gain.clamp(-15.0, 15.0);
    final updatedGains = List<double>.from(currentPreset.gains);
    if (bandIndex >= 0 && bandIndex < updatedGains.length) {
      final hadProfile = selectedHeadphoneProfile != null;
      updatedGains[bandIndex] = clamped;
      currentPreset = currentPreset.copyWith(
        name: 'Custom',
        gains: updatedGains,
      );
      if (hadProfile) {
        selectedHeadphoneProfile = null;
        await _effectsChannel.setEqPreamp(0.0);
        await setBassBoost(0.0);
      }
      await _effectsChannel.setEqBandGain(bandIndex, clamped);
    }
    _debouncedSavePreferences();
  }

  Future<void> resetToFlat() async {
    currentPreset = EqPreset.defaultPresets.first; // Flat
    selectedHeadphoneProfile = null;
    await _effectsChannel.setEqBandGains(
      List<double>.filled(customFrequencies.length, 0.0),
    );
    await _effectsChannel.setEqPreamp(0.0);
    await setBassBoost(0.0);
    await _savePreferences();
  }

  Future<void> startAbComparison() async {
    if (isAbComparisonActive) return;
    isAbComparisonActive = true;
    _abComparisonGains = List.from(currentPreset.gains);
    await _effectsChannel.setEqBandGains(
      List<double>.filled(customFrequencies.length, 0.0),
    );
  }

  Future<void> endAbComparison() async {
    if (!isAbComparisonActive) return;
    isAbComparisonActive = false;
    if (_abComparisonGains.isNotEmpty) {
      await _effectsChannel.setEqBandGains(_abComparisonGains);
      _abComparisonGains = [];
    }
  }

  Future<void> setVolumeBoost(double value) async {
    volumeBoost = value.clamp(0.0, 1.0);

    // Compute total gain: EQ preamp + volume boost
    final preampDb = selectedHeadphoneProfile?.preampGain ?? 0.0;
    final boostDb = volumeBoost * 10.0; // 0-10 dB
    final totalDb = preampDb + boostDb;

    // If total exceeds +6 dB headroom, cap the boost to prevent digital clipping
    if (totalDb > 6.0) {
      final cappedBoostDb = 6.0 - preampDb;
      volumeBoost = (cappedBoostDb / 10.0).clamp(0.0, 1.0);
    }

    final milliBels = (volumeBoost * 1000).round();
    await _effectsChannel.setVolumeBoost(milliBels);
    _debouncedSavePreferences();
  }

  Future<void> setBassBoost(double value) async {
    currentPreset = currentPreset.copyWith(bassBoost: value.clamp(0.0, 1.0));
    final strength = (currentPreset.bassBoost * 1000).round();
    await _effectsChannel.setBassBoost(strength);
    _debouncedSavePreferences();
  }

  Future<void> applyPreset(EqPreset preset) async {
    currentPreset = preset;
    selectedHeadphoneProfile = null;
    await _effectsChannel.setEqBandGains(preset.gains);
    await _effectsChannel.setEqPreamp(0.0);
    await setBassBoost(preset.bassBoost); // Bass boost travels with preset
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
      await _effectsChannel.setEqPreamp(profile.preampGain);
      await setBassBoost(profile.bassBoost);
    } else {
      await resetToFlat();
    }
    await _savePreferences();
  }

  Future<void> setCustomFrequencies(List<double> frequencies) async {
    if (frequencies.length != 10) return;
    customFrequencies = List.from(frequencies);
    await _effectsChannel.setEqBands(frequencies);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      PrefsKeys.eqCustomFrequencies,
      json.encode(frequencies),
    );
  }

  void dispose() {
    _saveDebounce?.cancel();
    _saveDebounce = null;
  }

  Future<void> setVirtualizerEnabled(bool enabled) async {
    final previous = isVirtualizerEnabled;
    isVirtualizerEnabled = enabled;
    try {
      await _effectsChannel.setVirtualizerEnabled(enabled);
      await _savePreferences();
    } catch (e, st) {
      isVirtualizerEnabled = previous;
      ErrorLogger.log('Failed to set virtualizer enabled', error: e, stackTrace: st, category: 'EqualizerManager');
    }
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
    if (!_isDynamicsBypassed) {
      await _effectsChannel.setDynamicsPreset(dynamicsPreset, isDynamicsEnabled);
    }
    await _savePreferences();
  }

  Future<void> toggleDynamicsBypass() async {
    _isDynamicsBypassed = !_isDynamicsBypassed;
    if (_isDynamicsBypassed) {
      await _effectsChannel.setDynamicsPreset(DynamicsPreset.off, false);
    } else {
      await _effectsChannel.setDynamicsPreset(
        dynamicsPreset,
        isDynamicsEnabled,
      );
    }
    await _savePreferences();
  }

  bool get isSpatializerSupported => _effectsChannel.isSpatializerSupported;
  bool get isHeadTrackerAvailable => _effectsChannel.isHeadTrackerAvailable;

  Future<void> setSpatializerEnabled(bool enabled) async {
    final previous = isSpatializerEnabled;
    isSpatializerEnabled = enabled;
    try {
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
    } catch (e, st) {
      isSpatializerEnabled = previous;
      ErrorLogger.log('Failed to set spatializer enabled', error: e, stackTrace: st, category: 'EqualizerManager');
    }
  }
}
