// lib/features/player/cubit/controllers/player_dsp_controller.dart
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:mutex/mutex.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/audio_feature_info.dart';
import '../../../../core/constants/prefs_keys.dart';
import '../../../../core/services/device_profile_service.dart';
import '../../../../core/services/hires_audio_service.dart';
import '../../../../core/services/room_correction_service.dart';
import '../../../../core/services/smart_audio_service.dart';
import '../../../../core/utils/error_logger.dart';
import '../../../../core/utils/safe_file_path.dart';
import '../../../../data/audio/audio_handler.dart';
import '../../../../data/audio/comparison_slot.dart';
import '../../../../data/audio/dsp_param_ranges.dart';
import '../../../../data/audio/gain_staging_budget.dart';
import '../../../../data/audio/headphone_profiles_repository.dart';
import '../../../../data/audio/ir_file_parser.dart';
import '../../../../data/db/app_database.dart';
import '../../../../domain/models/audio_effects_config.dart';
import '../../../../domain/models/audio_output_info.dart';
import '../../../../domain/models/eq_preset.dart';
import '../../../../domain/models/headphone_profile.dart';
import '../../../../domain/models/reverb_preset.dart';
import '../../../../domain/services/headphone_device_matcher.dart';
import '../../../../domain/services/settings_profiles_service.dart';
import '../../../../domain/services/smart_audio_plan.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../player_constants.dart';
import '../player_state.dart';

part 'player_dsp_effects.dart';
part 'player_dsp_profiles.dart';
part 'player_dsp_comparison.dart';
part 'player_dsp_follow_rate.dart';

/// Orchestrates all audio DSP effects, equalizer presets, and bit-perfect conflict gating.
class PlayerDspController {
  /// Maximum allowed size for custom impulse response WAV files (25 MB) (E3).
  static const int maxIrFileSizeBytes = 25 * 1024 * 1024;

  final PulsrAudioHandler _audioHandler;
  final SettingsCubit? _settingsCubit;
  final SettingsProfilesService? _settingsProfilesService;
  final DeviceProfileService? _deviceProfileService;
  final HiResAudioService? _hiResAudioService;
  final SmartAudioService? _smartAudioService;
  final HeadphoneProfilesRepository _headphoneProfilesRepo;
  final PlayerState Function() _getState;
  final void Function(PlayerState state) _emit;
  final void Function() _syncAudioEffects;
  final bool Function() _isClosed;

  StreamSubscription<AudioOutputInfo>? _deviceSub;
  DspSlice? _dspSnapshot;
  EqPreset? globalEqBackup;
  HeadphoneProfile? globalHeadphoneProfileBackup;
  bool perSongOverrideActive = false;
  String? _lastAutoAppliedDeviceKey;
  bool _smartAutoBitPerfectApplied = false;
  DateTime _lastUserInteraction = DateTime.fromMillisecondsSinceEpoch(0);

  void markUserInteracting() {
    _lastUserInteraction = DateTime.now();
  }

  bool get isUserInteracting =>
      DateTime.now().difference(_lastUserInteraction).inMilliseconds < 1500;

  PlayerDspController({
    required PulsrAudioHandler audioHandler,
    required SettingsCubit? settingsCubit,
    SettingsProfilesService? settingsProfilesService,
    DeviceProfileService? deviceProfileService,
    HiResAudioService? hiResAudioService,
    SmartAudioService? smartAudioService,
    HeadphoneProfilesRepository? headphoneProfilesRepo,
    required PlayerState Function() getState,
    required void Function(PlayerState state) emit,
    required void Function() syncAudioEffects,
    required bool Function() isClosed,
  })  : _audioHandler = audioHandler,
        _settingsCubit = settingsCubit,
        _settingsProfilesService = settingsProfilesService,
        _deviceProfileService = deviceProfileService,
        _hiResAudioService = hiResAudioService,
        _smartAudioService = smartAudioService,
        _headphoneProfilesRepo =
            headphoneProfilesRepo ?? HeadphoneProfilesRepository(),
        _getState = getState,
        _emit = emit,
        _syncAudioEffects = syncAudioEffects,
        _isClosed = isClosed {
    _startDeviceProfileWatcher();
  }

