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
import '../../../../data/audio/output_format_negotiation.dart';
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
import 'dsp_effect_applier.dart';

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

  late final DspEffectApplier _effectApplier = DspEffectApplier(
    getState: _getState,
    emit: _emit,
    markUserInteracting: markUserInteracting,
    guardDsp: guardDsp,
    rebalanceVolumeBoost: () => rebalanceVolumeBoostIfNeeded(),
  );

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

  /// Rate-specific reason (speed/pitch) so the player can refuse resampling on
  /// the bit-perfect bypass with a truthful, actionable message instead of the
  /// generic "this DSP would alter the bitstream" text.
  String? playbackRateBlockedReason() {
    final s = _settingsCubit?.state;
    if (s == null) return null;
    return AudioConflicts.speedBlockedByBitPerfect(
      bitPerfectOutput: s.bitPerfectOutput,
      bypassDspOnBitPerfect: s.bypassDspOnBitPerfect,
      device: s.currentOutputDevice,
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
  static DspSlice mergeDspRollback(
          DspSlice current, DspSlice previous, DspSlice attempted) =>
      DspRollbackPolicy.merge(current, previous, attempted);

  Future<bool> applyDspEffect({
    required String featureName,
    bool requiresGuard = true,
    bool guardCondition = true,
    bool showErrorOnGuard = true,
    required DspSlice Function(DspSlice current) updateDsp,
    required Future<void> Function() applyAudioHandler,
    String? failureMessage,
  }) =>
      _effectApplier.apply(
        featureName: featureName,
        requiresGuard: requiresGuard,
        guardCondition: guardCondition,
        showErrorOnGuard: showErrorOnGuard,
        updateDsp: updateDsp,
        applyAudioHandler: applyAudioHandler,
        failureMessage: failureMessage,
      );

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
