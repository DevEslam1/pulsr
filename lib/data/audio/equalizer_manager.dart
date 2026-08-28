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

enum ComparisonSlot { slotA, slotB, slotC, slotD }

class EqualizerManager {
  final AndroidLoudnessEnhancer? loudnessEnhancerA;
  final AndroidLoudnessEnhancer? loudnessEnhancerB;
  final AudioEffectsChannel _effectsChannel = AudioEffectsChannel();
  Timer? _saveDebounce;

  EqPreset currentPreset = EqPreset.defaultPresets.first;
  bool isEnabled = false;
  bool is32BandMode = false;

  double volumeBoost = 0.0; // 0.0 -> 1.0, maps to 0-1000 mB

  bool isVirtualizerEnabled = false;
  double virtualizerStrength = 0.0; // 0.0 to 1.0

  bool isDynamicsEnabled = false;
  DynamicsPreset dynamicsPreset = DynamicsPreset.off;
  bool _isDynamicsBypassed = false;
  bool get isDynamicsBypassed => _isDynamicsBypassed;

  bool isSpatializerEnabled = false;

  // Tier 1 & Tier 2 & Tier 3 Native DSP features
  bool isCrossfeedEnabled = false;
  double crossfeedDelayUs = 350.0; // 200 - 700 us
  double crossfeedFeedDb = -9.0; // -15 to -6 dB

  bool isLimiterEnabled = false;
  double limiterThresholdDb = -0.2;
  double limiterReleaseMs = 50.0;
  double limiterLookaheadMs = 3.0;

  // Visual Compressor Knobs
  double compressorRatio = 3.0;
  double compressorAttackMs = 15.0;
  double compressorMakeupGainDb = 0.0;

  bool isReverbEnabled = false;
  int reverbPreset =
      0; // 0=Studio, 1=Concert Hall, 2=Warm Tube, 3=Plate, 4=Custom IR
  double reverbWetDry = 0.20;

  double stereoBalance = 0.0; // -1.0 to +1.0
  bool monoMix = false;
  bool isSincResamplerEnabled = true;

  HeadphoneProfile? selectedHeadphoneProfile;

  List<double> customFrequencies = List.from(EqPreset.centerFrequencies);
  List<double> custom32Frequencies = List.from(EqPreset.iso32Frequencies);

  // A/B/C/D Comparison Slots
  ComparisonSlot activeComparisonSlot = ComparisonSlot.slotA;
  final Map<ComparisonSlot, EqPreset> comparisonSlots = {
    ComparisonSlot.slotA: EqPreset.defaultPresets.first,
    ComparisonSlot.slotB: EqPreset.defaultPresets[1],
    ComparisonSlot.slotC: EqPreset.defaultPresets[2],
    ComparisonSlot.slotD: EqPreset.defaultPresets[3],
  };

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

  List<double> get activeFrequencies =>
      is32BandMode ? custom32Frequencies : customFrequencies;