  void _startDeviceProfileWatcher() {
    final service = _deviceProfileService;
    final hiRes = _hiResAudioService;
    if (service == null || hiRes == null) return;
    _deviceSub = hiRes.outputDeviceStream.listen((device) {
      onOutputDeviceChanged(device);
    });
  }

  void dispose() {
    _abRevertTimer?.cancel();
    _abRevertTimer = null;
    _deviceSub?.cancel();
    _deviceSub = null;
  }

  final Mutex _followSampleRateMutex = Mutex();
  int? _lastFollowedSampleRate;
  int? _lastFollowedBitDepth;
  String? _lastFollowedRoute;

  String? dspBlockedReason() {
    final s = _settingsCubit?.state;
    if (s == null) return null;
    return AudioConflicts.dspBlockedByBitPerfect(
      bitPerfectOutput: s.bitPerfectOutput,
      bypassDspOnBitPerfect: s.bypassDspOnBitPerfect,
      device: s.currentOutputDevice,
      aaudioEnabled: s.aaudioOutputEnabled,
    );
  }

  bool guardDsp(String feature, {bool showError = true}) {
    final reason = dspBlockedReason();
    if (reason != null) {
      if (showError) {
        final state = _getState();
        _emit(state.copyWith(
          playback: state.playback.copyWith(
            errorMessage: '$feature blocked: $reason',
          ),
        ));
      }
      return false;
    }
    return true;
  }

