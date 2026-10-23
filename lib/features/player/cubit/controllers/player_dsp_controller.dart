// lib/features/player/cubit/controllers/player_dsp_controller.dart
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:mutex/mutex.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/audio_feature_info.dart';
import '../../../../core/constants/prefs_keys.dart';
import '../../../../data/services/device_profile_service.dart';
import '../../../../core/services/earbud_optimization_service.dart';
import '../../../../data/services/hires_audio_service.dart';
import '../../../../data/services/room_correction_service.dart';
import '../../../../core/services/smart_audio_service.dart';
import '../../../../core/utils/error_logger.dart';
import '../../../../core/utils/safe_file_path.dart';
import '../../../../data/audio/audio_handler.dart';
import '../../../../data/audio/bluetooth_quality_policy.dart';
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
import '../../../../data/services/settings_profiles_service.dart';
import '../../../../domain/services/smart_audio_plan.dart';
import '../../../../data/services/usb_exclusive_service.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../player_constants.dart';
import '../player_state.dart';
import 'dsp_effect_applier.dart';

part 'player_dsp_effects.dart';
part 'player_dsp_eq.dart';
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
  bool _multibandCompressorRestore = false;

  /// Pure, route-based DSP compensation (crossfeed gating + codec-aware music
  /// EQ/reverb) runs through [EarbudOptimizationService.detect], whose methods
  /// are side-effect-free. Constructed directly (same pattern as the
  /// UsbExclusiveService use in the follow-rate path) because the cubit does
  /// not inject it into this controller.
  final EarbudOptimizationService _earbudService = EarbudOptimizationService();

  /// Codec-aware music compensation tracking (fix #2). The compensation is a
  /// small, reversible overlay merged on top of the user's active EQ/reverb;
  /// these fields remember exactly what was folded in so a later route/track
  /// change can recover the true base (subtract-old / add-new) without ever
  /// double-applying or clobbering the user's own EQ edits.
  List<double>? _appliedMusicEqComp;
  bool _musicForcedEqEnabled = false;
  double _appliedMusicReverbScale = 1.0;
  EqPreset? globalEqBackup;
  HeadphoneProfile? globalHeadphoneProfileBackup;
  bool perSongOverrideActive = false;
  int _perSongEqApplyGen = 0;
  int _trackDspStateGen = 0;
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
  // Last codec rate requested by the Bluetooth Hi-Res alignment, so a track
  // that already matches the codec does not trigger a redundant switch.
  int? _lastFollowedBtCodecRate;

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

  /// The current output route, preferring the settings cubit's cached device
  /// (updated on every route change) and falling back to the Hi-Res service's
  /// last snapshot. Null when neither is available yet.
  AudioOutputInfo? currentOutputInfo() =>
      _settingsCubit?.state.currentOutputDevice ??
      _hiResAudioService?.currentOutputInfo;

  /// The engine's active output sample rate (Hz). Custom impulse responses must
  /// be resampled to this before native convolution. Falls back to the
  /// platform native rate, then 48 kHz, and is clamped to a sane range.
  int _engineActiveSampleRate() {
    final info = currentOutputInfo();
    int rate = info?.sampleRate ?? 0;
    if (rate <= 0) rate = info?.nativeSampleRate ?? 0;
    if (rate <= 0) rate = 48000;
    return rate.clamp(8000, IrFileParser.maxSampleRate);
  }

  /// Crossfeed (headphone imaging) only makes sense on headphone / earbud
  /// routes; on built-in speakers, car head units and HDMI it collapses the
  /// stereo image, so it must be bypassed there. Pure + static so it can be
  /// unit-tested directly (fix #1).
  ///
  /// device-validate: route classification relies on the platform-reported
  /// [AudioOutputInfo.activeDeviceType]; car head units reached over A2DP
  /// report as `bluetooth` and are treated as headphone-like here.
  static bool routeWantsCrossfeed(AudioOutputInfo? info) {
    if (info == null) {
      // Unknown route: honour the user's preference rather than silently
      // bypassing. The next concrete device event re-evaluates.
      return true;
    }
    // Explicit headphone/earbud-style transports always want crossfeed.
    if (info.isBluetooth || info.isLeAudio || info.isUsbDac) return true;
    final type = info.activeDeviceType.toLowerCase();
    const speakerLike = <String>[
      'builtin',
      'speaker',
      'hdmi',
      'car',
      'automotive',
      'bus',
      'aux',
      'line',
      'dock',
    ];
    if (speakerLike.any(type.contains)) return false;
    const headphoneLike = <String>[
      'head', // headphone / headset
      'wired',
      'usb',
      'blue',
      'ble',
      'hearing',
      'bt',
    ];
    if (headphoneLike.any(type.contains)) return true;
    // Unrecognised route: honour the preference (do not silently disable).
    return true;
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

  Timer? _abRevertTimer;
}
