// test/features/quran_mode/quran_mode_persistence_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/quran_mode_service.dart';
import 'package:pulsr/domain/models/eq_preset.dart';
import 'package:pulsr/domain/models/quran_mode_profile.dart';
import 'package:pulsr/features/player/cubit/controllers/player_controllers.dart';
import 'package:pulsr/features/player/cubit/managers/player_quran_manager.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/test_pulsr_audio_handler.dart';

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

  @override
  Future<void> setReverb(bool enabled, {int? preset, double? wetDry}) async {
    lastReverbWetDry = wetDry;
  }
}

PlayerPlaybackOptionsController _controller({
  required _QuranAudioHandler handler,
  required PlayerState Function() getState,
  required void Function(PlayerState) emit,
  QuranModeService? service,
}) {
  return PlayerPlaybackOptionsController(
    audioHandler: handler,
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
    });
  });
}
