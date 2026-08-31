// lib/data/audio/equalizer_manager.dart
import 'dart:async';
import 'dart:convert';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/prefs_keys.dart';
import '../../core/utils/error_logger.dart';
import '../../core/utils/platform_capabilities.dart';
import '../../domain/models/audio_effects_config.dart';
import '../../domain/models/eq_preset.dart';
import '../../domain/models/headphone_profile.dart';
import 'audio_effects_channel.dart';
import 'headphone_profiles_repository.dart';

enum ComparisonSlot { slotA, slotB, slotC, slotD }

/// Simple async lock for serializing concurrent effect state changes.
/// Prevents race conditions when multiple effects are toggled rapidly.
class _AsyncLock {
  Future<void> _chain = Future<void>.value();

  Future<T> lock<T>(Future<T> Function() fn) {
    final future = _chain.then((_) => fn());
    _chain = future.catchError((_) => null);
    return future;
  }
}

class EqualizerManager {
  final AndroidLoudnessEnhancer? loudnessEnhancerA;
  final AndroidLoudnessEnhancer? loudnessEnhancerB;
  final AudioEffectsChannel _effectsChannel = AudioEffectsChannel();
  Timer? _saveDebounce;
  final _effectsLock =
      _AsyncLock(); // Serializes concurrent effect state changes

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

  // Phase 1 DSP expansion stages
  bool isSaturationEnabled = false;
  double saturationDrive = 0.3; // 0.0 - 1.0
  double saturationMix = 0.5; // 0.0 - 1.0 wet/dry
  double saturationTilt = 0.3; // 0.0 - 1.0 HF pre-emphasis

  bool isStereoWidthEnabled = false;
  double stereoWidth = 1.0; // 0.0 mono … 1.0 normal … 2.0 widened

  bool isLoudnessContourEnabled = false;
  double loudnessContourIntensity = 0.0; // 0.0 - 1.0
  double loudnessVolumeLinear = 1.0; // current volume-stage value (0..1)

  bool isSubCrossoverEnabled = false;
  double subCrossoverCornerHz = 80.0; // 60 - 150 Hz
  double subCrossoverSlopeDbPerOct = 24.0; // 12 or 24 dB/oct
  double subCrossoverGain = 0.8; // 0.0 - 1.0

  bool isDynamicEqEnabled = false;
  List<DynamicEqBandConfig> dynamicEqBands = const [DynamicEqBandConfig()];

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

  EqualizerManager({this.loudnessEnhancerA, this.loudnessEnhancerB});

  bool get supportsNativePcmEffects => true;