  /// Declarative helper consolidating repetitive DSP effect setters, guarding,
  /// state emission, and audio handler sync.
  ///
  /// Unified error-reconciliation policy (shared by [applyPreset],
  /// [applyHeadphoneProfile], [setBandGain] and [resetToFlat]): on a native
  /// failure the DSP slice is rolled back to the pre-attempt snapshot
  /// ([previousDsp]) and the error is surfaced. We intentionally do NOT call
  /// [_syncAudioEffects] on failure — the snapshot is the authoritative
  /// known-good state, and re-reading the engine mid-failure only risks
  /// emitting a half-applied slice.
  static DspSlice mergeDspRollback(DspSlice current, DspSlice previous, DspSlice attempted) {
    return current.copyWith(
      isEqEnabled: attempted.isEqEnabled != previous.isEqEnabled ? previous.isEqEnabled : current.isEqEnabled,
      eqPreset: attempted.eqPreset != previous.eqPreset ? previous.eqPreset : current.eqPreset,
      selectedHeadphoneProfile: attempted.selectedHeadphoneProfile != previous.selectedHeadphoneProfile ? previous.selectedHeadphoneProfile : current.selectedHeadphoneProfile,
      preampDb: attempted.preampDb != previous.preampDb ? previous.preampDb : current.preampDb,
      isSpatializerEnabled: attempted.isSpatializerEnabled != previous.isSpatializerEnabled ? previous.isSpatializerEnabled : current.isSpatializerEnabled,
      isVirtualizerEnabled: attempted.isVirtualizerEnabled != previous.isVirtualizerEnabled ? previous.isVirtualizerEnabled : current.isVirtualizerEnabled,
      virtualizerStrength: attempted.virtualizerStrength != previous.virtualizerStrength ? previous.virtualizerStrength : current.virtualizerStrength,
      isDynamicsEnabled: attempted.isDynamicsEnabled != previous.isDynamicsEnabled ? previous.isDynamicsEnabled : current.isDynamicsEnabled,
      dynamicsPreset: attempted.dynamicsPreset != previous.dynamicsPreset ? previous.dynamicsPreset : current.dynamicsPreset,
      isCrossfeedEnabled: attempted.isCrossfeedEnabled != previous.isCrossfeedEnabled ? previous.isCrossfeedEnabled : current.isCrossfeedEnabled,
      crossfeedDelayUs: attempted.crossfeedDelayUs != previous.crossfeedDelayUs ? previous.crossfeedDelayUs : current.crossfeedDelayUs,
      crossfeedFeedDb: attempted.crossfeedFeedDb != previous.crossfeedFeedDb ? previous.crossfeedFeedDb : current.crossfeedFeedDb,
      crossfeedMode: attempted.crossfeedMode != previous.crossfeedMode ? previous.crossfeedMode : current.crossfeedMode,
      isLimiterEnabled: attempted.isLimiterEnabled != previous.isLimiterEnabled ? previous.isLimiterEnabled : current.isLimiterEnabled,
      limiterThresholdDb: attempted.limiterThresholdDb != previous.limiterThresholdDb ? previous.limiterThresholdDb : current.limiterThresholdDb,
      limiterReleaseMs: attempted.limiterReleaseMs != previous.limiterReleaseMs ? previous.limiterReleaseMs : current.limiterReleaseMs,
      isReverbEnabled: attempted.isReverbEnabled != previous.isReverbEnabled ? previous.isReverbEnabled : current.isReverbEnabled,
      reverbPreset: attempted.reverbPreset != previous.reverbPreset ? previous.reverbPreset : current.reverbPreset,
      reverbWetDry: attempted.reverbWetDry != previous.reverbWetDry ? previous.reverbWetDry : current.reverbWetDry,
      isSaturationEnabled: attempted.isSaturationEnabled != previous.isSaturationEnabled ? previous.isSaturationEnabled : current.isSaturationEnabled,
      saturationDrive: attempted.saturationDrive != previous.saturationDrive ? previous.saturationDrive : current.saturationDrive,
      saturationMix: attempted.saturationMix != previous.saturationMix ? previous.saturationMix : current.saturationMix,
      saturationTilt: attempted.saturationTilt != previous.saturationTilt ? previous.saturationTilt : current.saturationTilt,
      saturationMultiband: attempted.saturationMultiband != previous.saturationMultiband ? previous.saturationMultiband : current.saturationMultiband,
      isStereoWidthEnabled: attempted.isStereoWidthEnabled != previous.isStereoWidthEnabled ? previous.isStereoWidthEnabled : current.isStereoWidthEnabled,
      stereoWidth: attempted.stereoWidth != previous.stereoWidth ? previous.stereoWidth : current.stereoWidth,
      stereoWidthMultiband: attempted.stereoWidthMultiband != previous.stereoWidthMultiband ? previous.stereoWidthMultiband : current.stereoWidthMultiband,
      stereoWidthLow: attempted.stereoWidthLow != previous.stereoWidthLow ? previous.stereoWidthLow : current.stereoWidthLow,
      stereoWidthMid: attempted.stereoWidthMid != previous.stereoWidthMid ? previous.stereoWidthMid : current.stereoWidthMid,
      stereoWidthHigh: attempted.stereoWidthHigh != previous.stereoWidthHigh ? previous.stereoWidthHigh : current.stereoWidthHigh,
      stereoWidthLowCrossoverHz: attempted.stereoWidthLowCrossoverHz != previous.stereoWidthLowCrossoverHz ? previous.stereoWidthLowCrossoverHz : current.stereoWidthLowCrossoverHz,
      stereoWidthHighCrossoverHz: attempted.stereoWidthHighCrossoverHz != previous.stereoWidthHighCrossoverHz ? previous.stereoWidthHighCrossoverHz : current.stereoWidthHighCrossoverHz,
      isLoudnessContourEnabled: attempted.isLoudnessContourEnabled != previous.isLoudnessContourEnabled ? previous.isLoudnessContourEnabled : current.isLoudnessContourEnabled,
      loudnessContourIntensity: attempted.loudnessContourIntensity != previous.loudnessContourIntensity ? previous.loudnessContourIntensity : current.loudnessContourIntensity,
      isSubCrossoverEnabled: attempted.isSubCrossoverEnabled != previous.isSubCrossoverEnabled ? previous.isSubCrossoverEnabled : current.isSubCrossoverEnabled,
      subCrossoverCornerHz: attempted.subCrossoverCornerHz != previous.subCrossoverCornerHz ? previous.subCrossoverCornerHz : current.subCrossoverCornerHz,
      subCrossoverSlopeDbPerOct: attempted.subCrossoverSlopeDbPerOct != previous.subCrossoverSlopeDbPerOct ? previous.subCrossoverSlopeDbPerOct : current.subCrossoverSlopeDbPerOct,
      subCrossoverGain: attempted.subCrossoverGain != previous.subCrossoverGain ? previous.subCrossoverGain : current.subCrossoverGain,
      subCrossoverBassMono: attempted.subCrossoverBassMono != previous.subCrossoverBassMono ? previous.subCrossoverBassMono : current.subCrossoverBassMono,
      subCrossoverAntiPop: attempted.subCrossoverAntiPop != previous.subCrossoverAntiPop ? previous.subCrossoverAntiPop : current.subCrossoverAntiPop,
      isDynamicEqEnabled: attempted.isDynamicEqEnabled != previous.isDynamicEqEnabled ? previous.isDynamicEqEnabled : current.isDynamicEqEnabled,
      dynamicEqBands: attempted.dynamicEqBands != previous.dynamicEqBands ? previous.dynamicEqBands : current.dynamicEqBands,
      isViperDdcEnabled: attempted.isViperDdcEnabled != previous.isViperDdcEnabled ? previous.isViperDdcEnabled : current.isViperDdcEnabled,
      viperDdcProfileName: attempted.viperDdcProfileName != previous.viperDdcProfileName ? previous.viperDdcProfileName : current.viperDdcProfileName,
      isArbitraryEqEnabled: attempted.isArbitraryEqEnabled != previous.isArbitraryEqEnabled ? previous.isArbitraryEqEnabled : current.isArbitraryEqEnabled,
      arbitraryEqString: attempted.arbitraryEqString != previous.arbitraryEqString ? previous.arbitraryEqString : current.arbitraryEqString,
      isLiveProgEnabled: attempted.isLiveProgEnabled != previous.isLiveProgEnabled ? previous.isLiveProgEnabled : current.isLiveProgEnabled,
      liveProgCode: attempted.liveProgCode != previous.liveProgCode ? previous.liveProgCode : current.liveProgCode,
      isDynamicBassEnabled: attempted.isDynamicBassEnabled != previous.isDynamicBassEnabled ? previous.isDynamicBassEnabled : current.isDynamicBassEnabled,
      dynamicBassStrength: attempted.dynamicBassStrength != previous.dynamicBassStrength ? previous.dynamicBassStrength : current.dynamicBassStrength,
      dynamicBassPreset: attempted.dynamicBassPreset != previous.dynamicBassPreset ? previous.dynamicBassPreset : current.dynamicBassPreset,
      volumeBoost: attempted.volumeBoost != previous.volumeBoost ? previous.volumeBoost : current.volumeBoost,
      stereoBalance: attempted.stereoBalance != previous.stereoBalance ? previous.stereoBalance : current.stereoBalance,
      monoMix: attempted.monoMix != previous.monoMix ? previous.monoMix : current.monoMix,
      isSincResamplerEnabled: attempted.isSincResamplerEnabled != previous.isSincResamplerEnabled ? previous.isSincResamplerEnabled : current.isSincResamplerEnabled,
      isDitherEnabled: attempted.isDitherEnabled != previous.isDitherEnabled ? previous.isDitherEnabled : current.isDitherEnabled,
      ditherTargetBitDepth: attempted.ditherTargetBitDepth != previous.ditherTargetBitDepth ? previous.ditherTargetBitDepth : current.ditherTargetBitDepth,
    );
  }

