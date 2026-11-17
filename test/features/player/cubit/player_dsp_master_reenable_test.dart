// Regression test for P0-1.5: re-enabling the master DSP switch must not invent
// stage settings. An EQ-only session (no spatializer/virtualizer/limiter was on)
// used to come back with spatializer+limiter forced on by the old fallback.
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/features/player/cubit/controllers/player_dsp_controller.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';

import '../player_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RecordingAudioHandler handler;
  late MockSettingsCubit settings;
  late PlayerState state;
  late PlayerDspController controller;

  setUp(() {
    handler = RecordingAudioHandler();
    settings = MockSettingsCubit();
    when(() => settings.state).thenReturn(const SettingsState());
    state = const PlayerState();
    controller = PlayerDspController(
      audioHandler: handler,
      settingsCubit: settings,
      getState: () => state,
      emit: (s) => state = s,
      syncAudioEffects: ({bool force = false}) {},
      isClosed: () => false,
    );
  });

  tearDown(() => controller.dispose());

  group('master DSP re-enable', () {
    test('EQ-only session comes back with no stage enabled', () async {
      // EQ alone does not make the effects domain "active".
      state = state.copyWith(dsp: state.dsp.copyWith(isEqEnabled: true));
      expect(state.dsp.isDspEffectsActive, isFalse);

      await controller.setDspEffectsEnabled(false);
      expect(controller.hasDspEffectsSnapshot, isFalse,
          reason: 'a session with no active stage captures no snapshot');

      final callsBeforeEnable = handler.calls.length;
      await controller.setDspEffectsEnabled(true);

      expect(state.dsp.isSpatializerEnabled, isFalse);
      expect(state.dsp.isVirtualizerEnabled, isFalse);
      expect(state.dsp.isLimiterEnabled, isFalse);
      expect(state.dsp.isDynamicsEnabled, isFalse);
      expect(state.dsp.isReverbEnabled, isFalse);
      expect(state.dsp.isEqEnabled, isTrue,
          reason: 'the EQ the user configured must survive the master toggle');

      final stageCalls = handler.calls
          .skip(callsBeforeEnable)
          .where(<String>{
            'setSpatializerEnabled',
            'setVirtualizerEnabled',
            'setVirtualizerStrength',
            'setDynamicsPreset',
            'setCrossfeed',
            'setLookaheadLimiter',
            'setReverb',
            'setSaturation',
            'setStereoWidth',
            'setLoudnessContour',
            'setSubCrossover',
            'setDynamicEq',
            'setViperDdc',
            'setArbitraryEq',
            'setLiveProg',
            'setDynamicBass',
            'setVolumeBoost',
            'setBassBoost',
          }.contains)
          .toList();
      expect(stageCalls, isEmpty,
          reason: 'enabling must not push invented stage defaults to the engine');
    });

    test('a real snapshot still restores exactly what was on', () async {
      state = state.copyWith(
        dsp: state.dsp.copyWith(
          isLimiterEnabled: true,
          limiterThresholdDb: -1.0,
          limiterReleaseMs: 80.0,
        ),
      );

      await controller.setDspEffectsEnabled(false);
      expect(state.dsp.isLimiterEnabled, isFalse);
      expect(controller.hasDspEffectsSnapshot, isTrue);

      await controller.setDspEffectsEnabled(true);
      expect(state.dsp.isLimiterEnabled, isTrue);
      expect(state.dsp.limiterThresholdDb, -1.0);
      expect(state.dsp.limiterReleaseMs, 80.0);
      expect(state.dsp.isSpatializerEnabled, isFalse,
          reason: 'only the captured stages come back');
      expect(handler.calls.where((c) => c == 'setLookaheadLimiter'),
          isNotEmpty);
    });
  });
}
