import 'dart:async';

import '../../../../core/utils/error_logger.dart';
import '../player_state.dart';

/// Reconciles a failed DSP attempt against its pre-attempt snapshot, restoring
/// only the fields the attempt actually changed.
class DspRollbackPolicy {
  const DspRollbackPolicy._();

  static DspSlice merge(
      DspSlice current, DspSlice previous, DspSlice attempted) {
    return current.copyWith(
      isEqEnabled: attempted.isEqEnabled != previous.isEqEnabled
          ? previous.isEqEnabled
          : current.isEqEnabled,
      eqPreset: attempted.eqPreset != previous.eqPreset
          ? previous.eqPreset
          : current.eqPreset,
      selectedHeadphoneProfile: attempted.selectedHeadphoneProfile !=
              previous.selectedHeadphoneProfile
          ? previous.selectedHeadphoneProfile
          : current.selectedHeadphoneProfile,
      preampDb: attempted.preampDb != previous.preampDb
          ? previous.preampDb
          : current.preampDb,
      isSpatializerEnabled:
          attempted.isSpatializerEnabled != previous.isSpatializerEnabled
              ? previous.isSpatializerEnabled
              : current.isSpatializerEnabled,
      isVirtualizerEnabled:
          attempted.isVirtualizerEnabled != previous.isVirtualizerEnabled
              ? previous.isVirtualizerEnabled
              : current.isVirtualizerEnabled,
      virtualizerStrength:
          attempted.virtualizerStrength != previous.virtualizerStrength
              ? previous.virtualizerStrength
              : current.virtualizerStrength,
      isDynamicsEnabled:
          attempted.isDynamicsEnabled != previous.isDynamicsEnabled
              ? previous.isDynamicsEnabled
              : current.isDynamicsEnabled,
      dynamicsPreset: attempted.dynamicsPreset != previous.dynamicsPreset
          ? previous.dynamicsPreset
          : current.dynamicsPreset,
      isCrossfeedEnabled:
          attempted.isCrossfeedEnabled != previous.isCrossfeedEnabled
              ? previous.isCrossfeedEnabled
              : current.isCrossfeedEnabled,
      crossfeedDelayUs: attempted.crossfeedDelayUs != previous.crossfeedDelayUs
          ? previous.crossfeedDelayUs
          : current.crossfeedDelayUs,
      crossfeedFeedDb: attempted.crossfeedFeedDb != previous.crossfeedFeedDb
          ? previous.crossfeedFeedDb
          : current.crossfeedFeedDb,
      crossfeedMode: attempted.crossfeedMode != previous.crossfeedMode
          ? previous.crossfeedMode
          : current.crossfeedMode,
      isLimiterEnabled: attempted.isLimiterEnabled != previous.isLimiterEnabled
          ? previous.isLimiterEnabled
          : current.isLimiterEnabled,
      limiterThresholdDb:
          attempted.limiterThresholdDb != previous.limiterThresholdDb
              ? previous.limiterThresholdDb
              : current.limiterThresholdDb,
      limiterReleaseMs: attempted.limiterReleaseMs != previous.limiterReleaseMs
          ? previous.limiterReleaseMs
          : current.limiterReleaseMs,
      isReverbEnabled: attempted.isReverbEnabled != previous.isReverbEnabled
          ? previous.isReverbEnabled
          : current.isReverbEnabled,
      reverbPreset: attempted.reverbPreset != previous.reverbPreset
          ? previous.reverbPreset
          : current.reverbPreset,
      reverbWetDry: attempted.reverbWetDry != previous.reverbWetDry
          ? previous.reverbWetDry
          : current.reverbWetDry,
      isSaturationEnabled:
          attempted.isSaturationEnabled != previous.isSaturationEnabled
              ? previous.isSaturationEnabled
              : current.isSaturationEnabled,
      saturationDrive: attempted.saturationDrive != previous.saturationDrive
          ? previous.saturationDrive
          : current.saturationDrive,
      saturationMix: attempted.saturationMix != previous.saturationMix
          ? previous.saturationMix
          : current.saturationMix,
      saturationTilt: attempted.saturationTilt != previous.saturationTilt
          ? previous.saturationTilt
          : current.saturationTilt,
      saturationMultiband:
          attempted.saturationMultiband != previous.saturationMultiband
              ? previous.saturationMultiband
              : current.saturationMultiband,
      isStereoWidthEnabled:
          attempted.isStereoWidthEnabled != previous.isStereoWidthEnabled
              ? previous.isStereoWidthEnabled
              : current.isStereoWidthEnabled,
      stereoWidth: attempted.stereoWidth != previous.stereoWidth
          ? previous.stereoWidth
          : current.stereoWidth,
      stereoWidthMultiband:
          attempted.stereoWidthMultiband != previous.stereoWidthMultiband
              ? previous.stereoWidthMultiband
              : current.stereoWidthMultiband,
      stereoWidthLow: attempted.stereoWidthLow != previous.stereoWidthLow
          ? previous.stereoWidthLow
          : current.stereoWidthLow,
      stereoWidthMid: attempted.stereoWidthMid != previous.stereoWidthMid
          ? previous.stereoWidthMid
          : current.stereoWidthMid,
      stereoWidthHigh: attempted.stereoWidthHigh != previous.stereoWidthHigh
          ? previous.stereoWidthHigh
          : current.stereoWidthHigh,
      stereoWidthLowCrossoverHz: attempted.stereoWidthLowCrossoverHz !=
              previous.stereoWidthLowCrossoverHz
          ? previous.stereoWidthLowCrossoverHz
          : current.stereoWidthLowCrossoverHz,
      stereoWidthHighCrossoverHz: attempted.stereoWidthHighCrossoverHz !=
              previous.stereoWidthHighCrossoverHz
          ? previous.stereoWidthHighCrossoverHz
          : current.stereoWidthHighCrossoverHz,
      isLoudnessContourEnabled: attempted.isLoudnessContourEnabled !=
              previous.isLoudnessContourEnabled
          ? previous.isLoudnessContourEnabled
          : current.isLoudnessContourEnabled,
      loudnessContourIntensity: attempted.loudnessContourIntensity !=
              previous.loudnessContourIntensity
          ? previous.loudnessContourIntensity
          : current.loudnessContourIntensity,
      isSubCrossoverEnabled:
          attempted.isSubCrossoverEnabled != previous.isSubCrossoverEnabled
              ? previous.isSubCrossoverEnabled
              : current.isSubCrossoverEnabled,
      subCrossoverCornerHz:
          attempted.subCrossoverCornerHz != previous.subCrossoverCornerHz
              ? previous.subCrossoverCornerHz
              : current.subCrossoverCornerHz,
      subCrossoverSlopeDbPerOct: attempted.subCrossoverSlopeDbPerOct !=
              previous.subCrossoverSlopeDbPerOct
          ? previous.subCrossoverSlopeDbPerOct
          : current.subCrossoverSlopeDbPerOct,
      subCrossoverGain: attempted.subCrossoverGain != previous.subCrossoverGain
          ? previous.subCrossoverGain
          : current.subCrossoverGain,
      subCrossoverBassMono:
          attempted.subCrossoverBassMono != previous.subCrossoverBassMono
              ? previous.subCrossoverBassMono
              : current.subCrossoverBassMono,
      subCrossoverAntiPop:
          attempted.subCrossoverAntiPop != previous.subCrossoverAntiPop
              ? previous.subCrossoverAntiPop
              : current.subCrossoverAntiPop,
      isDynamicEqEnabled:
          attempted.isDynamicEqEnabled != previous.isDynamicEqEnabled
              ? previous.isDynamicEqEnabled
              : current.isDynamicEqEnabled,
      dynamicEqBands: attempted.dynamicEqBands != previous.dynamicEqBands
          ? previous.dynamicEqBands
          : current.dynamicEqBands,
      isViperDdcEnabled:
          attempted.isViperDdcEnabled != previous.isViperDdcEnabled
              ? previous.isViperDdcEnabled
              : current.isViperDdcEnabled,
      viperDdcProfileName:
          attempted.viperDdcProfileName != previous.viperDdcProfileName
              ? previous.viperDdcProfileName
              : current.viperDdcProfileName,
      isArbitraryEqEnabled:
          attempted.isArbitraryEqEnabled != previous.isArbitraryEqEnabled
              ? previous.isArbitraryEqEnabled
              : current.isArbitraryEqEnabled,
      arbitraryEqString:
          attempted.arbitraryEqString != previous.arbitraryEqString
              ? previous.arbitraryEqString
              : current.arbitraryEqString,
      isLiveProgEnabled:
          attempted.isLiveProgEnabled != previous.isLiveProgEnabled
              ? previous.isLiveProgEnabled
              : current.isLiveProgEnabled,
      liveProgCode: attempted.liveProgCode != previous.liveProgCode
          ? previous.liveProgCode
          : current.liveProgCode,
      isDynamicBassEnabled:
          attempted.isDynamicBassEnabled != previous.isDynamicBassEnabled
              ? previous.isDynamicBassEnabled
              : current.isDynamicBassEnabled,
      dynamicBassStrength:
          attempted.dynamicBassStrength != previous.dynamicBassStrength
              ? previous.dynamicBassStrength
              : current.dynamicBassStrength,
      dynamicBassPreset:
          attempted.dynamicBassPreset != previous.dynamicBassPreset
              ? previous.dynamicBassPreset
              : current.dynamicBassPreset,
      volumeBoost: attempted.volumeBoost != previous.volumeBoost
          ? previous.volumeBoost
          : current.volumeBoost,
      stereoBalance: attempted.stereoBalance != previous.stereoBalance
          ? previous.stereoBalance
          : current.stereoBalance,
      monoMix: attempted.monoMix != previous.monoMix
          ? previous.monoMix
          : current.monoMix,
      isSincResamplerEnabled:
          attempted.isSincResamplerEnabled != previous.isSincResamplerEnabled
              ? previous.isSincResamplerEnabled
              : current.isSincResamplerEnabled,
      isDitherEnabled: attempted.isDitherEnabled != previous.isDitherEnabled
          ? previous.isDitherEnabled
          : current.isDitherEnabled,
      ditherTargetBitDepth:
          attempted.ditherTargetBitDepth != previous.ditherTargetBitDepth
              ? previous.ditherTargetBitDepth
              : current.ditherTargetBitDepth,
    );
  }
}

