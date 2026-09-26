// lib/features/player/cubit/controllers/player_dsp_controller.dart
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/audio_feature_info.dart';
import '../../../../core/constants/prefs_keys.dart';
import '../../../../core/services/device_profile_service.dart';
import '../../../../core/services/hires_audio_service.dart';
import '../../../../core/services/room_correction_service.dart';
import '../../../../core/services/settings_profiles_service.dart';
import '../../../../core/services/smart_audio_service.dart';
import '../../../../core/utils/error_logger.dart';
import '../../../../core/utils/safe_file_path.dart';
import '../../../../data/audio/audio_handler.dart';
import '../../../../data/audio/comparison_slot.dart';
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
  PlayerState? _dspSnapshot;
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
        _headphoneProfilesRepo = headphoneProfilesRepo ?? HeadphoneProfilesRepository(),
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

  int _followSampleRateGen = 0;
  int? _lastFollowedSampleRate;

  Future<void> maybeFollowTrackSampleRate(SongsTableData song) async {
    final service = _hiResAudioService;
    final settings = _settingsCubit?.state;
    if (service == null || settings == null) return;
    final gen = ++_followSampleRateGen;
    final rate = HiResAudioService.followTrackRateToApply(
      trackSampleRate: song.sampleRate,
      lastRequestedSampleRate: _lastFollowedSampleRate,
      isBluetooth: settings.currentOutputDevice?.isBluetooth == true,
      followTrackEnabled:
          settings.followTrackSampleRate || settings.strictBitPerfect,
    );
    if (rate == null) return;
    try {
      final depth = (song.bitDepth != null && song.bitDepth! > 0)
          ? song.bitDepth!
          : PlayerConstants.defaultBitDepth;
      await service.setTargetOutputFormat(sampleRate: rate, bitDepth: depth);
      if (_isClosed() || gen != _followSampleRateGen) return;
      _lastFollowedSampleRate = rate;
      await _settingsCubit?.refreshOutputDevice();
    } catch (e, st) {
      _lastFollowedSampleRate = null;
      ErrorLogger.log('Follow-track sample rate failed ($rate)',
          error: e, stackTrace: st, category: 'PlayerDspController');
    }
  }

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
  Future<void> applyDspEffect({
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
      return;
    }
    final state = _getState();
    final previousDsp = state.dsp;
    _emit(state.copyWith(
      dsp: updateDsp(previousDsp),
      playback: state.playback.copyWith(errorMessage: null),
    ));
    try {
      await applyAudioHandler();
    } catch (e) {
      _syncAudioEffects();
      final s = _getState();
      _emit(s.copyWith(
        dsp: previousDsp,
        playback: s.playback.copyWith(
          errorMessage: failureMessage ??
              'Failed to set ${featureName.toLowerCase()}: $e',
        ),
      ));
    }
  }

  // Equalizer methods
  Future<void> setEqualizerEnabled(bool enabled) => applyDspEffect(
        featureName: 'Equalizer',
        guardCondition: enabled,
        updateDsp: (dsp) => dsp.copyWith(isEqEnabled: enabled),
        applyAudioHandler: () => _audioHandler.setEqualizerEnabled(enabled),
      );

  Future<void> applyPreset(EqPreset preset,
      {bool isPerSongRestore = false}) async {
    if (!guardDsp('Equalizer Preset')) return;
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
    } catch (e) {
      final s = _getState();
      _emit(s.copyWith(dsp: previousDsp, playback: s.playback.copyWith(errorMessage: 'Failed to apply preset: $e')));
    }
  }

  Future<void> resetEqualizer() => applyPreset(EqPreset.defaultPresets.first);

  Future<void> applyHeadphoneProfile(HeadphoneProfile? profile,
      {bool isPerSongRestore = false}) async {
    if (profile != null && !guardDsp('AutoEQ', showError: true)) return;
    final state = _getState();
    final previousDsp = state.dsp;
    if (profile != null) {
      if (perSongOverrideActive && !isPerSongRestore) {
        globalEqBackup = EqPreset(
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
          eqPreset: EqPreset(
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
      } catch (e) {
        final s = _getState();
        _emit(s.copyWith(
          dsp: previousDsp,
          playback: s.playback.copyWith(
            errorMessage: 'Failed to apply AutoEQ profile: $e',
          ),
        ));
      }
    } else {
      _emit(state.copyWith(
        dsp: state.dsp.copyWith(selectedHeadphoneProfile: null),
      ));
      try {
        await _audioHandler.applyHeadphoneProfile(null);
      } catch (e) {
        final s = _getState();
        _emit(s.copyWith(
          dsp: previousDsp,
          playback: s.playback.copyWith(
            errorMessage: 'Failed to reset headphone profile: $e',
          ),
        ));
      }
    }
  }

  Future<void> resetHeadphoneProfile() => applyHeadphoneProfile(null);

  Future<void> setBandGain(int bandIndex, double gain) async {
    if (!guardDsp('Band Gain', showError: false)) return;
    final clamped = gain.clamp(-15.0, 15.0);
    final state = _getState();
    final previousDsp = state.dsp;
    final currentGains = List<double>.from(state.eqPreset.gains);
    if (bandIndex >= 0 && bandIndex < currentGains.length) {
      currentGains[bandIndex] = clamped;
      _emit(state.copyWith(
        dsp: state.dsp.copyWith(
          eqPreset: EqPreset(
            name: 'Custom',
            gains: currentGains,
            bassBoost: state.eqPreset.bassBoost,
          ),
          selectedHeadphoneProfile: null,
        ),
      ));
    }
    try {
      await _audioHandler.setBandGain(bandIndex, clamped);
    } catch (e) {
      _syncAudioEffects();
      final s = _getState();
      _emit(s.copyWith(
          dsp: previousDsp,
          playback:
              s.playback.copyWith(errorMessage: 'Failed to set band gain: $e')));
    }
  }

  Future<void> resetToFlat() async {
    final state = _getState();
    _emit(state.copyWith(
      dsp: state.dsp.copyWith(
        eqPreset: EqPreset.defaultPresets.first,
        selectedHeadphoneProfile: null,
      ),
    ));
    try {
      await _audioHandler.resetToFlat();
    } catch (e) {
      _syncAudioEffects();
    }
  }

  Timer? _abRevertTimer;

  Future<void> startAbComparison() async {
    _abRevertTimer?.cancel();
    _abRevertTimer = Timer(const Duration(seconds: 10), () {
      endAbComparison();
    });
    return _audioHandler.startAbComparison();
  }

  Future<void> endAbComparison() {
    _abRevertTimer?.cancel();
    _abRevertTimer = null;
    return _audioHandler.endAbComparison();
  }

  Future<void> setBandMode(int count) async {
    if (count == 10 || count == 32) {
      await _audioHandler.set32BandMode(count == 32);
    } else if (count == 64) {
      await _audioHandler.equalizerManager.setBandMode(64);
    } else {
      return;
    }
    final state = _getState();
    _emit(state.copyWith(dsp: state.dsp.copyWith(eqPreset: _audioHandler.currentPreset)));
  }

  Future<void> switchComparisonSlot(ComparisonSlot slot) async {
    await _audioHandler.switchComparisonSlot(slot);
    final state = _getState();
    _emit(state.copyWith(dsp: state.dsp.copyWith(eqPreset: _audioHandler.currentPreset)));
  }

  String exportPresetToJson() => _audioHandler.exportPresetToJson();

  Future<bool> importPresetFromJson(String jsonStr) async {
    final ok = await _audioHandler.importPresetFromJson(jsonStr);
    if (ok) {
      final state = _getState();
      _emit(state.copyWith(
          dsp: state.dsp.copyWith(eqPreset: _audioHandler.currentPreset)));
    }
    return ok;
  }

  List<double> mergeRoomCorrectionWithHeadphoneCurve(List<double> roomGains, {double maxGainDb = 15.0}) =>
      RoomCorrectionService.mergeWithHeadphoneCurve(
        roomGains,
        _getState().selectedHeadphoneProfile?.gains ?? const <double>[],
        maxGainDb: maxGainDb,
      );

  List<double> exportCorrectionImpulseResponse(
    List<double> gains, {
    List<double>? centers,
    int sampleRate = RoomCorrectionService.captureSampleRate,
    int taps = 127,
  }) => RoomCorrectionService.exportCorrectionImpulseResponse(
        gains,
        centers: centers ?? EqPreset.centerFrequencies,
        sampleRate: sampleRate,
        taps: taps,
      );
}
