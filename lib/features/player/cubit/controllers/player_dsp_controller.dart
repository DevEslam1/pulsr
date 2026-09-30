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
  SettingsCubit? _settingsCubit;
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

  /// Monotonic interaction clock. A [Stopwatch] is immune to wall-clock jumps
  /// and avoids allocating a new [DateTime] on every [isUserInteracting] read.
  final Stopwatch _interactionStopwatch = Stopwatch();

  static const int _interactionWindowMs = 1500;

  void markUserInteracting() {
    _interactionStopwatch
      ..reset()
      ..start();
  }

  bool get isUserInteracting =>
      _interactionStopwatch.isRunning &&
      _interactionStopwatch.elapsedMilliseconds < _interactionWindowMs;

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
    _abComparisonActive = false;
    _deviceSub?.cancel();
    _deviceSub = null;
  }

  final Mutex _followSampleRateMutex = Mutex();
  int? _lastFollowedSampleRate;

  Future<void> maybeFollowTrackSampleRate(SongsTableData song) async {
    final service = _hiResAudioService;
    final settings = _settingsCubit?.state;
    if (service == null || settings == null) return;
    await _followSampleRateMutex.protect(() async {
      if (_isClosed()) return;
      final currentSong = _getState().currentSong;
      if (currentSong != null && currentSong.id != song.id) return;

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
        if (_isClosed()) return;
        _lastFollowedSampleRate = rate;
        await _settingsCubit?.refreshOutputDevice();
      } catch (e, st) {
        _lastFollowedSampleRate = null;
        ErrorLogger.log('Follow-track sample rate failed ($rate)',
            error: e, stackTrace: st, category: 'PlayerDspController');
      }
    });
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
    markUserInteracting();
    if (!guardDsp('Equalizer Preset')) return;
    globalEqBackup = preset;
    if (perSongOverrideActive && !isPerSongRestore) {
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
      _syncAudioEffects();
      final s = _getState();
      _emit(s.copyWith(dsp: previousDsp, playback: s.playback.copyWith(errorMessage: 'Failed to apply preset: $e')));
    }
  }

  Future<void> resetEqualizer() => applyPreset(EqPreset.defaultPresets.first);

  Future<void> applyHeadphoneProfile(HeadphoneProfile? profile,
      {bool isPerSongRestore = false}) async {
    markUserInteracting();
    if (profile != null && !guardDsp('AutoEQ', showError: true)) return;
    final state = _getState();
    final previousDsp = state.dsp;
    if (profile != null) {
      globalEqBackup = state.eqPreset;
      if (perSongOverrideActive && !isPerSongRestore) {
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
        await _audioHandler.applyHeadphoneProfile(profile);
        await _audioHandler.setEqualizerEnabled(true);
        final latest = _getState();
        _emit(latest.copyWith(
          dsp: latest.dsp.copyWith(
            isEqEnabled: true,
            selectedHeadphoneProfile: profile,
            eqPreset: EqPreset(
              name: profile.name,
              gains: profile.gains,
              bassBoost: profile.bassBoost,
            ),
          ),
          playback: latest.playback.copyWith(errorMessage: null),
        ));
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
      final currentProfile = state.dsp.selectedHeadphoneProfile;
      final bool eqModified = currentProfile != null &&
          (state.dsp.eqPreset.name != currentProfile.name ||
              state.dsp.eqPreset.gains != currentProfile.gains);
      final restorePreset = eqModified
          ? state.dsp.eqPreset
          : (globalEqBackup ?? EqPreset.defaultPresets.first);
      globalEqBackup = null;
      globalHeadphoneProfileBackup = null;
      _emit(state.copyWith(
        dsp: state.dsp.copyWith(
          selectedHeadphoneProfile: null,
          eqPreset: restorePreset,
        ),
        playback: state.playback.copyWith(errorMessage: null),
      ));
      try {
        await _audioHandler.applyHeadphoneProfile(null);
        await _audioHandler.applyPreset(restorePreset);
        final latest = _getState();
        _emit(latest.copyWith(
          dsp: latest.dsp.copyWith(
            selectedHeadphoneProfile: null,
            eqPreset: restorePreset,
          ),
          playback: latest.playback.copyWith(errorMessage: null),
        ));
      } catch (e) {
        _syncAudioEffects();
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
    markUserInteracting();
    if (!guardDsp('Band Gain', showError: false)) return;
    final state = _getState();
    final currentGains = List<double>.from(state.eqPreset.gains);
    if (bandIndex < 0 || bandIndex >= currentGains.length) return;
    final clamped = gain.clamp(-15.0, 15.0);
    final previousDsp = state.dsp;
    currentGains[bandIndex] = clamped;
    final newCustomPreset = EqPreset(
      name: 'Custom',
      gains: currentGains,
      bassBoost: state.eqPreset.bassBoost,
    );
    globalEqBackup = newCustomPreset;
    globalHeadphoneProfileBackup = null;
    _emit(state.copyWith(
      dsp: state.dsp.copyWith(
        eqPreset: newCustomPreset,
        selectedHeadphoneProfile: null,
      ),
    ));
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

  /// H7: Guards against a concurrent user "stop" and the 10 s auto-revert timer
  /// both invoking [endAbComparison] and double-calling the audio handler.
  bool _abComparisonActive = false;

  void attachSettingsCubit(SettingsCubit settingsCubit) => _settingsCubit = settingsCubit;
}