  Future<void> _restorePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      isEnabled = prefs.getBool(PrefsKeys.eqEnabled) ?? false;
      is32BandMode = prefs.getBool('eq_32_band_mode') ?? false;
      final presetName = prefs.getString(PrefsKeys.eqPresetName) ?? 'Flat';
      final gainsJson = prefs.getString(PrefsKeys.eqGains);
      final bass = prefs.getDouble(PrefsKeys.eqBassBoost) ?? 0.0;
      volumeBoost = prefs.getDouble(PrefsKeys.eqVolumeBoost) ?? 0.0;

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
          ErrorLogger.log('Failed to decode custom EQ frequencies',
              error: e, stackTrace: st, category: 'EqualizerManager');
        }
      }

      final targetFreqs =
          is32BandMode ? custom32Frequencies : customFrequencies;
      List<double> gains = List<double>.filled(targetFreqs.length, 0.0);
      bool gainsLoaded = false;
      if (gainsJson != null) {
        try {
          final decoded = json.decode(gainsJson) as List<dynamic>;
          final parsedGains =
              decoded.map((e) => (e as num).toDouble()).toList();
          if (parsedGains.isNotEmpty) {
            gains = EqPreset.interpolateGains(
              parsedGains,
              targetFrequencies: targetFreqs,
            );
            gainsLoaded = gains.length == targetFreqs.length;
          }
        } catch (e, st) {
          ErrorLogger.log('Failed to decode equalizer gains from prefs',
              error: e, stackTrace: st, category: 'EqualizerManager');
        }
      }

      if (!gainsLoaded) {
        final match =
            EqPreset.defaultPresets.where((p) => p.name == presetName);
        if (match.isNotEmpty) {
          gains = EqPreset.interpolateGains(match.first.gains,
              targetFrequencies: targetFreqs);
        } else {
          gains = List<double>.filled(targetFreqs.length, 0.0);
        }
      }

      currentPreset = EqPreset(name: presetName, gains: gains, bassBoost: bass);
      comparisonSlots[ComparisonSlot.slotA] = currentPreset;

      isVirtualizerEnabled =
          prefs.getBool(PrefsKeys.eqVirtualizerEnabled) ?? false;
      virtualizerStrength =
          prefs.getDouble(PrefsKeys.eqVirtualizerStrength) ?? 0.0;

      final dynPresetStr = prefs.getString(PrefsKeys.eqDynamicsPreset) ??
          DynamicsPreset.off.name;
      dynamicsPreset = DynamicsPreset.values.firstWhere(
        (d) => d.name == dynPresetStr,
        orElse: () => DynamicsPreset.off,
      );
      isDynamicsEnabled = prefs.getBool(PrefsKeys.eqDynamicsEnabled) ?? false;
      _isDynamicsBypassed =
          prefs.getBool(PrefsKeys.eqDynamicsBypassed) ?? false;

      isSpatializerEnabled =
          prefs.getBool(PrefsKeys.eqSpatializerEnabled) ?? false;

      isCrossfeedEnabled = prefs.getBool(PrefsKeys.crossfeedEnabled) ?? false;
      crossfeedDelayUs = prefs.getDouble(PrefsKeys.crossfeedDelayUs) ?? 350.0;
      crossfeedFeedDb = prefs.getDouble(PrefsKeys.crossfeedFeedDb) ?? -9.0;

      isLimiterEnabled =
          prefs.getBool(PrefsKeys.lookaheadLimiterEnabled) ?? false;
      limiterThresholdDb =
          prefs.getDouble(PrefsKeys.lookaheadLimiterThresholdDb) ?? -0.2;
      limiterReleaseMs =
          prefs.getDouble(PrefsKeys.lookaheadLimiterReleaseMs) ?? 50.0;

      isReverbEnabled =
          prefs.getBool(PrefsKeys.convolutionReverbEnabled) ?? false;
      reverbPreset = prefs.getInt(PrefsKeys.convolutionReverbPreset) ?? 0;
      reverbWetDry = prefs.getDouble(PrefsKeys.convolutionReverbWetDry) ?? 0.20;

      stereoBalance = prefs.getDouble(PrefsKeys.stereoBalance) ?? 0.0;
      monoMix = prefs.getBool(PrefsKeys.monoMix) ?? false;
      isSincResamplerEnabled =
          prefs.getBool(PrefsKeys.sincResamplerEnabled) ?? true;

      final profileId = prefs.getString(PrefsKeys.eqHeadphoneProfileId);
      if (profileId != null) {
        await HeadphoneProfilesRepository().loadProfiles();
        selectedHeadphoneProfile =
            HeadphoneProfilesRepository().getProfileById(profileId);
      }

      if (isEnabled) {
        await applyCurrentPreset();
        await _effectsChannel.setEqEnabled(true);
        await _effectsChannel.setNativeEqEnabled(true);
      }
      if (currentPreset.bassBoost > 0) {
        await setBassBoost(currentPreset.bassBoost);
      }
      if (volumeBoost > 0) {
        await setVolumeBoost(volumeBoost);
      }
      if (isVirtualizerEnabled) {
        await _effectsChannel.setVirtualizerEnabled(true);
        await _effectsChannel.setVirtualizerStrength(virtualizerStrength);
      }
      if (isDynamicsEnabled && !_isDynamicsBypassed) {
        await _effectsChannel.setDynamicsPreset(dynamicsPreset, true);
      }
      if (isSpatializerEnabled) {
        await _effectsChannel.setSpatializerEnabled(true);
      }

      if (isCrossfeedEnabled) {
        await _effectsChannel.setCrossfeedParams(
            crossfeedDelayUs, crossfeedFeedDb);
        await _effectsChannel.setCrossfeedEnabled(true);
      }
      if (isLimiterEnabled) {
        await _effectsChannel.setLimiterParams(
            limiterLookaheadMs, limiterThresholdDb, limiterReleaseMs);
        await _effectsChannel.setLimiterEnabled(true);
      }
      if (isReverbEnabled) {
        await _effectsChannel.setReverbPreset(reverbPreset);
        await _effectsChannel.setReverbWetDry(reverbWetDry);
        await _effectsChannel.setReverbEnabled(true);
      }
      if (stereoBalance != 0.0) {
        await _effectsChannel.setStereoBalance(stereoBalance);
      }
      if (monoMix) {
        await _effectsChannel.setMonoMix(true);
      }
      if (!isSincResamplerEnabled) {
        await _effectsChannel.setSincResamplerEnabled(false);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to restore equalizer preferences',
          error: e, stackTrace: st, category: 'EqualizerManager');
    }
  }

  Future<void> _savePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(PrefsKeys.eqEnabled, isEnabled);
      await prefs.setBool('eq_32_band_mode', is32BandMode);
      await prefs.setString(PrefsKeys.eqPresetName, currentPreset.name);
      await prefs.setString(
          PrefsKeys.eqGains, json.encode(currentPreset.gains));
      await prefs.setString(
          'eq_custom_frequencies', json.encode(customFrequencies));
      await prefs.setDouble(PrefsKeys.eqBassBoost, currentPreset.bassBoost);
      await prefs.setDouble(PrefsKeys.eqVolumeBoost, volumeBoost);
      await prefs.setBool(PrefsKeys.eqVirtualizerEnabled, isVirtualizerEnabled);
      await prefs.setDouble(
          PrefsKeys.eqVirtualizerStrength, virtualizerStrength);
      await prefs.setString(PrefsKeys.eqDynamicsPreset, dynamicsPreset.name);
      await prefs.setBool(PrefsKeys.eqDynamicsEnabled, isDynamicsEnabled);
      await prefs.setBool(PrefsKeys.eqDynamicsBypassed, _isDynamicsBypassed);
      await prefs.setBool(PrefsKeys.eqSpatializerEnabled, isSpatializerEnabled);

      await prefs.setBool(PrefsKeys.crossfeedEnabled, isCrossfeedEnabled);
      await prefs.setDouble(PrefsKeys.crossfeedDelayUs, crossfeedDelayUs);
      await prefs.setDouble(PrefsKeys.crossfeedFeedDb, crossfeedFeedDb);

      await prefs.setBool(PrefsKeys.lookaheadLimiterEnabled, isLimiterEnabled);
      await prefs.setDouble(
          PrefsKeys.lookaheadLimiterThresholdDb, limiterThresholdDb);
      await prefs.setDouble(
          PrefsKeys.lookaheadLimiterReleaseMs, limiterReleaseMs);

      await prefs.setBool(PrefsKeys.convolutionReverbEnabled, isReverbEnabled);
      await prefs.setInt(PrefsKeys.convolutionReverbPreset, reverbPreset);
      await prefs.setDouble(PrefsKeys.convolutionReverbWetDry, reverbWetDry);

      await prefs.setDouble(PrefsKeys.stereoBalance, stereoBalance);
      await prefs.setBool(PrefsKeys.monoMix, monoMix);
      await prefs.setBool(
          PrefsKeys.sincResamplerEnabled, isSincResamplerEnabled);

      if (selectedHeadphoneProfile != null) {
        await prefs.setString(
            PrefsKeys.eqHeadphoneProfileId, selectedHeadphoneProfile!.id);
      } else {
        await prefs.remove(PrefsKeys.eqHeadphoneProfileId);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to save equalizer preferences',
          error: e, stackTrace: st, category: 'EqualizerManager');
    }
  }

  Future<void> set32BandMode(bool enabled) async {
    is32BandMode = enabled;
    final targetFreqs = enabled ? custom32Frequencies : customFrequencies;
    final interpolated = EqPreset.interpolateGains(currentPreset.gains,
        targetFrequencies: targetFreqs);
    currentPreset = currentPreset.copyWith(gains: interpolated);

    if (Platform.isAndroid) {
      await _effectsChannel.setNativeEqBandCount(targetFreqs.length);
      for (int i = 0; i < targetFreqs.length; i++) {
        await _effectsChannel.setNativeEqBand(
          i,
          targetFreqs[i],
          currentPreset.gains[i],
          1.414,
        );
      }
      if (!enabled) {
        await _effectsChannel.setEqBands(targetFreqs);
        await _effectsChannel.setEqBandGains(currentPreset.gains);
      }
    }
    _debouncedSavePreferences();
  }

  Future<void> setEnabled(bool enabled) async {
    final previous = isEnabled;
    isEnabled = enabled;
    try {
      await _effectsChannel.setEqEnabled(enabled);
      await _effectsChannel.setNativeEqEnabled(enabled);
      if (enabled) {
        await applyCurrentPreset();
      }
      await _savePreferences();
    } catch (e, st) {
      isEnabled = previous;
      ErrorLogger.log('Failed to toggle equalizer state ($enabled)',
          error: e, stackTrace: st, category: 'EqualizerManager');
    }
  }

  Future<void> setEqualizerEnabled(bool enabled) => setEnabled(enabled);
  Future<void> applyPreset(EqPreset preset) => setPreset(preset);
  Future<void> applyHeadphoneProfile(HeadphoneProfile? profile) =>
      setHeadphoneProfile(profile);

  Future<void> setPreset(EqPreset preset) async {
    selectedHeadphoneProfile = null;
    final targetFreqs = is32BandMode ? custom32Frequencies : customFrequencies;
    final gains =
        EqPreset.interpolateGains(preset.gains, targetFrequencies: targetFreqs);
    currentPreset = preset.copyWith(gains: gains);
    comparisonSlots[activeComparisonSlot] = currentPreset;
    await applyCurrentPreset();
    await setBassBoost(preset.bassBoost);
    _debouncedSavePreferences();
  }

  Future<void> setBandGain(int index, double gain) async {
    if (index < 0 || index >= currentPreset.gains.length) return;
    selectedHeadphoneProfile = null;
    final targetFreqs = is32BandMode ? custom32Frequencies : customFrequencies;

    final newGains = List<double>.from(currentPreset.gains);
    newGains[index] = gain.clamp(-15.0, 15.0);
    currentPreset = currentPreset.copyWith(name: 'Custom', gains: newGains);
    comparisonSlots[activeComparisonSlot] = currentPreset;

    if (Platform.isAndroid && isEnabled) {
      if (is32BandMode) {
        await _effectsChannel.setNativeEqBand(
          index,
          targetFreqs[index],
          newGains[index],
          1.414,
        );
      } else {
        await _effectsChannel.setEqBandGain(index, newGains[index]);
        await _effectsChannel.setNativeEqBand(
          index,
          targetFreqs[index],
          newGains[index],
          1.414,
        );
      }
    }
    _debouncedSavePreferences();
  }

  Future<void> setPreamp(double preampDb) async {
    if (Platform.isAndroid) {
      await _effectsChannel.setEqPreamp(preampDb.clamp(-15.0, 15.0));
    }
    _debouncedSavePreferences();
  }

  Future<void> applyCurrentPreset() async {
    if (!isEnabled) return;
    final targetFreqs = is32BandMode ? custom32Frequencies : customFrequencies;
    if (Platform.isAndroid) {
      if (is32BandMode) {
        await _effectsChannel.setNativeEqBandCount(targetFreqs.length);
        for (int i = 0; i < targetFreqs.length; i++) {
          await _effectsChannel.setNativeEqBand(
            i,
            targetFreqs[i],
            currentPreset.gains[i],
            1.414,
          );
        }
      } else {
        await _effectsChannel.setEqBands(targetFreqs);
        await _effectsChannel.setEqBandGains(currentPreset.gains);
        await _effectsChannel.setNativeEqBandCount(targetFreqs.length);
        for (int i = 0; i < targetFreqs.length; i++) {
          await _effectsChannel.setNativeEqBand(
            i,
            targetFreqs[i],
            currentPreset.gains[i],
            1.414,
          );
        }
      }
    }
  }

  // --- A/B/C/D 4-SLOT COMPARISON ---

  void saveCurrentToSlot(ComparisonSlot slot) {
    comparisonSlots[slot] = currentPreset;
  }

  Future<void> switchComparisonSlot(ComparisonSlot slot) async {
    activeComparisonSlot = slot;
    final slotPreset = comparisonSlots[slot] ?? EqPreset.defaultPresets.first;
    await setPreset(slotPreset);
  }

  // --- PRESET JSON IMPORT / EXPORT ---

  String exportPresetToJson([EqPreset? preset]) {
    final target = preset ?? currentPreset;
    return json.encode(target.toJson());
  }

  Future<bool> importPresetFromJson(String jsonString) async {
    try {
      final decoded = json.decode(jsonString) as Map<String, dynamic>;
      final preset = EqPreset.fromJson(decoded);
      await setPreset(preset);
      return true;
    } catch (e, st) {
      ErrorLogger.log('Failed to import EQ preset from JSON',
          error: e, stackTrace: st, category: 'EqualizerManager');
      return false;
    }
  }

  Future<void> setBassBoost(double value) async {
    final clamped = value.clamp(0.0, 1.0);
    currentPreset = currentPreset.copyWith(bassBoost: clamped);
    final milliBels = (clamped * 1000).round();
    if (Platform.isAndroid) {
      await _effectsChannel.setBassBoost(milliBels);
    }
    _debouncedSavePreferences();
  }

  List<double> _abComparisonGains = [];
  bool isAbComparisonActive = false;

  Future<void> resetToFlat() async {
    selectedHeadphoneProfile = null;
    await setPreamp(0.0);
    await setPreset(const EqPreset(
      name: 'Flat',
      gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      bassBoost: 0.0,
    ));
  }

  Future<void> startAbComparison() async {
    isAbComparisonActive = true;
    _abComparisonGains = List.from(currentPreset.gains);
    final targetFreqs = is32BandMode ? custom32Frequencies : customFrequencies;
    final flatGains = List<double>.filled(targetFreqs.length, 0.0);
    if (Platform.isAndroid) {
      if (is32BandMode) {
        for (int i = 0; i < targetFreqs.length; i++) {
          await _effectsChannel.setNativeEqBand(i, targetFreqs[i], 0.0, 1.414);
        }
      } else {
        await _effectsChannel.setEqBandGains(flatGains);
      }
    }
  }

  Future<void> endAbComparison() async {
    isAbComparisonActive = false;
    if (_abComparisonGains.isNotEmpty) {
      final targetFreqs =
          is32BandMode ? custom32Frequencies : customFrequencies;
      if (Platform.isAndroid) {
        if (is32BandMode) {
          for (int i = 0; i < _abComparisonGains.length; i++) {
            await _effectsChannel.setNativeEqBand(
                i, targetFreqs[i], _abComparisonGains[i], 1.414);
          }
        } else {
          await _effectsChannel.setEqBandGains(_abComparisonGains);
        }
      }
    }
  }

  Future<void> setCustomFrequencies(List<double> frequencies) async {
    customFrequencies = List.from(frequencies);
    await _savePreferences();
  }

  Future<void> onAppPaused() async {
    _saveDebounce?.cancel();
    await _savePreferences();
  }

  Future<void> setVolumeBoost(double value) async {
    final preampDb = selectedHeadphoneProfile?.preampGain ?? 0.0;
    var safeValue = value.clamp(0.0, 1.0);
    if ((preampDb + safeValue * 10.0) > 6.0) {
      safeValue = ((6.0 - preampDb) / 10.0).clamp(0.0, 1.0);
    }
    volumeBoost = safeValue;
    final milliBels = (volumeBoost * 1000).round();
    if (Platform.isAndroid) {
      await _effectsChannel.setVolumeBoost(milliBels);
    }
    _debouncedSavePreferences();
  }

  Future<void> setHeadphoneProfile(HeadphoneProfile? profile) async {
    final prevPreset = currentPreset;
    final prevProfile = selectedHeadphoneProfile;
    try {
      if (profile != null) {
        final targetFreqs =
            is32BandMode ? custom32Frequencies : customFrequencies;
        final gains = EqPreset.interpolateGains(profile.gains,
            targetFrequencies: targetFreqs);
        currentPreset = EqPreset(
          name: profile.name,
          gains: gains,
          bassBoost: profile.bassBoost,
        );
        comparisonSlots[activeComparisonSlot] = currentPreset;
        selectedHeadphoneProfile = profile;
        await applyCurrentPreset();
        await setBassBoost(profile.bassBoost);
        await setPreamp(profile.preampGain);
      } else {
        selectedHeadphoneProfile = null;
        await setPreamp(0.0);
      }
    } catch (e, st) {
      currentPreset = prevPreset;
      selectedHeadphoneProfile = prevProfile;
      ErrorLogger.log('Failed to apply headphone profile',
          error: e, stackTrace: st, category: 'EqualizerManager');
    }
    _debouncedSavePreferences();
  }

  Future<void> setVirtualizerEnabled(bool enabled) async {
    final previous = isVirtualizerEnabled;
    isVirtualizerEnabled = enabled;
    try {
      await _effectsChannel.setVirtualizerEnabled(enabled);
      await _savePreferences();
    } catch (e, st) {
      isVirtualizerEnabled = previous;
      ErrorLogger.log('Failed to set virtualizer enabled',
          error: e, stackTrace: st, category: 'EqualizerManager');
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
      await _effectsChannel.setDynamicsPreset(
          dynamicsPreset, isDynamicsEnabled);
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
      ErrorLogger.log('Failed to set spatializer enabled',
          error: e, stackTrace: st, category: 'EqualizerManager');
    }
  }

  bool get hasOemAudio => _effectsChannel.hasOemAudio;
  List<String> get detectedOemEngines => _effectsChannel.detectedOemEngines;

  Future<void> setCrossfeed(bool enabled,
      {double? delayUs, double? feedDb}) async {
    isCrossfeedEnabled = enabled;
    if (delayUs != null) crossfeedDelayUs = delayUs;
    if (feedDb != null) crossfeedFeedDb = feedDb;
    if (Platform.isAndroid) {
      await _effectsChannel.setCrossfeedParams(
          crossfeedDelayUs, crossfeedFeedDb);
      await _effectsChannel.setCrossfeedEnabled(enabled);
    }
    _debouncedSavePreferences();
  }

  Future<void> setLookaheadLimiter(bool enabled,
      {double? thresholdDb, double? releaseMs, double? lookaheadMs}) async {
    isLimiterEnabled = enabled;
    if (thresholdDb != null) limiterThresholdDb = thresholdDb;
    if (releaseMs != null) limiterReleaseMs = releaseMs;
    if (Platform.isAndroid) {
      await _effectsChannel.setLimiterParams(
          lookaheadMs ?? 3.0, limiterThresholdDb, limiterReleaseMs);
      await _effectsChannel.setLimiterEnabled(enabled);
    }
    _debouncedSavePreferences();
  }

  Future<void> setCompressorParams({
    double? thresholdDb,
    double? ratio,
    double? attackMs,
    double? releaseMs,
    double? makeupGainDb,
  }) async {
    if (thresholdDb != null) limiterThresholdDb = thresholdDb;
    if (ratio != null) compressorRatio = ratio;
    if (attackMs != null) compressorAttackMs = attackMs;
    if (releaseMs != null) limiterReleaseMs = releaseMs;
    if (makeupGainDb != null) compressorMakeupGainDb = makeupGainDb;

    if (Platform.isAndroid) {
      await _effectsChannel.setLimiterParams(
          limiterLookaheadMs, limiterThresholdDb, limiterReleaseMs);
    }
    _debouncedSavePreferences();
  }

  Future<void> setReverb(bool enabled, {int? preset, double? wetDry}) async {
    isReverbEnabled = enabled;
    if (preset != null) reverbPreset = preset;
    if (wetDry != null) reverbWetDry = wetDry;
    if (Platform.isAndroid) {
      if (preset != null) await _effectsChannel.setReverbPreset(preset);
      if (wetDry != null) await _effectsChannel.setReverbWetDry(wetDry);
      await _effectsChannel.setReverbEnabled(enabled);
    }
    _debouncedSavePreferences();
  }

  Future<void> loadCustomImpulseResponse(List<double> irSamples) async {
    if (Platform.isAndroid) {
      await _effectsChannel.loadImpulseResponse(irSamples);
      isReverbEnabled = true;
      reverbPreset = 4; // Custom
      await _effectsChannel.setReverbEnabled(true);
    }
    _debouncedSavePreferences();
  }

  Future<int> getPipelineLatencyFrames() =>
      _effectsChannel.getPipelineLatencyFrames();
  Future<void> setBandSolo(int index, bool solo) =>
      _effectsChannel.setBandSolo(index, solo);
  Future<void> setBandMute(int index, bool mute) =>
      _effectsChannel.setBandMute(index, mute);

  Future<void> setStereoBalance(double balance) async {
    stereoBalance = balance.clamp(-1.0, 1.0);
    if (Platform.isAndroid) {
      await _effectsChannel.setStereoBalance(stereoBalance);
    }
    _debouncedSavePreferences();
  }

  Future<void> setMonoMix(bool mono) async {
    monoMix = mono;
    if (Platform.isAndroid) {
      await _effectsChannel.setMonoMix(mono);
    }
    _debouncedSavePreferences();
  }

  Future<void> setSincResampler(bool enabled) async {
    isSincResamplerEnabled = enabled;
    if (Platform.isAndroid) {
      await _effectsChannel.setSincResamplerEnabled(enabled);
    }
    _debouncedSavePreferences();
  }

  static final Map<String, EqPreset> _genreEqMap = {
    'rock': const EqPreset(
        name: 'Rock',
        gains: [4.0, 3.0, -1.0, -1.0, 2.0, 4.0, 5.0, 5.0, 5.0, 6.0],
        bassBoost: 0.2),
    'pop': const EqPreset(
        name: 'Pop',
        gains: [-1.5, -0.5, 1.5, 3.0, 4.0, 3.5, 2.0, 0.5, -0.5, -1.0],
        bassBoost: 0.1),
    'jazz': const EqPreset(
        name: 'Jazz',
        gains: [3.0, 2.0, 1.0, 2.0, -1.0, -1.0, 0.0, 1.0, 2.0, 3.0],
        bassBoost: 0.0),
    'classical': const EqPreset(
        name: 'Classical',
        gains: [4.0, 3.0, 2.0, 1.0, -1.0, -1.0, 0.0, 2.0, 3.0, 4.0],
        bassBoost: 0.0),
    'electronic': const EqPreset(
        name: 'Electronic',
        gains: [5.0, 4.0, 2.0, 0.0, -1.0, 0.0, 2.0, 4.0, 5.0, 5.0],
        bassBoost: 0.3),
    'hip-hop': const EqPreset(
        name: 'Hip-Hop',
        gains: [5.0, 4.0, 3.0, 1.0, 0.0, 0.0, 1.0, 3.0, 4.0, 4.0],
        bassBoost: 0.35),
    'acoustic': const EqPreset(
        name: 'Acoustic',
        gains: [2.5, 1.5, 0.0, 1.0, 2.0, 2.5, 2.0, 1.5, 2.0, 2.5],
        bassBoost: 0.05),
    'metal': const EqPreset(
        name: 'Metal',
        gains: [4.5, 3.5, 0.0, -1.5, -2.0, 0.0, 3.0, 5.0, 5.5, 6.0],
        bassBoost: 0.25),
  };

  Future<bool> applyGenreBasedEq(String? genre) async {
    if (genre == null || genre.trim().isEmpty) return false;
    final normalized = genre.trim().toLowerCase();
    for (final entry in _genreEqMap.entries) {
      if (normalized.contains(entry.key)) {
        await setPreset(entry.value);
        return true;
      }
    }
    return false;
  }

  void dispose() {
    _saveDebounce?.cancel();
    _saveDebounce = null;
  }
}
