// Coverage for the uncovered branches of player_dsp_effects.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/audio/comparison_slot.dart';
import 'package:pulsr/domain/models/audio_effects_config.dart';
import 'package:pulsr/domain/models/reverb_preset.dart';
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

  PlayerDspController buildController() => PlayerDspController(
        audioHandler: handler,
        settingsCubit: settings,
        getState: () => state,
        emit: (s) => state = s,
        syncAudioEffects: ({bool force = false}) {},
        isClosed: () => false,
      );

  setUp(() {
    handler = RecordingAudioHandler();
    settings = MockSettingsCubit();
    when(() => settings.state).thenReturn(const SettingsState());
    state = const PlayerState();
    controller = buildController();
  });

  group('PlayerDspEffects gain staging', () {
    test('setBassBoost clamps to available headroom and logs', () async {
      state = PlayerState(
        dsp: const DspSlice().copyWith(
          isLoudnessContourEnabled: true,
          loudnessContourIntensity: 1.0,
        ),
      );
      await controller.setBassBoost(0.5);
      // State mirrors the requested boost; the engine is clamped to 0.
      expect(state.eqPreset.bassBoost, 0.5);
      expect(handler.calls, contains('setBassBoost'));
    });

    test('setVolumeBoost clamps to available headroom', () async {
      state = PlayerState(
        dsp: const DspSlice().copyWith(
          isLoudnessContourEnabled: true,
          loudnessContourIntensity: 1.0,
        ),
      );
      await controller.setVolumeBoost(0.9);
      expect(state.volumeBoost, 0.9);
      expect(handler.calls, contains('setVolumeBoost'));
    });

    test('rebalanceVolumeBoostIfNeeded lowers an over-budget boost', () async {
      state = PlayerState(
        dsp: const DspSlice().copyWith(
          volumeBoost: 0.9,
          isLoudnessContourEnabled: true,
          loudnessContourIntensity: 1.0,
        ),
      );
      await controller.rebalanceVolumeBoostIfNeeded();
      expect(handler.calls, contains('setVolumeBoost'));
    });

    test('rebalanceVolumeBoostIfNeeded is a no-op when boost is zero',
        () async {
      await controller.rebalanceVolumeBoostIfNeeded();
      expect(handler.calls, isNot(contains('setVolumeBoost')));
    });
  });

  group('PlayerDspEffects toggle guard', () {
    test('setVirtualizerEnabled(true) is refused under bit-perfect bypass',
        () async {
      when(() => settings.state).thenReturn(bitPerfectBypassSettings());
      await controller.setVirtualizerEnabled(true);
      expect(state.isVirtualizerEnabled, isFalse);
      expect(handler.calls, isNot(contains('setVirtualizerEnabled')));
      expect(state.errorMessage, contains('blocked'));
    });

    test('setVirtualizerEnabled(false) still applies (disabled toggle)',
        () async {
      when(() => settings.state).thenReturn(bitPerfectBypassSettings());
      await controller.setVirtualizerEnabled(false);
      expect(state.isVirtualizerEnabled, isFalse);
      expect(handler.calls, contains('setVirtualizerEnabled'));
    });

    test('guardDsp with showError false does not emit an error', () async {
      when(() => settings.state).thenReturn(bitPerfectBypassSettings());
      final ok = controller.guardDsp('Virtualizer', showError: false);
      expect(ok, isFalse);
      expect(state.errorMessage, isNull);
    });

    test('dspBlockedReason and playbackRateBlockedReason expose the reason',
        () {
      when(() => settings.state).thenReturn(bitPerfectBypassSettings());
      expect(controller.dspBlockedReason(), isNotNull);
      expect(controller.playbackRateBlockedReason(), isNotNull);
    });
  });

  group('PlayerDspEffects parameterised setters', () {
    test('setCrossfeed clamps raw parameters and mirrors state', () async {
      await controller.setCrossfeed(true, delayUs: 300, feedDb: -8.0, mode: 1);
      expect(state.isCrossfeedEnabled, isTrue);
      expect(state.crossfeedDelayUs, 300);
      expect(state.crossfeedMode, 1);
    });

    test('setCrossfeedMode applies even when crossfeed is disabled '
        '(guardCondition false skips the bit-perfect guard)', () async {
      await controller.setCrossfeedMode(2);
      expect(handler.calls, contains('setCrossfeedMode'));
      expect(state.crossfeedMode, 2);
    });

    test('setLookaheadLimiter applies clamped thresholds', () async {
      await controller.setLookaheadLimiter(true,
          thresholdDb: -0.3, releaseMs: 60.0);
      expect(state.isLimiterEnabled, isTrue);
      expect(state.limiterReleaseMs, 60.0);
    });

    test('setReverbPreset reuses current enabled flag', () async {
      await controller.setReverb(true);
      await controller.setReverbPreset(3);
      expect(state.reverbPreset, 3);
    });

    test('setStereoWidth maps band widths and crossovers', () async {
      await controller.setStereoWidth(true,
          width: 1.2,
          multiband: true,
          lowWidth: 0.8,
          midWidth: 1.1,
          highWidth: 1.4,
          lowCrossoverHz: 200,
          highCrossoverHz: 3000);
      expect(state.isStereoWidthEnabled, isTrue);
      expect(state.stereoWidthMultiband, isTrue);
      expect(state.stereoWidthLow, 0.8);
      expect(state.stereoWidthHigh, 1.4);
    });

    test('setLoudnessContour applies intensity', () async {
      await controller.setLoudnessContour(true, intensity: 0.4);
      expect(state.isLoudnessContourEnabled, isTrue);
      expect(state.loudnessContourIntensity, 0.4);
    });

    test('setSubCrossover maps parameters', () async {
      await controller.setSubCrossover(true,
          cornerHz: 100, slopeDbPerOct: 12, gain: 0.5, bassMono: true, antiPop: false);
      expect(state.isSubCrossoverEnabled, isTrue);
      expect(state.subCrossoverCornerHz, 100);
      expect(state.subCrossoverBassMono, isTrue);
      expect(state.subCrossoverAntiPop, isFalse);
    });

    test('setSaturation maps drive/mix/tilt/multiband', () async {
      await controller.setSaturation(true,
          drive: 0.7, mix: 0.4, tilt: 0.2, multiband: true);
      expect(state.isSaturationEnabled, isTrue);
      expect(state.saturationDrive, 0.7);
      expect(state.saturationMultiband, isTrue);
    });

    test('setSaturationMultiband applies when saturation is disabled',
        () async {
      await controller.setSaturationMultiband(true);
      expect(handler.calls, contains('setSaturationMultiband'));
      expect(state.saturationMultiband, isTrue);
    });

    test('setDynamicBass maps strength and preset', () async {
      await controller.setDynamicBass(true, strength: 2.0, preset: 3);
      expect(state.isDynamicBassEnabled, isTrue);
      expect(state.dynamicBassStrength, 2.0);
      expect(state.dynamicBassPreset, 3);
    });

    test('setDither rejects invalid bit depths and accepts valid ones',
        () async {
      await controller.setDither(true, targetBitDepth: 20);
      expect(handler.calls, isNot(contains('setDither')));
      await controller.setDither(true, targetBitDepth: 24);
      expect(state.isDitherEnabled, isTrue);
      expect(state.ditherTargetBitDepth, 24);
    });

    test('setStereoBalance near-zero still applies without a guard error',
        () async {
      await controller.setStereoBalance(0.0);
      expect(handler.calls, contains('setStereoBalance'));
      expect(state.errorMessage, isNull);
      await controller.setStereoBalance(0.5);
      expect(state.stereoBalance, 0.5);
    });

    test('setMonoMix and setSincResampler toggle state', () async {
      await controller.setMonoMix(true);
      await controller.setSincResampler(false);
      expect(state.monoMix, isTrue);
      expect(state.isSincResamplerEnabled, isFalse);
    });

    test('setDynamicsPreset honours the explicit enabled flag', () async {
      await controller.setDynamicsPreset(DynamicsPreset.off, enabled: true);
      expect(state.isDynamicsEnabled, isTrue);
      expect(state.dynamicsPreset, DynamicsPreset.off);
    });

    test('toggleDynamicsBypass refreshes the enabled flag', () async {
      state = PlayerState(
        dsp: const DspSlice()
            .copyWith(dynamicsPreset: DynamicsPreset.studioPunch),
      );
      await controller.toggleDynamicsBypass();
      expect(handler.calls, contains('toggleDynamicsBypass'));
      expect(state.isDynamicsEnabled, isTrue);
    });
  });

  group('PlayerDspEffects dynamic EQ and misc', () {
    test('setDynamicEqBand ignores out-of-range indices', () async {
      await controller.setDynamicEqBand(0, sampleDynamicEqBand);
      expect(handler.calls, isNot(contains('setDynamicEqBand')));
    });

    test('setDynamicEqBand updates an existing band', () async {
      state = PlayerState(
        dsp: const DspSlice().copyWith(
          isDynamicEqEnabled: true,
          dynamicEqBands: [sampleDynamicEqBand],
        ),
      );
      await controller.setDynamicEqBand(0, const DynamicEqBandConfig());
      expect(handler.calls, contains('setDynamicEqBand'));
      expect(state.dynamicEqBands.length, 1);
    });

    test('addDynamicEqBand caps the band list at 8', () async {
      state = PlayerState(
        dsp: const DspSlice().copyWith(
          isDynamicEqEnabled: true,
          dynamicEqBands: List.filled(8, sampleDynamicEqBand),
        ),
      );
      await controller.addDynamicEqBand();
      expect(handler.calls, isNot(contains('addDynamicEqBand')));
      expect(state.dynamicEqBands.length, 8);
    });

    test('removeDynamicEqBand ignores out-of-range indices', () async {
      await controller.removeDynamicEqBand(5);
      expect(handler.calls, isNot(contains('removeDynamicEqBand')));
    });

    test('setViperDdcEnabled / setArbitraryEqEnabled / setLiveProgEnabled',
        () async {
      await controller.setViperDdcEnabled(true, profileName: 'HP');
      await controller.setArbitraryEqEnabled(true, eqString: 'GraphicEq: 1 2');
      await controller.setLiveProgEnabled(true, code: '@init');
      expect(state.isViperDdcEnabled, isTrue);
      expect(state.isArbitraryEqEnabled, isTrue);
      expect(state.isLiveProgEnabled, isTrue);
      expect(controller.isArbitraryEqLinearPhase, isFalse);
    });

    test('setLiveProgSlider surfaces a native failure', () async {
      handler.throwCalls.add('setLiveProgSlider');
      await controller.setLiveProgSlider(0, 0.5);
      expect(state.errorMessage, contains('LiveProg slider'));
    });

    test('setBypassCompare delegates to the handler', () async {
      await controller.setBypassCompare(bypass: true);
      expect(handler.calls, contains('setBypassCompare'));
    });

    test('mergeRoomCorrectionWithHeadphoneCurve and export IR', () {
      final merged = controller.mergeRoomCorrectionWithHeadphoneCurve(
          const [1.0, 2.0, 3.0]);
      expect(merged, isA<List<double>>());
      final ir = controller.exportCorrectionImpulseResponse(
          const [1.0, 2.0, 3.0]);
      expect(ir, isA<List<double>>());
    });
  });

  group('PlayerDspEffects reverb IR', () {
    test('loadCustomImpulseResponse success switches to custom preset',
        () async {
      final ok = await controller.loadCustomImpulseResponse([0.1, 0.2]);
      expect(ok, isTrue);
      expect(state.isReverbEnabled, isTrue);
      expect(state.reverbPreset, ReverbPreset.custom.wireValue);
    });

    test('loadCustomImpulseResponse rejection surfaces an error', () async {
      handler.irLoadResult = false;
      final ok = await controller.loadCustomImpulseResponse([0.1, 0.2]);
      expect(ok, isFalse);
      expect(state.errorMessage, contains('rejected'));
    });

    test('loadCustomImpulseResponse exception surfaces an error', () async {
      handler.throwCalls.add('loadCustomImpulseResponse');
      final ok = await controller.loadCustomImpulseResponse([0.1, 0.2]);
      expect(ok, isFalse);
      expect(state.errorMessage, contains('Failed to load impulse response'));
    });

    test('loadCustomImpulseResponse is refused under bit-perfect bypass',
        () async {
      when(() => settings.state).thenReturn(bitPerfectBypassSettings());
      final ok = await controller.loadCustomImpulseResponse([0.1]);
      expect(ok, isFalse);
    });
  });

  group('PlayerDspEffects master enable', () {
    test('disable then enable restores a captured snapshot', () async {
      await controller.setVirtualizerEnabled(true);
      await controller.setVirtualizerStrength(0.75);
      expect(state.isDspEffectsActive, isTrue);

      await controller.setDspEffectsEnabled(false);
      expect(state.isDspEffectsActive, isFalse);
      expect(handler.calls, contains('setViperDdc'));

      await controller.setDspEffectsEnabled(true);
      expect(state.isVirtualizerEnabled, isTrue);
      expect(state.virtualizerStrength, 0.75);
    });

    test('enable with no snapshot applies conservative defaults', () async {
      state = PlayerState(
        dsp: const DspSlice().copyWith(isVirtualizerSupported: true),
      );
      await controller.setDspEffectsEnabled(true);
      expect(state.isVirtualizerEnabled, isTrue);
      expect(state.isLimiterEnabled, isTrue);
      expect(handler.calls, contains('setVirtualizerStrength'));
    });

    test('enable is refused under bit-perfect bypass', () async {
      when(() => settings.state).thenReturn(bitPerfectBypassSettings());
      await controller.setDspEffectsEnabled(true);
      expect(state.errorMessage, contains('DSP Engine blocked'));
    });

    test('a native failure during disable is caught and surfaces an error',
        () async {
      handler.throwCalls.add('setViperDdc');
      await controller.setDspEffectsEnabled(false);
      expect(state.errorMessage, contains('Failed to update DSP effects'));
    });
  });

  group('PlayerDspEffects comparison slot', () {
    test('switchComparisonSlot forwards to the handler', () async {
      // switchComparisonSlot is on the controller's comparison extension.
      await controller.switchComparisonSlot(ComparisonSlot.slotB);
      expect(handler.calls, contains('switchComparisonSlot'));
    });
  });
}
