import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/core/services/earbud_optimization_service.dart';
import 'package:pulsr/core/services/hires_audio_service.dart';
import 'package:pulsr/core/services/quran_mode_service.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/domain/models/eq_preset.dart';
import 'package:pulsr/domain/models/quran_mode_profile.dart';
import 'package:pulsr/features/player/cubit/controllers/player_controllers.dart';
import 'package:pulsr/features/player/cubit/managers/player_quran_manager.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/test_pulsr_audio_handler.dart';

class _FakeHiResAudioService extends HiResAudioService {
  final AudioOutputInfo _info;
  _FakeHiResAudioService(this._info);

  @override
  AudioOutputInfo? get currentOutputInfo => _info;

  @override
  Future<AudioOutputInfo> getAudioOutputInfo() async => _info;
}

/// Forces [detectEarbudCapabilities] onto its async path and lets a test hold
/// it open, so a state change can land while a Quran profile apply is awaiting.
class _GatedHiResAudioService extends HiResAudioService {
  final AudioOutputInfo _info;
  _GatedHiResAudioService(this._info);

  final List<Completer<void>> gates = [];

  @override
  AudioOutputInfo? get currentOutputInfo => null;

  @override
  Future<AudioOutputInfo> getAudioOutputInfo() async {
    final gate = Completer<void>();
    gates.add(gate);
    await gate.future;
    return _info;
  }
}

/// Records the preamp/reverb values the Quran profile actually pushes down to
/// the engine, and mirrors [preampDb] back so the cubit's reconciliation reads
/// the same value it just applied.
class _QuranAudioHandler extends TestPulsrAudioHandler {
  double _preampDb = 0.0;
  final List<double> preampValues = [];

  @override
  double get preampDb => _preampDb;

  @override
  Future<void> setPreamp(double value) async {
    _preampDb = value;
    preampValues.add(value);
  }

  double? lastReverbWetDry;
  bool? lastReverbEnabled;
  bool? lastSaturationEnabled;
  double? lastSaturationMix;
  bool rejectSaturation = false;
  bool rejectReverb = false;
  AudioServiceShuffleMode? lastShuffleMode;

  @override
  Future<void> setSaturation(bool enabled,
      {double? drive,
      double? mix,
      double? tilt,
      int? mode,
      bool? multiband}) async {
    if (rejectSaturation) throw StateError('Native saturation rejected');
    lastSaturationEnabled = enabled;
    lastSaturationMix = mix;
  }

  @override
  Future<void> setReverb(bool enabled, {int? preset, double? wetDry}) async {
    if (rejectReverb) throw StateError('Native reverb rejected');
    lastReverbEnabled = enabled;
    lastReverbWetDry = wetDry;
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    lastShuffleMode = shuffleMode;
  }
}

