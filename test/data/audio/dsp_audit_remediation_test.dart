// test/data/audio/dsp_audit_remediation_test.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/data/audio/equalizer_manager.dart';
import 'package:pulsr/data/audio/optimized_dsp_pipeline.dart';
import 'package:pulsr/features/player/cubit/controllers/dsp_effect_applier.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DSP Audit Remediation Suite', () {
    late EqualizerManager manager;
    final List<MethodCall> methodCalls = [];

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      methodCalls.clear();

      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel(PulsrChannels.audioEffects),
        (MethodCall call) async {
          methodCalls.add(call);
          if (call.method == 'loadArbitraryEq') return true;
          return true;
        },
      );

      manager = EqualizerManager();
    });

    tearDown(() {
      manager.dispose();
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel(PulsrChannels.audioEffects), null);
    });

    test('1. Arbitrary EQ clearing forwards empty string to native channel',
        () async {
      // First load a real profile
      await manager.setArbitraryEq(
        true,
        eqString: 'GraphicEQ: 20 0; 20000 0',
        linearPhase: true,
      );
      expect(manager.arbitraryEqString, 'GraphicEQ: 20 0; 20000 0');
      expect(manager.isArbitraryEqEnabled, isTrue);

      methodCalls.clear();

      // Now clear the response with empty string
      await manager.setArbitraryEq(false, eqString: '');
      expect(manager.arbitraryEqString, '');
      expect(manager.isArbitraryEqEnabled, isFalse);

      // Verify that loadArbitraryEq was indeed called with empty string
      final loadCalls = methodCalls
          .where((call) => call.method == 'loadArbitraryEq')
          .toList();
      expect(loadCalls.length, 1);
      expect(loadCalls.first.arguments['eqString'], '');
    });

    test('2. OptimizedDspPipeline orders Saturation before Convolution Reverb',
        () {
      final saturationIdx =
          OptimizedDspPipeline.pipelineOrder.indexOf(DspStage.harmonicSaturation);
      final reverbIdx =
          OptimizedDspPipeline.pipelineOrder.indexOf(DspStage.convolutionReverb);

      expect(saturationIdx, greaterThan(-1));
      expect(reverbIdx, greaterThan(-1));
      expect(saturationIdx, lessThan(reverbIdx),
          reason: 'Harmonic saturation must precede convolution reverb');
    });

    test('3. DspSlice.isDspActive & isDspEffectsActive track multiband compressor',
        () {
      const sliceOff = DspSlice(isMultibandCompressorEnabled: false);
      expect(sliceOff.isDspActive, isFalse);
      expect(sliceOff.isDspEffectsActive, isFalse);
      expect(sliceOff.activeDspStagesCount, 0);

      const sliceOn = DspSlice(isMultibandCompressorEnabled: true);
      expect(sliceOn.isDspActive, isTrue);
      expect(sliceOn.isDspEffectsActive, isTrue);
      expect(sliceOn.activeDspStagesCount, 1);
      expect(sliceOn.activeDspEffectStagesCount, 1);

      const state = PlayerState(dsp: sliceOn);
      expect(state.isMultibandCompressorEnabled, isTrue);
      expect(state.isDspActive, isTrue);
    });

    test('4. DspRollbackPolicy reconciles multiband compressor & arbitrary linear phase',
        () {
      const prev = DspSlice(
        isMultibandCompressorEnabled: false,
        multibandCompressorF0: 160.0,
        multibandCompressorF1: 1000.0,
        multibandCompressorF2: 5000.0,
        arbitraryEqLinearPhase: false,
      );

      const attempted = DspSlice(
        isMultibandCompressorEnabled: true,
        multibandCompressorF0: 200.0,
        multibandCompressorF1: 1500.0,
        multibandCompressorF2: 6000.0,
        arbitraryEqLinearPhase: true,
      );

      // Current has the optimistic changes from attempted
      final rolledBack = DspRollbackPolicy.merge(attempted, prev, attempted);

      expect(rolledBack.isMultibandCompressorEnabled, isFalse);
      expect(rolledBack.multibandCompressorF0, 160.0);
      expect(rolledBack.multibandCompressorF1, 1000.0);
      expect(rolledBack.multibandCompressorF2, 5000.0);
      expect(rolledBack.arbitraryEqLinearPhase, isFalse);
    });

    test('5. EqualizerManager configures dither target bit depth', () async {
      await manager.setDither(true, targetBitDepth: 16);
      expect(manager.isDitherEnabled, isTrue);
      expect(manager.ditherTargetBitDepth, 16);

      await manager.setDither(true, targetBitDepth: 24);
      expect(manager.ditherTargetBitDepth, 24);

      final ditherCalls =
          methodCalls.where((c) => c.method == 'setDitherParams').toList();
      expect(ditherCalls.isNotEmpty, isTrue);
    });

    test('6. OptimizedDspPipeline orders Multiband Compressor properly', () {
      final dynEqIdx =
          OptimizedDspPipeline.pipelineOrder.indexOf(DspStage.dynamicEq);
      final mbcIdx =
          OptimizedDspPipeline.pipelineOrder.indexOf(DspStage.multibandCompressor);
      final pannerIdx =
          OptimizedDspPipeline.pipelineOrder.indexOf(DspStage.stereoPanner);

      expect(mbcIdx, greaterThan(dynEqIdx));
      expect(mbcIdx, lessThan(pannerIdx));
    });
  });
}