/// Applies guarded DSP mutations with unified state emission and rollback.
class DspEffectApplier {
  final PlayerState Function() _getState;
  final void Function(PlayerState state) _emit;
  final void Function() _markUserInteracting;
  final bool Function(String feature, {bool showError}) _guardDsp;
  final Future<void> Function() _rebalanceVolumeBoost;

  DspEffectApplier({
    required PlayerState Function() getState,
    required void Function(PlayerState state) emit,
    required void Function() markUserInteracting,
    required bool Function(String feature, {bool showError}) guardDsp,
    required Future<void> Function() rebalanceVolumeBoost,
  })  : _getState = getState,
        _emit = emit,
        _markUserInteracting = markUserInteracting,
        _guardDsp = guardDsp,
        _rebalanceVolumeBoost = rebalanceVolumeBoost;

  Future<bool> apply({
    required String featureName,
    bool requiresGuard = true,
    bool guardCondition = true,
    bool showErrorOnGuard = true,
    required DspSlice Function(DspSlice current) updateDsp,
    required Future<void> Function() applyAudioHandler,
    String? failureMessage,
  }) async {
    _markUserInteracting();
    if (requiresGuard &&
        guardCondition &&
        !_guardDsp(featureName, showError: showErrorOnGuard)) {
      return false;
    }
    final state = _getState();
    final previousDsp = state.dsp;
    final attemptedDsp = updateDsp(previousDsp);
    _emit(state.copyWith(
      dsp: attemptedDsp,
      playback: state.playback.copyWith(errorMessage: null),
    ));
    try {
      await applyAudioHandler();
      if (featureName != 'Volume Boost') {
        unawaited(_rebalanceVolumeBoost());
      }
      return true;
    } catch (e, st) {
      ErrorLogger.log('Failed to set $featureName',
          error: e, stackTrace: st, category: 'PlayerDspController');
      final s = _getState();
      final rolledBackDsp =
          DspRollbackPolicy.merge(s.dsp, previousDsp, attemptedDsp);
      _emit(s.copyWith(
        dsp: rolledBackDsp,
        playback: s.playback.copyWith(
          errorMessage: failureMessage ??
              'Failed to set ${featureName.toLowerCase()}: $e',
        ),
      ));
      return false;
    }
  }
}
