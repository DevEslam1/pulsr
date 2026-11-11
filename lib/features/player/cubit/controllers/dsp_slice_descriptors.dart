// lib/features/player/cubit/controllers/dsp_slice_descriptors.dart
import 'package:flutter/foundation.dart';
import '../../../../data/audio/audio_handler.dart';
import '../../../../domain/models/audio_effects_config.dart';
import '../../../../domain/models/eq_preset.dart';
import '../../../../domain/models/headphone_profile.dart';
import '../../../../domain/models/quran_mode_profile.dart';
import '../player_state.dart';

/// Abstract descriptor for a field on [DspSlice].
abstract class DspFieldDescriptor {
  String get name;
  bool valuesEqual(DspSlice a, DspSlice b);
  DspSlice rollbackIfChanged(
      DspSlice current, DspSlice previous, DspSlice attempted);
  DspSlice syncFromHandler(DspSlice target, PulsrAudioHandler handler);
}

/// Generic, table-driven implementation of a single [DspSlice] field descriptor.
///
/// Provides a single source of truth across:
/// 1. [DspRollbackPolicy.merge] (restoring previous values for attempted changes).
/// 2. AudioHandler effects re-syncing (`_syncAudioEffects`).
/// 3. Equalizer sheet rebuild gating (`dspSheetRebuildGate`).
class DspField<T> implements DspFieldDescriptor {
  @override
  final String name;
  final T Function(DspSlice slice) getSlice;
  final T Function(PulsrAudioHandler handler)? getHandler;
  final DspSlice Function(DspSlice slice, T value) withValue;
  final bool Function(T a, T b)? areEqual;

  const DspField({
    required this.name,
    required this.getSlice,
    this.getHandler,
    required this.withValue,
    this.areEqual,
  });

  bool _eq(T a, T b) {
    if (areEqual != null) return areEqual!(a, b);
    if (a is List && b is List) {
      return listEquals(a, b);
    }
    return a == b;
  }

  @override
  bool valuesEqual(DspSlice a, DspSlice b) {
    return _eq(getSlice(a), getSlice(b));
  }

  @override
  DspSlice rollbackIfChanged(
      DspSlice current, DspSlice previous, DspSlice attempted) {
    final prevVal = getSlice(previous);
    final attVal = getSlice(attempted);
    if (!_eq(prevVal, attVal)) {
      return withValue(current, prevVal);
    }
    return current;
  }

  @override
  DspSlice syncFromHandler(DspSlice target, PulsrAudioHandler handler) {
    if (getHandler == null) return target;
    return withValue(target, getHandler!(handler));
  }
}

bool _eqPresetEquals(EqPreset a, EqPreset b) {
  if (identical(a, b)) return true;
  return a.name == b.name &&
      a.bassBoost == b.bassBoost &&
      listEquals(a.gains, b.gains) &&
      listEquals(a.customFrequencies, b.customFrequencies) &&
      listEquals(a.qFactors, b.qFactors) &&
      mapEquals(a.bandsMap, b.bandsMap);
}