PlayerPlaybackOptionsController _controller({
  required _QuranAudioHandler handler,
  required PlayerState Function() getState,
  required void Function(PlayerState) emit,
  QuranModeService? service,
  EarbudOptimizationService? earbudOptimizationService,
  HiResAudioService? hiResAudioService,
}) {
  return PlayerPlaybackOptionsController(
    audioHandler: handler,
    earbudOptimizationService: earbudOptimizationService,
    hiResAudioService: hiResAudioService,
    getState: getState,
    emit: emit,
    isClosed: () => false,
    quranManager: PlayerQuranManager(service: service),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Quran Mode persistence', () {
    test('enabling persists enabled + style and a fresh controller restores it',
        () async {
      final service = QuranModeService();
      final handler = _QuranAudioHandler();
      var state = const PlayerState();
      final controller = _controller(
        handler: handler,
        getState: () => state,
        emit: (s) => state = s,
        service: service,
      );

      await controller.setQuranModeEnabled(true);
      expect(await service.isEnabled(), isTrue);
      expect(state.isQuranModeEnabled, isTrue);

      controller.setQuranReciterStyle(QuranReciterStyle.sleepMode);
      await pumpEventQueue();
      expect(await service.getStyle(), QuranReciterStyle.sleepMode);
      expect(state.quranReciterStyle, QuranReciterStyle.sleepMode);

      // A fresh controller/manager models the next launch: it must load the
      // persisted selection and re-apply the saved profile.
      final restoredHandler = _QuranAudioHandler();
      var restoredState = const PlayerState();
      final restored = _controller(
        handler: restoredHandler,
        getState: () => restoredState,
        emit: (s) => restoredState = s,
        service: QuranModeService(),
      );
      await restored.restoreQuranMode();

      expect(restoredState.isQuranModeEnabled, isTrue);
      expect(restoredState.quranReciterStyle, QuranReciterStyle.sleepMode);
      expect(
        restoredHandler.preampDb,
        QuranModeProfile.forStyle(QuranReciterStyle.sleepMode).preampDb,
      );
    });

    test('disabled mode restores nothing on next launch', () async {
      SharedPreferences.setMockInitialValues({
        'quran_mode_enabled': false,
        'quran_reciter_style': 'tarawih',
      });

      final handler = _QuranAudioHandler();
      var state = const PlayerState();
      final controller = _controller(
        handler: handler,
        getState: () => state,
        emit: (s) => state = s,
        service: QuranModeService(),
      );

      await controller.restoreQuranMode();

      expect(state.isQuranModeEnabled, isFalse);
      expect(handler.preampValues, isEmpty);
    });
  });

  group('Quran Mode regular profile actions', () {
    test('warmth activates a dry style, clamps, and zero disables processing',
        () async {
      final handler = _QuranAudioHandler();
      var state = const PlayerState();
      final controller = _controller(
          handler: handler, getState: () => state, emit: (s) => state = s);
      await controller.setQuranModeEnabled(true);
      expect(state.isSaturationEnabled, isFalse);
      await controller.setQuranWarmth(1.0);
      expect(state.isSaturationEnabled, isTrue);
      expect(state.saturationMix, 0.6);
      expect(handler.lastSaturationEnabled, isTrue);
      expect(handler.lastSaturationMix, 0.6);
      await controller.setQuranWarmth(0.0);
      expect(state.isSaturationEnabled, isFalse);
      expect(state.saturationMix, 0.0);
      expect(handler.lastSaturationEnabled, isFalse);
    });

    test('rejected warmth preserves the last accepted UI value', () async {
      final handler = _QuranAudioHandler();
      var state = const PlayerState();
      final controller = _controller(
          handler: handler, getState: () => state, emit: (s) => state = s);
      await controller.setQuranModeEnabled(true);
      await controller.setQuranWarmth(0.2);
      handler.rejectSaturation = true;
      await controller.setQuranWarmth(0.6);
      expect(state.saturationMix, 0.2);
      expect(state.isSaturationEnabled, isTrue);
      expect(state.errorMessage, contains('Failed to set Quran vocal warmth'));
    });

    test('warmth ignores edits when Quran mode is off and non-finite values',
        () async {
      final handler = _QuranAudioHandler();
      var state = const PlayerState();
      final controller = _controller(
          handler: handler, getState: () => state, emit: (s) => state = s);
      await controller.setQuranWarmth(0.4);
      expect(handler.lastSaturationMix, isNull);
      await controller.setQuranModeEnabled(true);
      final mix = state.saturationMix;
      await controller.setQuranWarmth(double.nan);
      expect(state.saturationMix, mix);
    });

    test('reset reapplies the Quran profile, not the pre-Quran snapshot',
        () async {
      final rock = EqPreset.defaultPresets.firstWhere((p) => p.name == 'Rock');
      final handler = _QuranAudioHandler();
      var state = PlayerState(dsp: DspSlice(eqPreset: rock));
      final controller = _controller(
        handler: handler,
        getState: () => state,
        emit: (s) => state = s,
        service: QuranModeService(),
      );

      await controller.setQuranModeEnabled(true);
      final quranPresetName = state.eqPreset.name;
      expect(quranPresetName, contains('Quran'));

      await controller.reapplyQuranProfile();

      // Pre-fix this restored the captured "Rock" snapshot while still enabled.
      expect(state.isQuranModeEnabled, isTrue);
      expect(state.eqPreset.name, quranPresetName);
      expect(state.eqPreset.name, isNot(rock.name));
    });

    test('a style change during an in-flight apply is not reverted', () async {
      final output = AudioOutputInfo(
        deviceName: 'Wired',
        isUsbDac: false,
        sampleRate: 44100,
        bitDepth: 16,
        isBitPerfectActive: false,
      );
      final hiRes = _GatedHiResAudioService(output);
      final handler = _QuranAudioHandler();
      var state = const PlayerState();
      final controller = _controller(
        handler: handler,
        getState: () => state,
        emit: (s) => state = s,
        service: QuranModeService(),
        earbudOptimizationService: EarbudOptimizationService(),
        hiResAudioService: hiRes,
      );

      // The profile apply blocks while probing output capabilities.
      final enable = controller.setQuranModeEnabled(true);
      await pumpEventQueue();
      expect(hiRes.gates, isNotEmpty);

      // A style change lands while that apply is still awaiting.
      controller.setQuranReciterStyle(QuranReciterStyle.studyMode);
      await pumpEventQueue();
      expect(state.quranReciterStyle, QuranReciterStyle.studyMode);

      // Release every blocked probe so all applies complete.
      for (final gate in hiRes.gates) {
        if (!gate.isCompleted) gate.complete();
      }
      await enable;
      await pumpEventQueue();

      // The earlier apply must not have clobbered the style back to Murattal.
      expect(state.quranReciterStyle, QuranReciterStyle.studyMode);
      expect(state.isQuranModeEnabled, isTrue);
    });

    test('setQuranAmbience clamps reverb to 0..0.6', () async {
      final handler = _QuranAudioHandler();
      var state = const PlayerState();
      final controller = _controller(
        handler: handler,
        getState: () => state,
        emit: (s) => state = s,
        service: QuranModeService(),
      );

      await controller.setQuranModeEnabled(true);
      await controller.setQuranAmbience(1.5);

      expect(state.reverbWetDry, 0.6);
      expect(handler.lastReverbWetDry, 0.6);
      expect(state.isReverbEnabled, isTrue);
    });

    test('setQuranAmbience zero disables reverb and ignores non-finite/off edits',
        () async {
      final handler = _QuranAudioHandler();
      var state = const PlayerState();
      final controller = _controller(
        handler: handler,
        getState: () => state,
        emit: (s) => state = s,
        service: QuranModeService(),
      );

      // Ignored when Quran mode is off
      await controller.setQuranAmbience(0.4);
      expect(handler.lastReverbWetDry, isNull);

      await controller.setQuranModeEnabled(true);
      await controller.setQuranAmbience(0.3);
      expect(state.isReverbEnabled, isTrue);
      expect(state.reverbWetDry, 0.3);

      // Non-finite ignored
      await controller.setQuranAmbience(double.nan);
      expect(state.reverbWetDry, 0.3);

      // Zero disables reverb
      await controller.setQuranAmbience(0.0);
      expect(state.isReverbEnabled, isFalse);
      expect(state.reverbWetDry, 0.0);
      expect(handler.lastReverbEnabled, isFalse);
    });

    test('rejected ambience preserves last accepted value and emits error',
        () async {
      final handler = _QuranAudioHandler();
      var state = const PlayerState();
      final controller = _controller(
        handler: handler,
        getState: () => state,
        emit: (s) => state = s,
        service: QuranModeService(),
      );

      await controller.setQuranModeEnabled(true);
      await controller.setQuranAmbience(0.2);
      expect(state.reverbWetDry, 0.2);

      handler.rejectReverb = true;
      await controller.setQuranAmbience(0.5);
      expect(state.reverbWetDry, 0.2);
      expect(state.errorMessage, contains('Failed to set Quran ambience'));
    });

    test('enabling Quran Mode disables shuffle and disabling restores it',
        () async {
      final handler = _QuranAudioHandler();
      var state = const PlayerState(
        playback: PlaybackSlice(isShuffle: true, playbackSpeed: 1.0),
      );
      final controller = _controller(
        handler: handler,
        getState: () => state,
        emit: (s) => state = s,
        service: QuranModeService(),
      );

      // Turn on Quran mode: shuffle should be disabled to keep recitation order
      await controller.setQuranModeEnabled(true);
      expect(state.isQuranModeEnabled, isTrue);
      expect(state.isShuffle, isFalse);
      expect(handler.lastShuffleMode, AudioServiceShuffleMode.none);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(PrefsKeys.playbackShuffle), isFalse);

      // Turn off Quran mode: pre-Quran shuffle should be restored
      await controller.setQuranModeEnabled(false);
      expect(state.isQuranModeEnabled, isFalse);
      expect(state.isShuffle, isTrue);
      expect(handler.lastShuffleMode, AudioServiceShuffleMode.all);
      expect(prefs.getBool(PrefsKeys.playbackShuffle), isTrue);
    });

    test('disabling Quran Mode restores playbackSpeed to SharedPreferences',
        () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(PrefsKeys.playbackSpeed, 1.0);

      final handler = _QuranAudioHandler();
      var state = const PlayerState(
        playback: PlaybackSlice(playbackSpeed: 1.0),
      );
      final controller = _controller(
        handler: handler,
        getState: () => state,
        emit: (s) => state = s,
        service: QuranModeService(),
      );

      // Enable Quran Mode and switch to memorization (0.75x)
      await controller.setQuranModeEnabled(true);
      controller.setQuranReciterStyle(QuranReciterStyle.memorization);
      await pumpEventQueue();
      expect(state.playbackSpeed, 0.75);

      // User disables Quran Mode: speed must be restored in memory AND prefs
      await controller.setQuranModeEnabled(false);
      expect(state.playbackSpeed, 1.0);
      expect(prefs.getDouble(PrefsKeys.playbackSpeed), 1.0);
    });

    test('lossy Bluetooth applies HF presence compensation and scales reverb',
        () async {
      final fakeOutput = AudioOutputInfo(
        deviceName: 'realme Buds',
        isUsbDac: false,
        sampleRate: 44100,
        bitDepth: 16,
        isBitPerfectActive: false,
        isBluetooth: true,
        btCodecName: 'sbc',
      );
      final hiRes = _FakeHiResAudioService(fakeOutput);
      final earbudService = EarbudOptimizationService();
      final handler = _QuranAudioHandler();
      var state = const PlayerState();
      final controller = _controller(
        handler: handler,
        getState: () => state,
        emit: (s) => state = s,
        service: QuranModeService(),
        earbudOptimizationService: earbudService,
        hiResAudioService: hiRes,
      );

      await controller.setQuranModeEnabled(true);

      // Base Murattal gains:
      // [-2.0, -1.5, -1.0, 0.5, 1.5, 2.5, 3.5, 2.5, 0.5, -1.5]
      // SBC compensation: gains[7] += 0.5 (4 kHz -> 3.0), gains[8] += 0.5 (8 kHz -> 1.0)
      expect(state.eqPreset.gains[7], 3.0);
      expect(state.eqPreset.gains[8], 1.0);
      // SBC estimated latency >= 200 ms scales reverb by 0.65: base 0.12 * 0.65 = 0.078
      expect(state.reverbWetDry, closeTo(0.078, 0.001));
    });

    test('rapid toggling on and off does not drop state and respects latest intent',
        () async {
      final handler = _QuranAudioHandler();
      var state = const PlayerState();
      final controller = _controller(
        handler: handler,
        getState: () => state,
        emit: (s) => state = s,
        service: QuranModeService(),
      );

      // Start enabling
      final enableFuture = controller.setQuranModeEnabled(true);
      // Immediately toggle off before first completes
      final disableFuture = controller.setQuranModeEnabled(false);

      await Future.wait([enableFuture, disableFuture]);
      await pumpEventQueue();

      expect(state.isQuranModeEnabled, isFalse);
      final service = QuranModeService();
      expect(await service.isEnabled(), isFalse);
    });

    test('toggling off during an in-flight gated probe leaves mode disabled',
        () async {
      final output = AudioOutputInfo(
        deviceName: 'Wired',
        isUsbDac: false,
        sampleRate: 44100,
        bitDepth: 16,
        isBitPerfectActive: false,
      );
      final hiRes = _GatedHiResAudioService(output);
      final handler = _QuranAudioHandler();
      var state = const PlayerState();
      final controller = _controller(
        handler: handler,
        getState: () => state,
        emit: (s) => state = s,
        service: QuranModeService(),
        earbudOptimizationService: EarbudOptimizationService(),
        hiResAudioService: hiRes,
      );

      // Turn on (gates the capability check)
      final enable = controller.setQuranModeEnabled(true);
      await pumpEventQueue();
      expect(hiRes.gates, isNotEmpty);

      // User turns off while enable is awaiting capability probe
      final disable = controller.setQuranModeEnabled(false);
      await pumpEventQueue();
      expect(state.isQuranModeEnabled, isFalse);

      // Release probe gates
      for (final gate in hiRes.gates) {
        if (!gate.isCompleted) gate.complete();
      }
      await enable;
      await disable;
      await pumpEventQueue();

      // State must remain disabled and not be overwritten by delayed enable
      expect(state.isQuranModeEnabled, isFalse);
    });

    test('warmth and ambience update state immediately without muting transition',
        () async {
      final handler = _QuranAudioHandler();
      var state = const PlayerState();
      final controller = _controller(
        handler: handler,
        getState: () => state,
        emit: (s) => state = s,
        service: QuranModeService(),
      );

      await controller.setQuranModeEnabled(true);

      // Immediate synchronous emit for ambience
      final ambienceFuture = controller.setQuranAmbience(0.35);
      expect(state.reverbWetDry, 0.35);
      expect(state.isReverbEnabled, isTrue);
      await ambienceFuture;
      expect(handler.lastReverbWetDry, 0.35);

      // Immediate synchronous emit for warmth
      final warmthFuture = controller.setQuranWarmth(0.45);
      expect(state.saturationMix, 0.45);
      expect(state.isSaturationEnabled, isTrue);
      await warmthFuture;
      expect(handler.lastSaturationMix, 0.45);
    });
  });
}