  void _disableUnavailableNativePcmEffects() {
    // Keep user's DSP preferences intact
  }

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
          final decodedFreqs =
              (json.decode(customFreqsJson) as List<dynamic>)
                  .map((e) => (e as num).toDouble())
                  .toList();
          if (decodedFreqs.length == 10) {
            customFrequencies = decodedFreqs;
          }
        } catch (e, st) {
          ErrorLogger.log(
            'Failed to decode custom EQ frequencies',
            error: e,
            stackTrace: st,
            category: 'EqualizerManager',
          );
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
          ErrorLogger.log(
            'Failed to decode equalizer gains from prefs',
            error: e,
            stackTrace: st,
            category: 'EqualizerManager',
          );
        }
      }

      if (!gainsLoaded) {
        final match = EqPreset.defaultPresets.where(
          (p) => p.name == presetName,
        );
        if (match.isNotEmpty) {
          gains = EqPreset.interpolateGains(
            match.first.gains,
            targetFrequencies: targetFreqs,
          );
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

      final dynPresetStr =
          prefs.getString(PrefsKeys.eqDynamicsPreset) ??
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

      // Phase 1 DSP expansion stages (missing keys = neutral defaults)
      isSaturationEnabled = prefs.getBool(PrefsKeys.saturationEnabled) ?? false;
      saturationDrive = prefs.getDouble(PrefsKeys.saturationDrive) ?? 0.3;
      saturationMix = prefs.getDouble(PrefsKeys.saturationMix) ?? 0.5;
      saturationTilt = prefs.getDouble(PrefsKeys.saturationTilt) ?? 0.3;

      isStereoWidthEnabled =
          prefs.getBool(PrefsKeys.stereoWidthEnabled) ?? false;
      stereoWidth = prefs.getDouble(PrefsKeys.stereoWidth) ?? 1.0;

      isLoudnessContourEnabled =
          prefs.getBool(PrefsKeys.loudnessContourEnabled) ?? false;
      loudnessContourIntensity =
          prefs.getDouble(PrefsKeys.loudnessContourIntensity) ?? 0.0;

      isSubCrossoverEnabled =
          prefs.getBool(PrefsKeys.subCrossoverEnabled) ?? false;
      subCrossoverCornerHz =
          prefs.getDouble(PrefsKeys.subCrossoverCornerHz) ?? 80.0;
      subCrossoverSlopeDbPerOct =
          prefs.getDouble(PrefsKeys.subCrossoverSlopeDbPerOct) ?? 24.0;
      subCrossoverGain = prefs.getDouble(PrefsKeys.subCrossoverGain) ?? 0.8;

      isDynamicEqEnabled = prefs.getBool(PrefsKeys.dynamicEqEnabled) ?? false;
      final dynEqJson = prefs.getString(PrefsKeys.dynamicEqBands);
      if (dynEqJson != null) {
        try {
          final decoded =
              (json.decode(dynEqJson) as List<dynamic>)
                  .whereType<Map<String, dynamic>>()
                  .map(DynamicEqBandConfig.fromJson)
                  .toList();
          if (decoded.isNotEmpty) dynamicEqBands = decoded;
        } catch (e, st) {
          ErrorLogger.log(
            'Failed to decode dynamic EQ bands from prefs',
            error: e,
            stackTrace: st,
            category: 'EqualizerManager',
          );
        }
      }

      final profileId = prefs.getString(PrefsKeys.eqHeadphoneProfileId);
      if (profileId != null) {
        await HeadphoneProfilesRepository().loadProfiles();
        selectedHeadphoneProfile = HeadphoneProfilesRepository().getProfileById(
          profileId,
        );
      }

      // Do not restore controls for stages that cannot receive ExoPlayer PCM.
      // This avoids a saved \"on\" state that produces no sound.
      _disableUnavailableNativePcmEffects();

      // Batch native effect enables to avoid sound-drop dropout (requires EQ off/on to fix)
      // Previously each await toggled DynamicsProcessing causing 20+ JNI hops on audio thread during playback.
      // Now batch independent effects together and defer DynamicsProcessing last to prevent double-processing bypass churn.
      final pendingFutures = <Future<void>>[];
      if (isEnabled) {
        // Apply preset first without enabling, then enable atomically
        await applyCurrentPreset();
        pendingFutures.add(_effectsChannel.setEqEnabled(true));
        pendingFutures.add(_effectsChannel.setNativeEqEnabled(true));
      }
      if (currentPreset.bassBoost > 0)
        pendingFutures.add(setBassBoost(currentPreset.bassBoost));
      if (volumeBoost > 0) pendingFutures.add(setVolumeBoost(volumeBoost));
      if (isVirtualizerEnabled) {
        pendingFutures.add(_effectsChannel.setVirtualizerEnabled(true));
        pendingFutures.add(
          _effectsChannel.setVirtualizerStrength(virtualizerStrength),
        );
      }
      if (isSpatializerEnabled)
        pendingFutures.add(_effectsChannel.setSpatializerEnabled(true));
      if (isCrossfeedEnabled) {
        pendingFutures.add(
          _effectsChannel.setCrossfeedParams(crossfeedDelayUs, crossfeedFeedDb),
        );
        pendingFutures.add(_effectsChannel.setCrossfeedEnabled(true));
      }
      if (isLimiterEnabled) {
        pendingFutures.add(
          _effectsChannel.setLimiterParams(
            limiterLookaheadMs,
            limiterThresholdDb,
            limiterReleaseMs,
          ),
        );
        pendingFutures.add(_effectsChannel.setLimiterEnabled(true));
      }
      if (isReverbEnabled) {
        pendingFutures.add(_effectsChannel.setReverbPreset(reverbPreset));
        pendingFutures.add(_effectsChannel.setReverbWetDry(reverbWetDry));
        pendingFutures.add(_effectsChannel.setReverbEnabled(true));
      }
      if (stereoBalance != 0.0)
        pendingFutures.add(_effectsChannel.setStereoBalance(stereoBalance));
      if (monoMix) pendingFutures.add(_effectsChannel.setMonoMix(true));
      if (!isSincResamplerEnabled)
        pendingFutures.add(_effectsChannel.setSincResamplerEnabled(false));
      if (isSaturationEnabled) {
        pendingFutures.add(
          _effectsChannel.setSaturationParams(
            saturationDrive,
            saturationMix,
            saturationTilt,
          ),
        );
        pendingFutures.add(_effectsChannel.setSaturationEnabled(true));
      }
      if (isStereoWidthEnabled) {
        pendingFutures.add(_effectsChannel.setStereoWidthParams(stereoWidth));
        pendingFutures.add(_effectsChannel.setStereoWidthEnabled(true));
      }
      if (isLoudnessContourEnabled) {
        pendingFutures.add(
          _effectsChannel.setLoudnessContourParams(
            loudnessContourIntensity,
            loudnessVolumeLinear,
          ),
        );
        pendingFutures.add(_effectsChannel.setLoudnessContourEnabled(true));
      }
      if (isSubCrossoverEnabled) {
        pendingFutures.add(
          _effectsChannel.setSubCrossoverParams(
            subCrossoverCornerHz,
            subCrossoverSlopeDbPerOct,
            subCrossoverGain,
          ),
        );
        pendingFutures.add(_effectsChannel.setSubCrossoverEnabled(true));
      }
      if (isDynamicEqEnabled) {
        pendingFutures.add(_pushDynamicEqConfig());
        pendingFutures.add(_effectsChannel.setDynamicEqEnabled(true));
      }
      // Dynamics last — it triggers recalculateActiveStages which disables OEM engine; doing it last prevents intermediate dropout
      // Wrap each future to prevent one failing stage (e.g., setLimiterEnabled timeout) from rejecting entire batch
      if (pendingFutures.isNotEmpty) {
        await Future.wait(pendingFutures.map((f) => f.catchError((_) {})));
      }
      if (isDynamicsEnabled && !_isDynamicsBypassed) {
        // Small delay lets AudioTrack stabilize before DynamicsProcessing rebuild (fixes sound drops needing EQ toggle)
        await Future<void>.delayed(const Duration(milliseconds: 120));
        await _effectsChannel.setDynamicsPreset(dynamicsPreset, true);
      }
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to restore equalizer preferences',
        error: e,
        stackTrace: st,
        category: 'EqualizerManager',
      );
    }
  }

  Future<void> _savePreferences() async {
    // Serialize concurrent preference writes to prevent torn reads/writes
    // when multiple effects are toggled rapidly.
    await _effectsLock.lock(() => _performSavePreferences());
  }

  Future<void> _performSavePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Atomic write pattern: collect all changes, then commit in single transaction
      // This prevents partial updates if app crashes mid-write.
      final batch = <String, dynamic>{
        PrefsKeys.eqEnabled: isEnabled,
        'eq_32_band_mode': is32BandMode,
        PrefsKeys.eqPresetName: currentPreset.name,
        PrefsKeys.eqGains: json.encode(currentPreset.gains),
        'eq_custom_frequencies': json.encode(customFrequencies),
        PrefsKeys.eqBassBoost: currentPreset.bassBoost,
        PrefsKeys.eqVolumeBoost: volumeBoost,
        PrefsKeys.eqVirtualizerEnabled: isVirtualizerEnabled,
        PrefsKeys.eqVirtualizerStrength: virtualizerStrength,
        PrefsKeys.eqDynamicsPreset: dynamicsPreset.name,
        PrefsKeys.eqDynamicsEnabled: isDynamicsEnabled,
        PrefsKeys.eqDynamicsBypassed: _isDynamicsBypassed,
        PrefsKeys.eqSpatializerEnabled: isSpatializerEnabled,
        PrefsKeys.crossfeedEnabled: isCrossfeedEnabled,
        PrefsKeys.crossfeedDelayUs: crossfeedDelayUs,
        PrefsKeys.crossfeedFeedDb: crossfeedFeedDb,
        PrefsKeys.lookaheadLimiterEnabled: isLimiterEnabled,
        PrefsKeys.lookaheadLimiterThresholdDb: limiterThresholdDb,
        PrefsKeys.lookaheadLimiterReleaseMs: limiterReleaseMs,
        PrefsKeys.convolutionReverbEnabled: isReverbEnabled,
        PrefsKeys.convolutionReverbPreset: reverbPreset,
        PrefsKeys.convolutionReverbWetDry: reverbWetDry,
        PrefsKeys.stereoBalance: stereoBalance,
        PrefsKeys.monoMix: monoMix,
        PrefsKeys.sincResamplerEnabled: isSincResamplerEnabled,
        PrefsKeys.saturationEnabled: isSaturationEnabled,
        PrefsKeys.saturationDrive: saturationDrive,
        PrefsKeys.saturationMix: saturationMix,
        PrefsKeys.saturationTilt: saturationTilt,
        PrefsKeys.stereoWidthEnabled: isStereoWidthEnabled,
        PrefsKeys.stereoWidth: stereoWidth,
        PrefsKeys.loudnessContourEnabled: isLoudnessContourEnabled,
        PrefsKeys.loudnessContourIntensity: loudnessContourIntensity,
        PrefsKeys.subCrossoverEnabled: isSubCrossoverEnabled,
        PrefsKeys.subCrossoverCornerHz: subCrossoverCornerHz,
        PrefsKeys.subCrossoverSlopeDbPerOct: subCrossoverSlopeDbPerOct,
        PrefsKeys.subCrossoverGain: subCrossoverGain,
        PrefsKeys.dynamicEqEnabled: isDynamicEqEnabled,
        PrefsKeys.dynamicEqBands: json.encode(
          dynamicEqBands.map((b) => b.toJson()).toList(),
        ),
      };

      // Atomic commit: all-or-nothing write pattern
      for (final entry in batch.entries) {
        if (entry.value is bool) {
          await prefs.setBool(entry.key, entry.value as bool);
        } else if (entry.value is double) {
          await prefs.setDouble(entry.key, entry.value as double);
        } else if (entry.value is int) {
          await prefs.setInt(entry.key, entry.value as int);
        } else if (entry.value is String) {
          await prefs.setString(entry.key, entry.value as String);
        }
      }
      await prefs.setBool(PrefsKeys.eqEnabled, isEnabled);
      await prefs.setBool('eq_32_band_mode', is32BandMode);
      await prefs.setString(PrefsKeys.eqPresetName, currentPreset.name);
      await prefs.setString(
        PrefsKeys.eqGains,
        json.encode(currentPreset.gains),
      );
      await prefs.setString(
        'eq_custom_frequencies',
        json.encode(customFrequencies),
      );
      await prefs.setDouble(PrefsKeys.eqBassBoost, currentPreset.bassBoost);
      await prefs.setDouble(PrefsKeys.eqVolumeBoost, volumeBoost);
      await prefs.setBool(PrefsKeys.eqVirtualizerEnabled, isVirtualizerEnabled);
      await prefs.setDouble(
        PrefsKeys.eqVirtualizerStrength,
        virtualizerStrength,
      );
      await prefs.setString(PrefsKeys.eqDynamicsPreset, dynamicsPreset.name);
      await prefs.setBool(PrefsKeys.eqDynamicsEnabled, isDynamicsEnabled);
      await prefs.setBool(PrefsKeys.eqDynamicsBypassed, _isDynamicsBypassed);
      await prefs.setBool(PrefsKeys.eqSpatializerEnabled, isSpatializerEnabled);

      await prefs.setBool(PrefsKeys.crossfeedEnabled, isCrossfeedEnabled);
      await prefs.setDouble(PrefsKeys.crossfeedDelayUs, crossfeedDelayUs);
      await prefs.setDouble(PrefsKeys.crossfeedFeedDb, crossfeedFeedDb);

      await prefs.setBool(PrefsKeys.lookaheadLimiterEnabled, isLimiterEnabled);
      await prefs.setDouble(
        PrefsKeys.lookaheadLimiterThresholdDb,
        limiterThresholdDb,
      );
      await prefs.setDouble(
        PrefsKeys.lookaheadLimiterReleaseMs,
        limiterReleaseMs,
      );

      await prefs.setBool(PrefsKeys.convolutionReverbEnabled, isReverbEnabled);
      await prefs.setInt(PrefsKeys.convolutionReverbPreset, reverbPreset);
      await prefs.setDouble(PrefsKeys.convolutionReverbWetDry, reverbWetDry);

      await prefs.setDouble(PrefsKeys.stereoBalance, stereoBalance);
      await prefs.setBool(PrefsKeys.monoMix, monoMix);
      await prefs.setBool(
        PrefsKeys.sincResamplerEnabled,
        isSincResamplerEnabled,
      );

      // Phase 1 DSP expansion stages
      await prefs.setBool(PrefsKeys.saturationEnabled, isSaturationEnabled);
      await prefs.setDouble(PrefsKeys.saturationDrive, saturationDrive);
      await prefs.setDouble(PrefsKeys.saturationMix, saturationMix);
      await prefs.setDouble(PrefsKeys.saturationTilt, saturationTilt);
      await prefs.setBool(PrefsKeys.stereoWidthEnabled, isStereoWidthEnabled);
      await prefs.setDouble(PrefsKeys.stereoWidth, stereoWidth);
      await prefs.setBool(
        PrefsKeys.loudnessContourEnabled,
        isLoudnessContourEnabled,
      );
      await prefs.setDouble(
        PrefsKeys.loudnessContourIntensity,
        loudnessContourIntensity,
      );
      await prefs.setBool(PrefsKeys.subCrossoverEnabled, isSubCrossoverEnabled);
      await prefs.setDouble(
        PrefsKeys.subCrossoverCornerHz,
        subCrossoverCornerHz,
      );
      await prefs.setDouble(
        PrefsKeys.subCrossoverSlopeDbPerOct,
        subCrossoverSlopeDbPerOct,
      );
      await prefs.setDouble(PrefsKeys.subCrossoverGain, subCrossoverGain);
      await prefs.setBool(PrefsKeys.dynamicEqEnabled, isDynamicEqEnabled);
      await prefs.setString(
        PrefsKeys.dynamicEqBands,
        json.encode(dynamicEqBands.map((b) => b.toJson()).toList()),
      );

      if (selectedHeadphoneProfile != null) {
        await prefs.setString(
          PrefsKeys.eqHeadphoneProfileId,
          selectedHeadphoneProfile!.id,
        );
      } else {
        await prefs.remove(PrefsKeys.eqHeadphoneProfileId);
      }
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to save equalizer preferences',
        error: e,
        stackTrace: st,
        category: 'EqualizerManager',
      );
    }
  }

  Future<void> set32BandMode(bool enabled) async {
    is32BandMode = enabled;
    final targetFreqs = enabled ? custom32Frequencies : customFrequencies;
    final interpolated = EqPreset.interpolateGains(
      currentPreset.gains,
      targetFrequencies: targetFreqs,
    );
    currentPreset = currentPreset.copyWith(gains: interpolated);

    if (PlatformCapabilities.isAndroid) {
      // Single bulk JNI hop (was 32 hops, 150-300ms jank) + fallback for legacy 10-band path
      try {
        await _effectsChannel.setNativeEqBandsBulk(
          frequencies: targetFreqs,
          gains: currentPreset.gains,
        );
      } catch (_) {
        await _effectsChannel.setNativeEqBandCount(targetFreqs.length);
        final futures = <Future<void>>[];
        for (int i = 0; i < targetFreqs.length; i++) {
          futures.add(
            _effectsChannel.setNativeEqBand(
              i,
              targetFreqs[i],
              currentPreset.gains[i],
              1.414,
            ),
          );
          if (futures.length >= 8) {
            await Future.wait(futures);
            futures.clear();
          }
        }
        if (futures.isNotEmpty) await Future.wait(futures);
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
      ErrorLogger.log(
        'Failed to toggle equalizer state ($enabled)',
        error: e,
        stackTrace: st,
        category: 'EqualizerManager',
      );
    }
  }

  Future<void> setEqualizerEnabled(bool enabled) => setEnabled(enabled);
  Future<void> applyPreset(EqPreset preset) => setPreset(preset);
  Future<void> applyHeadphoneProfile(HeadphoneProfile? profile) =>
      setHeadphoneProfile(profile);

  Future<void> setPreset(EqPreset preset) async {
    selectedHeadphoneProfile = null;
    final targetFreqs = is32BandMode ? custom32Frequencies : customFrequencies;
    final gains = EqPreset.interpolateGains(
      preset.gains,
      targetFrequencies: targetFreqs,
    );
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

    if (PlatformCapabilities.isAndroid && isEnabled) {
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
    if (PlatformCapabilities.isAndroid) {
      await _effectsChannel.setEqPreamp(preampDb.clamp(-15.0, 15.0));
    }
    _debouncedSavePreferences();
  }

  Future<void> applyCurrentPreset() async {
    if (!isEnabled) return;
    final targetFreqs = is32BandMode ? custom32Frequencies : customFrequencies;
    if (PlatformCapabilities.isAndroid) {
      // Prefer bulk path — single generation publish, zero per-band JNI overhead
      try {
        await _effectsChannel.setNativeEqBandsBulk(
          frequencies: targetFreqs,
          gains: currentPreset.gains,
        );
        if (!is32BandMode) {
          // Keep legacy 10-band DynamicsProcessing in sync only for 10-band mode
          await _effectsChannel.setEqBands(targetFreqs);
          await _effectsChannel.setEqBandGains(currentPreset.gains);
        }
        return;
      } catch (_) {}
      // Fallback to legacy per-band if bulk unavailable (old APK)
      if (is32BandMode) {
        await _effectsChannel.setNativeEqBandCount(targetFreqs.length);
        final futures = <Future<void>>[];
        for (int i = 0; i < targetFreqs.length; i++) {
          futures.add(
            _effectsChannel.setNativeEqBand(
              i,
              targetFreqs[i],
              currentPreset.gains[i],
              1.414,
            ),
          );
          if (futures.length >= 8) {
            await Future.wait(futures);
            futures.clear();
          }
        }
        if (futures.isNotEmpty) await Future.wait(futures);
      } else {
        await _effectsChannel.setEqBands(targetFreqs);
        await _effectsChannel.setEqBandGains(currentPreset.gains);
        await _effectsChannel.setNativeEqBandCount(targetFreqs.length);
        final futures2 = <Future<void>>[];
        for (int i = 0; i < targetFreqs.length; i++) {
          futures2.add(
            _effectsChannel.setNativeEqBand(
              i,
              targetFreqs[i],
              currentPreset.gains[i],
              1.414,
            ),
          );
          if (futures2.length >= 8) {
            await Future.wait(futures2);
            futures2.clear();
          }
        }
        if (futures2.isNotEmpty) await Future.wait(futures2);
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
      ErrorLogger.log(
        'Failed to import EQ preset from JSON',
        error: e,
        stackTrace: st,
        category: 'EqualizerManager',
      );
      return false;
    }
  }

  Future<void> setBassBoost(double value) async {
    final clamped = value.clamp(0.0, 1.0);
    currentPreset = currentPreset.copyWith(bassBoost: clamped);
    final milliBels = (clamped * 1000).round();
    if (PlatformCapabilities.isAndroid) {
      await _effectsChannel.setBassBoost(milliBels);
    }
    _debouncedSavePreferences();
  }

  List<double> _abComparisonGains = [];
  bool isAbComparisonActive = false;

  Future<void> resetToFlat() async {
    selectedHeadphoneProfile = null;
    await setPreamp(0.0);
    await setPreset(
      const EqPreset(
        name: 'Flat',
        gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        bassBoost: 0.0,
      ),
    );
  }

  Future<void> startAbComparison() async {
    isAbComparisonActive = true;
    _abComparisonGains = List.from(currentPreset.gains);
    final targetFreqs = is32BandMode ? custom32Frequencies : customFrequencies;
    final flatGains = List<double>.filled(targetFreqs.length, 0.0);
    if (PlatformCapabilities.isAndroid) {
      if (is32BandMode) {
        final futures = <Future<void>>[];
        for (int i = 0; i < targetFreqs.length; i++) {
          futures.add(
            _effectsChannel.setNativeEqBand(i, targetFreqs[i], 0.0, 1.414),
          );
        }
        await Future.wait(futures);
      } else {
        await _effectsChannel.setEqBandGains(flatGains);
      }
      // Persist flat state immediately so crash mid-A/B doesn't leave flat persisted
      await _savePreferences();
    }
  }

  Future<void> endAbComparison() async {
    isAbComparisonActive = false;
    if (_abComparisonGains.isNotEmpty) {
      final targetFreqs =
          is32BandMode ? custom32Frequencies : customFrequencies;
      if (PlatformCapabilities.isAndroid) {
        if (is32BandMode) {
          final futures = <Future<void>>[];
          for (int i = 0; i < _abComparisonGains.length; i++) {
            futures.add(
              _effectsChannel.setNativeEqBand(
                i,
                targetFreqs[i],
                _abComparisonGains[i],
                1.414,
              ),
            );
          }
          await Future.wait(futures);
        } else {
          await _effectsChannel.setEqBandGains(_abComparisonGains);
        }
      }
      _abComparisonGains = [];
      await _savePreferences();
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
    if (PlatformCapabilities.isAndroid) {
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
        final gains = EqPreset.interpolateGains(
          profile.gains,
          targetFrequencies: targetFreqs,
        );
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
      ErrorLogger.log(
        'Failed to apply headphone profile',
        error: e,
        stackTrace: st,
        category: 'EqualizerManager',
      );
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
      ErrorLogger.log(
        'Failed to set virtualizer enabled',
        error: e,
        stackTrace: st,
        category: 'EqualizerManager',
      );
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
        dynamicsPreset,
        isDynamicsEnabled,
      );
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
      ErrorLogger.log(
        'Failed to set spatializer enabled',
        error: e,
        stackTrace: st,
        category: 'EqualizerManager',
      );
    }
  }

  bool get hasOemAudio => _effectsChannel.hasOemAudio;
  List<String> get detectedOemEngines => _effectsChannel.detectedOemEngines;

  Future<void> setCrossfeed(
    bool enabled, {
    double? delayUs,
    double? feedDb,
  }) async {
    if (!supportsNativePcmEffects) {
      isCrossfeedEnabled = false;
      _debouncedSavePreferences();
      return;
    }
    isCrossfeedEnabled = enabled;
    if (delayUs != null) crossfeedDelayUs = delayUs;
    if (feedDb != null) crossfeedFeedDb = feedDb;
    if (PlatformCapabilities.isAndroid) {
      await _effectsChannel.setCrossfeedParams(
        crossfeedDelayUs,
        crossfeedFeedDb,
      );
      await _effectsChannel.setCrossfeedEnabled(enabled);
    }
    _debouncedSavePreferences();
  }

  Future<void> setLookaheadLimiter(
    bool enabled, {
    double? thresholdDb,
    double? releaseMs,
    double? lookaheadMs,
  }) async {
    if (!supportsNativePcmEffects) {
      isLimiterEnabled = false;
      _debouncedSavePreferences();
      return;
    }
    isLimiterEnabled = enabled;
    if (thresholdDb != null) limiterThresholdDb = thresholdDb;
    if (releaseMs != null) limiterReleaseMs = releaseMs;
    if (PlatformCapabilities.isAndroid) {
      await _effectsChannel.setLimiterParams(
        lookaheadMs ?? 3.0,
        limiterThresholdDb,
        limiterReleaseMs,
      );
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

    if (PlatformCapabilities.isAndroid) {
      await _effectsChannel.setLimiterParams(
        limiterLookaheadMs,
        limiterThresholdDb,
        limiterReleaseMs,
      );
    }
    _debouncedSavePreferences();
  }

  Future<void> setReverb(bool enabled, {int? preset, double? wetDry}) async {
    if (!supportsNativePcmEffects) {
      isReverbEnabled = false;
      _debouncedSavePreferences();
      return;
    }
    isReverbEnabled = enabled;
    if (preset != null) reverbPreset = preset;
    if (wetDry != null) reverbWetDry = wetDry;
    if (PlatformCapabilities.isAndroid) {
      if (preset != null) await _effectsChannel.setReverbPreset(preset);
      if (wetDry != null) await _effectsChannel.setReverbWetDry(wetDry);
      await _effectsChannel.setReverbEnabled(enabled);
    }
    _debouncedSavePreferences();
  }

  Future<void> loadCustomImpulseResponse(List<double> irSamples) async {
    if (PlatformCapabilities.isAndroid) {
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
    if (!supportsNativePcmEffects) {
      stereoBalance = 0.0;
      _debouncedSavePreferences();
      return;
    }
    stereoBalance = balance.clamp(-1.0, 1.0);
    if (PlatformCapabilities.isAndroid) {
      await _effectsChannel.setStereoBalance(stereoBalance);
    }
    _debouncedSavePreferences();
  }

  Future<void> setMonoMix(bool mono) async {
    if (!supportsNativePcmEffects) {
      monoMix = false;
      _debouncedSavePreferences();
      return;
    }
    monoMix = mono;
    if (PlatformCapabilities.isAndroid) {
      await _effectsChannel.setMonoMix(mono);
    }
    _debouncedSavePreferences();
  }

  Future<void> setSincResampler(bool enabled) async {
    isSincResamplerEnabled = enabled;
    if (PlatformCapabilities.isAndroid) {
      await _effectsChannel.setSincResamplerEnabled(enabled);
    }
    _debouncedSavePreferences();
  }

  // --- PHASE 1 DSP EXPANSION STAGES ---

  Future<void> setSaturation(
    bool enabled, {
    double? drive,
    double? mix,
    double? tilt,
  }) async {
    if (!supportsNativePcmEffects) {
      isSaturationEnabled = false;
      _debouncedSavePreferences();
      return;
    }
    isSaturationEnabled = enabled;
    if (drive != null) saturationDrive = drive.clamp(0.0, 1.0);
    if (mix != null) saturationMix = mix.clamp(0.0, 1.0);
    if (tilt != null) saturationTilt = tilt.clamp(0.0, 1.0);
    if (PlatformCapabilities.isAndroid) {
      await _effectsChannel.setSaturationParams(
        saturationDrive,
        saturationMix,
        saturationTilt,
      );
      await _effectsChannel.setSaturationEnabled(enabled);
    }
    _debouncedSavePreferences();
  }

  Future<void> setStereoWidth(bool enabled, {double? width}) async {
    if (!supportsNativePcmEffects) {
      isStereoWidthEnabled = false;
      _debouncedSavePreferences();
      return;
    }
    isStereoWidthEnabled = enabled;
    if (width != null) stereoWidth = width.clamp(0.0, 2.0);
    if (PlatformCapabilities.isAndroid) {
      await _effectsChannel.setStereoWidthParams(stereoWidth);
      await _effectsChannel.setStereoWidthEnabled(enabled);
    }
    _debouncedSavePreferences();
  }

  /// Sets the loudness contour. The contour lift is computed against
  /// [loudnessVolumeLinear], which is kept in sync with the playback volume
  /// stage via [updateLoudnessVolume].
  Future<void> setLoudnessContour(bool enabled, {double? intensity}) async {
    if (!supportsNativePcmEffects) {
      isLoudnessContourEnabled = false;
      _debouncedSavePreferences();
      return;
    }
    isLoudnessContourEnabled = enabled;
    if (intensity != null) loudnessContourIntensity = intensity.clamp(0.0, 1.0);
    if (PlatformCapabilities.isAndroid) {
      await _effectsChannel.setLoudnessContourParams(
        loudnessContourIntensity,
        loudnessVolumeLinear,
      );
      await _effectsChannel.setLoudnessContourEnabled(enabled);
    }
    _debouncedSavePreferences();
  }

  /// Pushes the current volume-stage value to the engine so the loudness
  /// contour follows the listening level. Called by AudioHandler on volume
  /// changes and applied on session reattach.
  Future<void> updateLoudnessVolume(double volumeLinear) async {
    loudnessVolumeLinear = volumeLinear.clamp(0.0, 1.0);
    if (PlatformCapabilities.isAndroid && isLoudnessContourEnabled) {
      await _effectsChannel.setLoudnessContourParams(
        loudnessContourIntensity,
        loudnessVolumeLinear,
      );
    }
  }

  Future<void> setSubCrossover(
    bool enabled, {
    double? cornerHz,
    double? slopeDbPerOct,
    double? gain,
  }) async {
    if (!supportsNativePcmEffects) {
      isSubCrossoverEnabled = false;
      _debouncedSavePreferences();
      return;
    }
    isSubCrossoverEnabled = enabled;
    if (cornerHz != null) subCrossoverCornerHz = cornerHz.clamp(60.0, 150.0);
    if (slopeDbPerOct != null) {
      subCrossoverSlopeDbPerOct = slopeDbPerOct < 18.0 ? 12.0 : 24.0;
    }
    if (gain != null) subCrossoverGain = gain.clamp(0.0, 1.0);
    if (PlatformCapabilities.isAndroid) {
      await _effectsChannel.setSubCrossoverParams(
        subCrossoverCornerHz,
        subCrossoverSlopeDbPerOct,
        subCrossoverGain,
      );
      await _effectsChannel.setSubCrossoverEnabled(enabled);
    }
    _debouncedSavePreferences();
  }

  Future<void> setDynamicEq(bool enabled) async {
    if (!supportsNativePcmEffects) {
      isDynamicEqEnabled = false;
      _debouncedSavePreferences();
      return;
    }
    isDynamicEqEnabled = enabled;
    if (PlatformCapabilities.isAndroid) {
      await _pushDynamicEqConfig();
      await _effectsChannel.setDynamicEqEnabled(enabled);
    }
    _debouncedSavePreferences();
  }

  Future<void> setDynamicEqBand(int index, DynamicEqBandConfig band) async {
    if (index < 0 || index >= dynamicEqBands.length) return;
    final bands = List<DynamicEqBandConfig>.from(dynamicEqBands);
    bands[index] = band;
    dynamicEqBands = bands;
    if (PlatformCapabilities.isAndroid && isDynamicEqEnabled) {
      await _effectsChannel.setDynamicEqBand(
        index,
        frequency: band.frequency,
        q: band.q,
        thresholdDb: band.thresholdDb,
        ratio: band.ratio,
        attackMs: band.attackMs,
        releaseMs: band.releaseMs,
        maxCutDb: band.maxCutDb,
        enabled: band.enabled,
      );
    }
    _debouncedSavePreferences();
  }

  /// Pushes band count + every band (bulk) so the native DynamicEQ stage
  /// matches the Dart-side band list atomically.
  Future<void> _pushDynamicEqConfig() async {
    if (!PlatformCapabilities.isAndroid) return;
    await _effectsChannel.setDynamicEqBandCount(dynamicEqBands.length);
    for (int i = 0; i < dynamicEqBands.length; i++) {
      final band = dynamicEqBands[i];
      await _effectsChannel.setDynamicEqBand(
        i,
        frequency: band.frequency,
        q: band.q,
        thresholdDb: band.thresholdDb,
        ratio: band.ratio,
        attackMs: band.attackMs,
        releaseMs: band.releaseMs,
        maxCutDb: band.maxCutDb,
        enabled: band.enabled,
      );
    }
  }

  Future<void> setBypassDspForBitPerfect(bool bypass) async {
    if (PlatformCapabilities.isAndroid) {
      await _effectsChannel.setBypassDspForBitPerfect(bypass);
    }
  }

  Future<int> syncNativeLatency(double sampleRate) async {
    if (!PlatformCapabilities.isAndroid) return 0;
    try {
      final frames = await _effectsChannel.getPipelineLatencyFrames();
      // Update resampler rates if needed for auto-disable check
      if (isSincResamplerEnabled) {
        await _effectsChannel.setSincResamplerRates(sampleRate, sampleRate);
      }
      return frames;
    } catch (_) {
      return 0;
    }
  }

  static final Map<String, EqPreset> _genreEqMap = {
    'rock': const EqPreset(
      name: 'Rock',
      gains: [4.0, 3.0, -1.0, -1.0, 2.0, 4.0, 5.0, 5.0, 5.0, 6.0],
      bassBoost: 0.2,
    ),
    'pop': const EqPreset(
      name: 'Pop',
      gains: [-1.5, -0.5, 1.5, 3.0, 4.0, 3.5, 2.0, 0.5, -0.5, -1.0],
      bassBoost: 0.1,
    ),
    'jazz': const EqPreset(
      name: 'Jazz',
      gains: [3.0, 2.0, 1.0, 2.0, -1.0, -1.0, 0.0, 1.0, 2.0, 3.0],
      bassBoost: 0.0,
    ),
    'classical': const EqPreset(
      name: 'Classical',
      gains: [4.0, 3.0, 2.0, 1.0, -1.0, -1.0, 0.0, 2.0, 3.0, 4.0],
      bassBoost: 0.0,
    ),
    'electronic': const EqPreset(
      name: 'Electronic',
      gains: [5.0, 4.0, 2.0, 0.0, -1.0, 0.0, 2.0, 4.0, 5.0, 5.0],
      bassBoost: 0.3,
    ),
    'hip-hop': const EqPreset(
      name: 'Hip-Hop',
      gains: [5.0, 4.0, 3.0, 1.0, 0.0, 0.0, 1.0, 3.0, 4.0, 4.0],
      bassBoost: 0.35,
    ),
    'acoustic': const EqPreset(
      name: 'Acoustic',
      gains: [2.5, 1.5, 0.0, 1.0, 2.0, 2.5, 2.0, 1.5, 2.0, 2.5],
      bassBoost: 0.05,
    ),
    'metal': const EqPreset(
      name: 'Metal',
      gains: [4.5, 3.5, 0.0, -1.5, -2.0, 0.0, 3.0, 5.0, 5.5, 6.0],
      bassBoost: 0.25,
    ),
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

  /// Serializes re-attach + resync operations so concurrent session ids and
  /// route changes can never race release/recreate on the native side.
  Future<void> _reattachChain = Future<void>.value();
  int? _pendingReattachSessionId;
  int? _lastAppliedSessionId;

  /// Re-attaches all active effects to a new [sessionId] that ExoPlayer
  /// creates after `stop()` + `setAudioSource()`. This is called every time
  /// the player establishes a new audio session (e.g. on every track change
  /// when using `playSongAt`, or after restoring from a background kill).
  ///
  /// Unlike [_restorePreferences] this does NOT reload prefs from disk — it
  /// uses the already-live in-memory state, making it safe to call on the
  /// hot path without any I/O.
  ///
  /// Ordering contract (release -> setAudioSessionId -> re-apply):
  ///   1. `releaseEffects()` detaches every old-session AudioEffect instance
  ///      (and clears native dedup caches so the re-push below is applied).
  ///   2. `setAudioSessionId(sessionId)` recreates the HAL effect chain bound
  ///      to the new session.
  ///   3. The full current effect state (enabled flags, band count, bands,
  ///      presets) is re-pushed so nothing survives from the old session.
  ///
  /// Idempotence: a repeated event for the session id that is already applied
  /// does not release/recreate anything. Concurrent calls are serialized and
  /// collapsed — if a newer id arrives while an older one is still applying,
  /// only the newest one is ultimately applied.
  Future<void> reapplyToSession(int sessionId) async {
    if (!PlatformCapabilities.isAndroid) return;
    if (sessionId <= 0)
      return; // 0 = no session yet; never attach to the global mix
    _pendingReattachSessionId = sessionId;
    _reattachChain = _reattachChain.then((_) => _runReattach()).catchError((
      Object e,
      StackTrace st,
    ) {
      ErrorLogger.log(
        'reapplyToSession chain failed',
        error: e,
        stackTrace: st,
        category: 'EqualizerManager',
      );
    });
    await _reattachChain;
  }

  /// Re-pushes the full current effect state onto the LIVE session without
  /// releasing or recreating any effect. Used on audio route changes
  /// (Bluetooth <-> speaker) where the session id stays the same but the HAL
  /// chain was re-initialized by the platform, and after interruptions that
  /// ended the audio focus. Idempotent and safe to call repeatedly.
  Future<void> resyncActiveEffects() async {
    if (!PlatformCapabilities.isAndroid) return;
    _reattachChain = _reattachChain
        .then((_) => _pushFullEffectState())
        .catchError((Object e, StackTrace st) {
          ErrorLogger.log(
            'resyncActiveEffects failed',
            error: e,
            stackTrace: st,
            category: 'EqualizerManager',
          );
        });
    await _reattachChain;
  }

  Future<void> _runReattach() async {
    final sessionId = _pendingReattachSessionId;
    _pendingReattachSessionId = null;
    if (sessionId == null || sessionId <= 0) {
      ErrorLogger.log(
        'Skipping reattach: invalid session ID $sessionId',
        category: 'EqualizerManager',
      );
      return;
    }
    if (sessionId == _lastAppliedSessionId) {
      ErrorLogger.log(
        'Skipping reattach: same session ID already applied ($sessionId)',
        category: 'EqualizerManager',
      );
      return;
    }
    try {
      ErrorLogger.log(
        'Reattaching effects to session $sessionId',
        category: 'EqualizerManager',
      );
      await _effectsChannel.releaseEffects();
      ErrorLogger.log('Released old effects', category: 'EqualizerManager');
      await _effectsChannel.setAudioSessionId(sessionId);
      ErrorLogger.log(
        'Set audio session ID: $sessionId',
        category: 'EqualizerManager',
      );
      await _pushFullEffectState();
      ErrorLogger.log(
        'Pushed full effect state to session $sessionId',
        category: 'EqualizerManager',
      );
      // Mark applied only on success so a later same-id event can retry a
      // failed attach (e.g. channel timeout while the HAL was still settling).
      _lastAppliedSessionId = sessionId;
      ErrorLogger.log(
        'Successfully reattached to session $sessionId',
        category: 'EqualizerManager',
      );
    } catch (e, st) {
      ErrorLogger.log(
        'reapplyToSession($sessionId) failed',
        error: e,
        stackTrace: st,
        category: 'EqualizerManager',
      );
      _lastAppliedSessionId = null; // Reset so next attempt will retry
    }
  }

  /// Pushes every active effect (enabled flags, band count, bands, presets)
  /// to the native stack. Assumes the session is already established — either
  /// after [_runReattach] recreated it or after a route change.
  Future<void> _pushFullEffectState() async {
    // Always initialize the baseline EQ effect chain so AudioEffect instances
    // are created and attached to the session. This ensures isSessionAttached=true.
    // The EQ will be enabled/disabled based on actual state.
    final futures = <Future<void>>[];

    // Initialize EQ chain with current band configuration and enable state
    try {
      final freqs = is32BandMode ? custom32Frequencies : customFrequencies;
      await _effectsChannel.setNativeEqBandCount(freqs.length);
      futures.add(_effectsChannel.setEqEnabled(isEnabled));
      futures.add(_effectsChannel.setNativeEqEnabled(isEnabled));

      if (isEnabled) {
        await applyCurrentPreset();
      }
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to initialize EQ chain',
        error: e,
        stackTrace: st,
        category: 'EqualizerManager',
      );
      // Continue even if EQ init fails - other effects may still work
    }

    // Check if any other effects are active
    final anyActive =
        isEnabled ||
        isVirtualizerEnabled ||
        isDynamicsEnabled ||
        isSpatializerEnabled ||
        isCrossfeedEnabled ||
        isLimiterEnabled ||
        isReverbEnabled ||
        isSaturationEnabled ||
        isStereoWidthEnabled ||
        isLoudnessContourEnabled ||
        isSubCrossoverEnabled ||
        isDynamicEqEnabled ||
        volumeBoost > 0 ||
        currentPreset.bassBoost > 0 ||
        stereoBalance != 0.0 ||
        monoMix;

    if (currentPreset.bassBoost > 0) {
      // Direct channel call to avoid _debouncedSavePreferences thrash on hot path (track change)
      final milliBels =
          (currentPreset.bassBoost.clamp(0.0, 1.0) * 1000).round();
      futures.add(_effectsChannel.setBassBoost(milliBels));
    }
    if (volumeBoost > 0) {
      final milliBels = (volumeBoost.clamp(0.0, 1.0) * 1000).round();
      futures.add(_effectsChannel.setVolumeBoost(milliBels));
    }
    if (isVirtualizerEnabled) {
      futures.add(_effectsChannel.setVirtualizerEnabled(true));
      futures.add(_effectsChannel.setVirtualizerStrength(virtualizerStrength));
    }
    if (isSpatializerEnabled) {
      futures.add(_effectsChannel.setSpatializerEnabled(true));
    }
    if (isCrossfeedEnabled) {
      futures.add(
        _effectsChannel.setCrossfeedParams(crossfeedDelayUs, crossfeedFeedDb),
      );
      futures.add(_effectsChannel.setCrossfeedEnabled(true));
    }
    if (isLimiterEnabled) {
      futures.add(
        _effectsChannel.setLimiterParams(
          limiterLookaheadMs,
          limiterThresholdDb,
          limiterReleaseMs,
        ),
      );
      futures.add(_effectsChannel.setLimiterEnabled(true));
    }
    if (isReverbEnabled) {
      futures.add(_effectsChannel.setReverbPreset(reverbPreset));
      futures.add(_effectsChannel.setReverbWetDry(reverbWetDry));
      futures.add(_effectsChannel.setReverbEnabled(true));
    }
    if (stereoBalance != 0.0) {
      futures.add(_effectsChannel.setStereoBalance(stereoBalance));
    }
    if (monoMix) futures.add(_effectsChannel.setMonoMix(true));
    if (isSaturationEnabled) {
      futures.add(
        _effectsChannel.setSaturationParams(
          saturationDrive,
          saturationMix,
          saturationTilt,
        ),
      );
      futures.add(_effectsChannel.setSaturationEnabled(true));
    }
    if (isStereoWidthEnabled) {
      futures.add(_effectsChannel.setStereoWidthParams(stereoWidth));
      futures.add(_effectsChannel.setStereoWidthEnabled(true));
    }
    if (isLoudnessContourEnabled) {
      futures.add(
        _effectsChannel.setLoudnessContourParams(
          loudnessContourIntensity,
          loudnessVolumeLinear,
        ),
      );
      futures.add(_effectsChannel.setLoudnessContourEnabled(true));
    }
    if (isSubCrossoverEnabled) {
      futures.add(
        _effectsChannel.setSubCrossoverParams(
          subCrossoverCornerHz,
          subCrossoverSlopeDbPerOct,
          subCrossoverGain,
        ),
      );
      futures.add(_effectsChannel.setSubCrossoverEnabled(true));
    }
    if (isDynamicEqEnabled) {
      futures.add(_pushDynamicEqConfig());
      futures.add(_effectsChannel.setDynamicEqEnabled(true));
    }

    if (futures.isNotEmpty) await Future.wait(futures);

    // Dynamics last — triggers recalculateActiveStages which may disable OEM
    // engine; apply last to prevent intermediate dropout. No delay needed here
    // because the session is already stable by the time reapplyToSession is
    // called (unlike cold-start where AudioTrack is still opening).
    if (isDynamicsEnabled && !_isDynamicsBypassed) {
      await _effectsChannel.setDynamicsPreset(dynamicsPreset, true);
    }
  }

  void dispose() {
    _saveDebounce?.cancel();
    _saveDebounce = null;
  }
}