/// Table of all DSP field descriptors.
final List<DspFieldDescriptor> dspSliceFields = <DspFieldDescriptor>[
  DspField<bool>(
    name: 'isEqEnabled',
    getSlice: (s) => s.isEqEnabled,
    getHandler: (h) => h.isEqualizerEnabled,
    withValue: (s, v) => s.copyWith(isEqEnabled: v),
  ),
  DspField<EqPreset>(
    name: 'eqPreset',
    getSlice: (s) => s.eqPreset,
    getHandler: (h) => h.currentPreset,
    withValue: (s, v) => s.copyWith(eqPreset: v),
    areEqual: _eqPresetEquals,
  ),
  DspField<bool>(
    name: 'isVirtualizerEnabled',
    getSlice: (s) => s.isVirtualizerEnabled,
    getHandler: (h) => h.isVirtualizerEnabled,
    withValue: (s, v) => s.copyWith(isVirtualizerEnabled: v),
  ),
  DspField<double>(
    name: 'virtualizerStrength',
    getSlice: (s) => s.virtualizerStrength,
    getHandler: (h) => h.virtualizerStrength,
    withValue: (s, v) => s.copyWith(virtualizerStrength: v),
  ),
  DspField<bool>(
    name: 'isVirtualizerSupported',
    getSlice: (s) => s.isVirtualizerSupported,
    getHandler: (h) => h.isVirtualizerSupported,
    withValue: (s, v) => s.copyWith(isVirtualizerSupported: v),
  ),
  DspField<bool>(
    name: 'isDynamicsEnabled',
    getSlice: (s) => s.isDynamicsEnabled,
    getHandler: (h) => h.isDynamicsEffectivelyEnabled,
    withValue: (s, v) => s.copyWith(isDynamicsEnabled: v),
  ),
  DspField<bool>(
    name: 'isDynamicsSupported',
    getSlice: (s) => s.isDynamicsSupported,
    getHandler: (h) => h.isDynamicsSupported,
    withValue: (s, v) => s.copyWith(isDynamicsSupported: v),
  ),
  DspField<DynamicsPreset>(
    name: 'dynamicsPreset',
    getSlice: (s) => s.dynamicsPreset,
    getHandler: (h) => h.dynamicsPreset,
    withValue: (s, v) => s.copyWith(dynamicsPreset: v),
  ),
  DspField<HeadphoneProfile?>(
    name: 'selectedHeadphoneProfile',
    getSlice: (s) => s.selectedHeadphoneProfile,
    getHandler: (h) => h.selectedHeadphoneProfile,
    withValue: (s, v) => s.copyWith(selectedHeadphoneProfile: v),
  ),
  DspField<bool>(
    name: 'isSpatializerSupported',
    getSlice: (s) => s.isSpatializerSupported,
    getHandler: (h) => h.isSpatializerSupported,
    withValue: (s, v) => s.copyWith(isSpatializerSupported: v),
  ),
  DspField<bool>(
    name: 'isSpatializerEnabled',
    getSlice: (s) => s.isSpatializerEnabled,
    getHandler: (h) => h.isSpatializerEnabled,
    withValue: (s, v) => s.copyWith(isSpatializerEnabled: v),
  ),
  DspField<double>(
    name: 'volumeBoost',
    getSlice: (s) => s.volumeBoost,
    getHandler: (h) => h.volumeBoost,
    withValue: (s, v) => s.copyWith(volumeBoost: v),
  ),
  DspField<double>(
    name: 'effectiveVolumeBoost',
    getSlice: (s) => s.effectiveVolumeBoost,
    withValue: (s, v) => s.copyWith(effectiveVolumeBoost: v),
  ),
  DspField<double>(
    name: 'effectiveBassBoost',
    getSlice: (s) => s.effectiveBassBoost,
    withValue: (s, v) => s.copyWith(effectiveBassBoost: v),
  ),
  DspField<double>(
    name: 'preampDb',
    getSlice: (s) => s.preampDb,
    getHandler: (h) => h.preampDb,
    withValue: (s, v) => s.copyWith(preampDb: v),
  ),
  DspField<bool>(
    name: 'isVolumeBoostSupported',
    getSlice: (s) => s.isVolumeBoostSupported,
    getHandler: (h) => h.isVolumeBoostSupported,
    withValue: (s, v) => s.copyWith(isVolumeBoostSupported: v),
  ),
  DspField<bool>(
    name: 'isBassBoostSupported',
    getSlice: (s) => s.isBassBoostSupported,
    getHandler: (h) => h.isBassBoostSupported,
    withValue: (s, v) => s.copyWith(isBassBoostSupported: v),
  ),
  DspField<bool>(
    name: 'isCrossfeedEnabled',
    getSlice: (s) => s.isCrossfeedEnabled,
    getHandler: (h) => h.crossfeedUserEnabled,
    withValue: (s, v) => s.copyWith(isCrossfeedEnabled: v),
  ),
  DspField<double>(
    name: 'crossfeedDelayUs',
    getSlice: (s) => s.crossfeedDelayUs,
    getHandler: (h) => h.crossfeedDelayUs,
    withValue: (s, v) => s.copyWith(crossfeedDelayUs: v),
  ),
  DspField<double>(
    name: 'crossfeedFeedDb',
    getSlice: (s) => s.crossfeedFeedDb,
    getHandler: (h) => h.crossfeedFeedDb,
    withValue: (s, v) => s.copyWith(crossfeedFeedDb: v),
  ),
  DspField<int>(
    name: 'crossfeedMode',
    getSlice: (s) => s.crossfeedMode,
    getHandler: (h) => h.crossfeedMode,
    withValue: (s, v) => s.copyWith(crossfeedMode: v),
  ),
  DspField<bool>(
    name: 'isLimiterEnabled',
    getSlice: (s) => s.isLimiterEnabled,
    getHandler: (h) => h.isLimiterEnabled,
    withValue: (s, v) => s.copyWith(isLimiterEnabled: v),
  ),
  DspField<double>(
    name: 'limiterThresholdDb',
    getSlice: (s) => s.limiterThresholdDb,
    getHandler: (h) => h.limiterThresholdDb,
    withValue: (s, v) => s.copyWith(limiterThresholdDb: v),
  ),
  DspField<double>(
    name: 'limiterReleaseMs',
    getSlice: (s) => s.limiterReleaseMs,
    getHandler: (h) => h.limiterReleaseMs,
    withValue: (s, v) => s.copyWith(limiterReleaseMs: v),
  ),
  DspField<double>(
    name: 'compressorRatio',
    getSlice: (s) => s.compressorRatio,
    withValue: (s, v) => s.copyWith(compressorRatio: v),
  ),
  DspField<double>(
    name: 'compressorAttackMs',
    getSlice: (s) => s.compressorAttackMs,
    withValue: (s, v) => s.copyWith(compressorAttackMs: v),
  ),
  DspField<double>(
    name: 'compressorMakeupGainDb',
    getSlice: (s) => s.compressorMakeupGainDb,
    withValue: (s, v) => s.copyWith(compressorMakeupGainDb: v),
  ),
  DspField<bool>(
    name: 'isReverbEnabled',
    getSlice: (s) => s.isReverbEnabled,
    getHandler: (h) => h.isReverbEnabled,
    withValue: (s, v) => s.copyWith(isReverbEnabled: v),
  ),
  DspField<int>(
    name: 'reverbPreset',
    getSlice: (s) => s.reverbPreset,
    getHandler: (h) => h.reverbPreset,
    withValue: (s, v) => s.copyWith(reverbPreset: v),
  ),
  DspField<double>(
    name: 'reverbWetDry',
    getSlice: (s) => s.reverbWetDry,
    getHandler: (h) => h.reverbWetDry,
    withValue: (s, v) => s.copyWith(reverbWetDry: v),
  ),
  DspField<double>(
    name: 'stereoBalance',
    getSlice: (s) => s.stereoBalance,
    getHandler: (h) => h.stereoBalance,
    withValue: (s, v) => s.copyWith(stereoBalance: v),
  ),
  DspField<bool>(
    name: 'monoMix',
    getSlice: (s) => s.monoMix,
    getHandler: (h) => h.monoMix,
    withValue: (s, v) => s.copyWith(monoMix: v),
  ),
  DspField<bool>(
    name: 'isSincResamplerEnabled',
    getSlice: (s) => s.isSincResamplerEnabled,
    getHandler: (h) => h.isSincResamplerEnabled,
    withValue: (s, v) => s.copyWith(isSincResamplerEnabled: v),
  ),
  DspField<bool>(
    name: 'isDitherEnabled',
    getSlice: (s) => s.isDitherEnabled,
    getHandler: (h) => h.isDitherEnabled,
    withValue: (s, v) => s.copyWith(isDitherEnabled: v),
  ),
  DspField<int>(
    name: 'ditherTargetBitDepth',
    getSlice: (s) => s.ditherTargetBitDepth,
    getHandler: (h) => h.ditherTargetBitDepth,
    withValue: (s, v) => s.copyWith(ditherTargetBitDepth: v),
  ),
  DspField<bool>(
    name: 'isSaturationEnabled',
    getSlice: (s) => s.isSaturationEnabled,
    getHandler: (h) => h.isSaturationEnabled,
    withValue: (s, v) => s.copyWith(isSaturationEnabled: v),
  ),
  DspField<double>(
    name: 'saturationDrive',
    getSlice: (s) => s.saturationDrive,
    getHandler: (h) => h.saturationDrive,
    withValue: (s, v) => s.copyWith(saturationDrive: v),
  ),
  DspField<double>(
    name: 'saturationMix',
    getSlice: (s) => s.saturationMix,
    getHandler: (h) => h.saturationMix,
    withValue: (s, v) => s.copyWith(saturationMix: v),
  ),
  DspField<double>(
    name: 'saturationTilt',
    getSlice: (s) => s.saturationTilt,
    getHandler: (h) => h.saturationTilt,
    withValue: (s, v) => s.copyWith(saturationTilt: v),
  ),
  DspField<bool>(
    name: 'saturationMultiband',
    getSlice: (s) => s.saturationMultiband,
    getHandler: (h) => h.saturationMultiband,
    withValue: (s, v) => s.copyWith(saturationMultiband: v),
  ),
  DspField<bool>(
    name: 'isStereoWidthEnabled',
    getSlice: (s) => s.isStereoWidthEnabled,
    getHandler: (h) => h.isStereoWidthEnabled,
    withValue: (s, v) => s.copyWith(isStereoWidthEnabled: v),
  ),
  DspField<double>(
    name: 'stereoWidth',
    getSlice: (s) => s.stereoWidth,
    getHandler: (h) => h.stereoWidth,
    withValue: (s, v) => s.copyWith(stereoWidth: v),
  ),
  DspField<bool>(
    name: 'stereoWidthMultiband',
    getSlice: (s) => s.stereoWidthMultiband,
    getHandler: (h) => h.stereoWidthMultiband,
    withValue: (s, v) => s.copyWith(stereoWidthMultiband: v),
  ),
  DspField<double>(
    name: 'stereoWidthLow',
    getSlice: (s) => s.stereoWidthLow,
    getHandler: (h) => h.stereoWidthLow,
    withValue: (s, v) => s.copyWith(stereoWidthLow: v),
  ),
  DspField<double>(
    name: 'stereoWidthMid',
    getSlice: (s) => s.stereoWidthMid,
    getHandler: (h) => h.stereoWidthMid,
    withValue: (s, v) => s.copyWith(stereoWidthMid: v),
  ),
  DspField<double>(
    name: 'stereoWidthHigh',
    getSlice: (s) => s.stereoWidthHigh,
    getHandler: (h) => h.stereoWidthHigh,
    withValue: (s, v) => s.copyWith(stereoWidthHigh: v),
  ),
  DspField<double>(
    name: 'stereoWidthLowCrossoverHz',
    getSlice: (s) => s.stereoWidthLowCrossoverHz,
    getHandler: (h) => h.stereoWidthLowCrossoverHz,
    withValue: (s, v) => s.copyWith(stereoWidthLowCrossoverHz: v),
  ),
  DspField<double>(
    name: 'stereoWidthHighCrossoverHz',
    getSlice: (s) => s.stereoWidthHighCrossoverHz,
    getHandler: (h) => h.stereoWidthHighCrossoverHz,
    withValue: (s, v) => s.copyWith(stereoWidthHighCrossoverHz: v),
  ),
  DspField<bool>(
    name: 'isLoudnessContourEnabled',
    getSlice: (s) => s.isLoudnessContourEnabled,
    getHandler: (h) => h.isLoudnessContourEnabled,
    withValue: (s, v) => s.copyWith(isLoudnessContourEnabled: v),
  ),
  DspField<double>(
    name: 'loudnessContourIntensity',
    getSlice: (s) => s.loudnessContourIntensity,
    getHandler: (h) => h.loudnessContourIntensity,
    withValue: (s, v) => s.copyWith(loudnessContourIntensity: v),
  ),
  DspField<bool>(
    name: 'isSubCrossoverEnabled',
    getSlice: (s) => s.isSubCrossoverEnabled,
    getHandler: (h) => h.isSubCrossoverEnabled,
    withValue: (s, v) => s.copyWith(isSubCrossoverEnabled: v),
  ),
  DspField<double>(
    name: 'subCrossoverCornerHz',
    getSlice: (s) => s.subCrossoverCornerHz,
    getHandler: (h) => h.subCrossoverCornerHz,
    withValue: (s, v) => s.copyWith(subCrossoverCornerHz: v),
  ),
  DspField<double>(
    name: 'subCrossoverSlopeDbPerOct',
    getSlice: (s) => s.subCrossoverSlopeDbPerOct,
    getHandler: (h) => h.subCrossoverSlopeDbPerOct,
    withValue: (s, v) => s.copyWith(subCrossoverSlopeDbPerOct: v),
  ),
  DspField<double>(
    name: 'subCrossoverGain',
    getSlice: (s) => s.subCrossoverGain,
    getHandler: (h) => h.subCrossoverGain,
    withValue: (s, v) => s.copyWith(subCrossoverGain: v),
  ),
  DspField<bool>(
    name: 'subCrossoverBassMono',
    getSlice: (s) => s.subCrossoverBassMono,
    getHandler: (h) => h.subCrossoverBassMono,
    withValue: (s, v) => s.copyWith(subCrossoverBassMono: v),
  ),
  DspField<bool>(
    name: 'subCrossoverAntiPop',
    getSlice: (s) => s.subCrossoverAntiPop,
    getHandler: (h) => h.subCrossoverAntiPop,
    withValue: (s, v) => s.copyWith(subCrossoverAntiPop: v),
  ),
  DspField<bool>(
    name: 'isMultibandCompressorEnabled',
    getSlice: (s) => s.isMultibandCompressorEnabled,
    getHandler: (h) => h.isMultibandCompressorEnabled,
    withValue: (s, v) => s.copyWith(isMultibandCompressorEnabled: v),
  ),
  DspField<double>(
    name: 'multibandCompressorF0',
    getSlice: (s) => s.multibandCompressorF0,
    getHandler: (h) => h.multibandCompressorF0,
    withValue: (s, v) => s.copyWith(multibandCompressorF0: v),
  ),
  DspField<double>(
    name: 'multibandCompressorF1',
    getSlice: (s) => s.multibandCompressorF1,
    getHandler: (h) => h.multibandCompressorF1,
    withValue: (s, v) => s.copyWith(multibandCompressorF1: v),
  ),
  DspField<double>(
    name: 'multibandCompressorF2',
    getSlice: (s) => s.multibandCompressorF2,
    getHandler: (h) => h.multibandCompressorF2,
    withValue: (s, v) => s.copyWith(multibandCompressorF2: v),
  ),
  DspField<List<MultibandCompressorBandConfig>>(
    name: 'multibandCompressorBands',
    getSlice: (s) => s.multibandCompressorBands,
    withValue: (s, v) => s.copyWith(multibandCompressorBands: v),
    areEqual: listEquals,
  ),
  DspField<bool>(
    name: 'isDynamicEqEnabled',
    getSlice: (s) => s.isDynamicEqEnabled,
    getHandler: (h) => h.isDynamicEqEnabled,
    withValue: (s, v) => s.copyWith(isDynamicEqEnabled: v),
  ),
  DspField<List<DynamicEqBandConfig>>(
    name: 'dynamicEqBands',
    getSlice: (s) => s.dynamicEqBands,
    getHandler: (h) => h.dynamicEqBands,
    withValue: (s, v) => s.copyWith(dynamicEqBands: v),
    areEqual: listEquals,
  ),
  DspField<bool>(
    name: 'isViperDdcEnabled',
    getSlice: (s) => s.isViperDdcEnabled,
    getHandler: (h) => h.isViperDdcEnabled,
    withValue: (s, v) => s.copyWith(isViperDdcEnabled: v),
  ),
  DspField<String>(
    name: 'viperDdcProfileName',
    getSlice: (s) => s.viperDdcProfileName,
    getHandler: (h) => h.viperDdcProfileName,
    withValue: (s, v) => s.copyWith(viperDdcProfileName: v),
  ),
  DspField<bool>(
    name: 'isArbitraryEqEnabled',
    getSlice: (s) => s.isArbitraryEqEnabled,
    getHandler: (h) => h.isArbitraryEqEnabled,
    withValue: (s, v) => s.copyWith(isArbitraryEqEnabled: v),
  ),
  DspField<bool>(
    name: 'arbitraryEqLinearPhase',
    getSlice: (s) => s.arbitraryEqLinearPhase,
    getHandler: (h) => h.arbitraryEqLinearPhase,
    withValue: (s, v) => s.copyWith(arbitraryEqLinearPhase: v),
  ),
  DspField<String>(
    name: 'arbitraryEqString',
    getSlice: (s) => s.arbitraryEqString,
    getHandler: (h) => h.arbitraryEqString,
    withValue: (s, v) => s.copyWith(arbitraryEqString: v),
  ),
  DspField<bool>(
    name: 'isLiveProgEnabled',
    getSlice: (s) => s.isLiveProgEnabled,
    getHandler: (h) => h.isLiveProgEnabled,
    withValue: (s, v) => s.copyWith(isLiveProgEnabled: v),
  ),
  DspField<String>(
    name: 'liveProgCode',
    getSlice: (s) => s.liveProgCode,
    getHandler: (h) => h.liveProgCode,
    withValue: (s, v) => s.copyWith(liveProgCode: v),
  ),
  DspField<String>(
    name: 'liveProgStatus',
    getSlice: (s) => s.liveProgStatus,
    withValue: (s, v) => s.copyWith(liveProgStatus: v),
  ),
  DspField<bool>(
    name: 'isDynamicBassEnabled',
    getSlice: (s) => s.isDynamicBassEnabled,
    getHandler: (h) => h.isDynamicBassEnabled,
    withValue: (s, v) => s.copyWith(isDynamicBassEnabled: v),
  ),
  DspField<double>(
    name: 'dynamicBassStrength',
    getSlice: (s) => s.dynamicBassStrength,
    getHandler: (h) => h.dynamicBassStrength,
    withValue: (s, v) => s.copyWith(dynamicBassStrength: v),
  ),
  DspField<int>(
    name: 'dynamicBassPreset',
    getSlice: (s) => s.dynamicBassPreset,
    getHandler: (h) => h.dynamicBassPreset,
    withValue: (s, v) => s.copyWith(dynamicBassPreset: v),
  ),
  DspField<bool>(
    name: 'hasOemAudio',
    getSlice: (s) => s.hasOemAudio,
    getHandler: (h) => h.hasOemAudio,
    withValue: (s, v) => s.copyWith(hasOemAudio: v),
  ),
  DspField<List<String>>(
    name: 'detectedOemEngines',
    getSlice: (s) => s.detectedOemEngines,
    getHandler: (h) => h.detectedOemEngines,
    withValue: (s, v) => s.copyWith(detectedOemEngines: v),
    areEqual: listEquals,
  ),
  DspField<bool>(
    name: 'isQuranModeEnabled',
    getSlice: (s) => s.isQuranModeEnabled,
    withValue: (s, v) => s.copyWith(isQuranModeEnabled: v),
  ),
  DspField<QuranReciterStyle>(
    name: 'quranReciterStyle',
    getSlice: (s) => s.quranReciterStyle,
    withValue: (s, v) => s.copyWith(quranReciterStyle: v),
  ),
];