  Future<bool> applyDspEffect({
    required String featureName,
    bool requiresGuard = true,
    bool guardCondition = true,
    bool showErrorOnGuard = true,
    required DspSlice Function(DspSlice current) updateDsp,
    required Future<void> Function() applyAudioHandler,
    String? failureMessage,
  }) async {
    markUserInteracting();
    if (requiresGuard &&
        guardCondition &&
        !guardDsp(featureName, showError: showErrorOnGuard)) {
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
        unawaited(rebalanceVolumeBoostIfNeeded());
      }
      return true;
    } catch (e, st) {
      ErrorLogger.log('Failed to set $featureName',
          error: e, stackTrace: st, category: 'PlayerDspController');
      final s = _getState();
      final rolledBackDsp = mergeDspRollback(s.dsp, previousDsp, attemptedDsp);
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

  // Equalizer methods
  Future<bool> setEqualizerEnabled(bool enabled) => applyDspEffect(
        featureName: 'Equalizer',
        guardCondition: enabled,
        updateDsp: (dsp) => dsp.copyWith(isEqEnabled: enabled),
        applyAudioHandler: () => _audioHandler.setEqualizerEnabled(enabled),
      );

  Future<bool> applyPreset(EqPreset preset,
      {bool isPerSongRestore = false}) async {
    markUserInteracting();
    if (!guardDsp('Equalizer Preset')) return false;
    if (perSongOverrideActive && !isPerSongRestore) {
      globalEqBackup = preset;
      globalHeadphoneProfileBackup = null;
    }
    final state = _getState();
    final previousDsp = state.dsp;
    _emit(state.copyWith(
      dsp: state.dsp.copyWith(
        isEqEnabled: true,
        eqPreset: preset,
        selectedHeadphoneProfile: null,
      ),
      playback: state.playback.copyWith(errorMessage: null),
    ));
    try {
      await _audioHandler.setEqualizerEnabled(true);
      await _audioHandler.applyPreset(preset);
      return true;
    } catch (e, st) {
      ErrorLogger.log('Failed to apply preset',
          error: e, stackTrace: st, category: 'PlayerDspController');
      final s = _getState();
      _emit(s.copyWith(
          dsp: previousDsp,
          playback:
              s.playback.copyWith(errorMessage: 'Failed to apply preset: $e')));
      return false;
    }
  }

  Future<bool> resetEqualizer() => applyPreset(EqPreset.defaultPresets.first);

  /// The engine-canonical EQ preamp (dB), read through the handler boundary
  /// (which returns the equalizer manager's value) — the single source of truth,
  /// kept in sync with native on every setPreamp, restore, snapshot recall and
  /// session reattach. Exposed so the cubit's reconciliation and the UI read ONE
  /// value instead of drifting.
  double get preampDb => _audioHandler.preampDb;

  /// Routes preamp through the shared guard/emit/rollback helper so it obeys
  /// the bit-perfect gate, marks user interaction and surfaces native failures
  /// like every other DSP setter (previously it bypassed all of this and let
  /// native exceptions escape into UI callers). Clamped defensively to the
  /// central ±15 dB contract ([DspParamRanges.preampDb]) and mirrored into
  /// PlayerState.dsp.preampDb so the reconciliation path and UI never drift from
  /// the engine (PlayerCubit._syncAudioEffects reads it back from the handler).
  Future<bool> setPreamp(double preampDb) {
    final clamped = DspParamRanges.preampDb.clampRaw(preampDb);
    return applyDspEffect(
      featureName: 'Preamp',
      updateDsp: (dsp) => dsp.copyWith(preampDb: clamped),
      applyAudioHandler: () => _audioHandler.setPreamp(clamped),
    );
  }

  Future<bool> applyHeadphoneProfile(HeadphoneProfile? profile,
      {bool isPerSongRestore = false, bool showErrorOnGuard = true}) async {
    markUserInteracting();
    if (profile != null && !guardDsp('AutoEQ', showError: showErrorOnGuard)) {
      return false;
    }
    final state = _getState();
    final previousDsp = state.dsp;
    if (profile != null) {
      if (perSongOverrideActive && !isPerSongRestore) {
        globalEqBackup = state.eqPreset.copyWith(
          name: profile.name,
          gains: profile.gains,
          bassBoost: profile.bassBoost,
        );
        globalHeadphoneProfileBackup = profile;
      }
      _emit(state.copyWith(
        dsp: state.dsp.copyWith(
          isEqEnabled: true,
          selectedHeadphoneProfile: profile,
          eqPreset: state.eqPreset.copyWith(
            name: profile.name,
            gains: profile.gains,
            bassBoost: profile.bassBoost,
          ),
        ),
        playback: state.playback.copyWith(errorMessage: null),
      ));
      try {
        await _audioHandler.setEqualizerEnabled(true);
        await _audioHandler.applyHeadphoneProfile(profile);
        return true;
      } catch (e, st) {
        ErrorLogger.log('Failed to apply AutoEQ profile',
            error: e, stackTrace: st, category: 'PlayerDspController');
        final s = _getState();
        _emit(s.copyWith(
          dsp: previousDsp,
          playback: s.playback.copyWith(
            errorMessage: 'Failed to apply AutoEQ profile: $e',
          ),
        ));
        return false;
      }
    } else {
      _emit(state.copyWith(
        dsp: state.dsp.copyWith(selectedHeadphoneProfile: null),
      ));
      try {
        await _audioHandler.applyHeadphoneProfile(null);
        return true;
      } catch (e, st) {
        ErrorLogger.log('Failed to reset headphone profile',
            error: e, stackTrace: st, category: 'PlayerDspController');
        final s = _getState();
        _emit(s.copyWith(
          dsp: previousDsp,
          playback: s.playback.copyWith(
            errorMessage: 'Failed to reset headphone profile: $e',
          ),
        ));
        return false;
      }
    }
  }

  Future<bool> resetHeadphoneProfile() => applyHeadphoneProfile(null);

  Future<void> setBandGain(int bandIndex, double gain) async {
    markUserInteracting();
    if (!guardDsp('Band Gain', showError: false)) return;
    final clamped = gain.clamp(-15.0, 15.0);
    final state = _getState();
    final currentGains = List<double>.from(state.eqPreset.gains);
    if (bandIndex < 0 || bandIndex >= currentGains.length) return;
    final previousDsp = state.dsp;
    currentGains[bandIndex] = clamped;
    _emit(state.copyWith(
      dsp: state.dsp.copyWith(
        eqPreset: state.eqPreset.copyWith(
          name: 'Custom',
          gains: currentGains,
        ),
        selectedHeadphoneProfile: null,
      ),
    ));
    try {
      await _audioHandler.setBandGain(bandIndex, clamped);
    } catch (e, st) {
      ErrorLogger.log('Failed to set band gain',
          error: e, stackTrace: st, category: 'PlayerDspController');
      final s = _getState();
      _emit(s.copyWith(
          dsp: previousDsp,
          playback: s.playback
              .copyWith(errorMessage: 'Failed to set band gain: $e')));
    }
  }

  Future<void> resetToFlat() async {
    markUserInteracting();
    final state = _getState();
    final previousDsp = state.dsp;
    _emit(state.copyWith(
      dsp: state.dsp.copyWith(
        eqPreset: EqPreset.defaultPresets.first,
        selectedHeadphoneProfile: null,
      ),
    ));
    try {
      await _audioHandler.resetToFlat();
    } catch (e, st) {
      ErrorLogger.log('Failed to reset equalizer',
          error: e, stackTrace: st, category: 'PlayerDspController');
      final s = _getState();
      _emit(s.copyWith(
        dsp: previousDsp,
        playback:
            s.playback.copyWith(errorMessage: 'Failed to reset equalizer: $e'),
      ));
    }
  }

  Timer? _abRevertTimer;
}
