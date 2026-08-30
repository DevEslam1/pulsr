// test/dsp_expansion_test.dart
// Focused unit tests for the Phase-1 DSP expansion layer: EqualizerManager
// persistence round-trips, OptimizedDspPipeline stage ordering/flags, and the
// AudioFeatureInfo conflict-matrix entries for the 5 new stages.
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/audio_feature_info.dart';
import 'package:pulsr/data/audio/equalizer_manager.dart';
import 'package:pulsr/data/audio/optimized_dsp_pipeline.dart';
import 'package:pulsr/domain/models/audio_effects_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('OptimizedDspPipeline DSP-expansion stages', () {
    test('pipelineOrder contains the 5 new stages in engine execution order',
        () {
      const expectedOrder = [
        DspStage.parametricEq,
        DspStage.dynamicEq,
        DspStage.crossfeed,
        DspStage.convolutionReverb,
        DspStage.stereoPanner,
        DspStage.harmonicSaturation,
        DspStage.stereoWidth,
        DspStage.subCrossover,
        DspStage.lookaheadLimiter,
        DspStage.loudnessContour,
        DspStage.volume,
      ];
      expect(OptimizedDspPipeline.pipelineOrder, expectedOrder);
    });

    test('getActiveStages respects enable flags per stage', () {
      final pipeline = OptimizedDspPipeline();

      // Nothing enabled: only the always-on volume stage remains.
      expect(pipeline.getActiveStages(), [DspStage.volume]);

      // Enable every expansion stage + the classic ones.
      pipeline.updateState(
        isEqEnabled: true,
        isDynamicEqEnabled: true,
        isCrossfeedEnabled: true,
        isReverbEnabled: true,
        stereoBalance: 0.5,
        isSaturationEnabled: true,
        isStereoWidthEnabled: true,
        isSubCrossoverEnabled: true,
        isLoudnessContourEnabled: true,
        isLimiterEnabled: true,
      );
      expect(pipeline.getActiveStages(), OptimizedDspPipeline.pipelineOrder);

      // Panner drops out when balance returns to 0 and monoMix is off.
      pipeline.updateState(stereoBalance: 0.0);
      expect(pipeline.getActiveStages(), isNot(contains(DspStage.stereoPanner)));

      // Dynamic EQ alone toggles only its own stage.
      final dynOnly = OptimizedDspPipeline()
        ..updateState(isDynamicEqEnabled: true);
      expect(dynOnly.getActiveStages(),
          [DspStage.dynamicEq, DspStage.volume]);
    });

    test('bit-perfect bypass zeroes estimated latency regardless of stages',
        () {
      final pipeline = OptimizedDspPipeline()
        ..updateState(
          isEqEnabled: true,
          isReverbEnabled: true,
          isLimiterEnabled: true,
        )
        ..updateNativeLatency(frames: 512, sampleRate: 48000.0);

      // Without bypass the measured native latency is used: 512/48k = ~10.67 ms.
      expect(pipeline.calculateTotalEstimatedLatencyMs(), closeTo(10.667, 0.01));

      pipeline.updateState(bitPerfectBypass: true);
      expect(pipeline.calculateTotalEstimatedLatencyMs(), 0.0);
      // Lyrics/seek compensation keeps the raw position in bypass.
      const raw = Duration(seconds: 90);
      expect(pipeline.getCompensatedPosition(raw), raw);
    });
  });

  group('AudioFeatureInfo conflict matrix — Phase-1 stages', () {
    const expectedNewEntries = {
      'saturation': AudioFeatureRegistry.saturation,
      'stereoWidth': AudioFeatureRegistry.stereoWidth,
      'loudnessContour': AudioFeatureRegistry.loudnessContour,
      'subCrossover': AudioFeatureRegistry.subCrossover,
      'dynamicEq': AudioFeatureRegistry.dynamicEq,
    };

    test('the 5 new feature entries exist with expected ids', () {
      expectedNewEntries.forEach((id, info) {
        expect(info.id, id);
      });
    });

    test('all 5 new entries declare the Bit-Perfect bypass conflict', () {
      expectedNewEntries.forEach((id, info) {
        expect(info.conflictsWith, 'Bit-Perfect bypass',
            reason: '$id must conflict with Bit-Perfect bypass');
        expect(info.title, isNotEmpty);
        expect(info.description, isNotEmpty);
      });
    });

    test('ids are unique across the registry', () {
      const all = [
        AudioFeatureRegistry.bitPerfect,
        AudioFeatureRegistry.bypassDsp,
        AudioFeatureRegistry.equalizer,
        AudioFeatureRegistry.bassBoost,
        AudioFeatureRegistry.crossfeed,
        AudioFeatureRegistry.limiter,
        AudioFeatureRegistry.reverb,
        AudioFeatureRegistry.volumeBoost,
        AudioFeatureRegistry.saturation,
        AudioFeatureRegistry.stereoWidth,
        AudioFeatureRegistry.loudnessContour,
        AudioFeatureRegistry.subCrossover,
        AudioFeatureRegistry.dynamicEq,
      ];
      final ids = all.map((e) => e.id).toList();
      expect(ids.toSet().length, ids.length);
    });
  });

  group('EqualizerManager Phase-1 stage persistence', () {
    test('save + restore round-trips all 5 new feature states', () async {
      final manager = EqualizerManager();
      await manager.setSaturation(true, drive: 0.7, mix: 0.6, tilt: 0.2);
      await manager.setStereoWidth(true, width: 1.6);
      await manager.setLoudnessContour(true, intensity: 0.6);
      await manager.updateLoudnessVolume(0.4);
      await manager.setSubCrossover(true,
          cornerHz: 110.0, slopeDbPerOct: 12.0, gain: 0.6);
      await manager.setDynamicEq(true);
      await manager.setDynamicEqBand(
        0,
        const DynamicEqBandConfig(
          frequency: 2500.0,
          q: 3.0,
          thresholdDb: -28.0,
          ratio: 4.0,
          releaseMs: 200.0,
          maxCutDb: -9.0,
        ),
      );
      // Flush the debounce immediately and detach.
      await manager.onAppPaused();
      manager.dispose();

      // Values actually landed in prefs under the documented keys.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('setting_saturation_enabled'), isTrue);
      expect(prefs.getDouble('setting_saturation_drive'), 0.7);
      expect(prefs.getBool('setting_stereo_width_enabled'), isTrue);
      expect(prefs.getDouble('setting_stereo_width'), 1.6);
      expect(prefs.getBool('setting_loudness_contour_enabled'), isTrue);
      expect(prefs.getDouble('setting_loudness_contour_intensity'), 0.6);
      expect(prefs.getBool('setting_sub_crossover_enabled'), isTrue);
      expect(prefs.getDouble('setting_sub_crossover_corner_hz'), 110.0);
      expect(prefs.getDouble('setting_sub_crossover_slope_db_per_oct'), 12.0);
      expect(prefs.getDouble('setting_sub_crossover_gain'), 0.6);
      expect(prefs.getBool('setting_dynamic_eq_enabled'), isTrue);
      expect(prefs.getString('setting_dynamic_eq_bands'), isNotNull);

      // A fresh manager restores the exact same state from disk.
      final restored = EqualizerManager();
      await restored.init();
      expect(restored.isSaturationEnabled, isTrue);
      expect(restored.saturationDrive, 0.7);
      expect(restored.saturationMix, 0.6);
      expect(restored.saturationTilt, 0.2);
      expect(restored.isStereoWidthEnabled, isTrue);
      expect(restored.stereoWidth, 1.6);
      expect(restored.isLoudnessContourEnabled, isTrue);
      expect(restored.loudnessContourIntensity, 0.6);
      // loudnessVolumeLinear is runtime state (re-pushed by AudioHandler on
      // volume changes / session reattach) — deliberately NOT persisted, so a
      // fresh manager starts back at the 1.0 default.
      expect(restored.loudnessVolumeLinear, 1.0);
      expect(restored.isSubCrossoverEnabled, isTrue);
      expect(restored.subCrossoverCornerHz, 110.0);
      expect(restored.subCrossoverSlopeDbPerOct, 12.0);
      expect(restored.subCrossoverGain, 0.6);
      expect(restored.isDynamicEqEnabled, isTrue);
      expect(restored.dynamicEqBands.length, 1);
      const expectedBand = DynamicEqBandConfig(
        frequency: 2500.0,
        q: 3.0,
        thresholdDb: -28.0,
        ratio: 4.0,
        releaseMs: 200.0,
        maxCutDb: -9.0,
      );
      expect(restored.dynamicEqBands.first.frequency,
          expectedBand.frequency);
      expect(restored.dynamicEqBands.first.q, expectedBand.q);
      expect(restored.dynamicEqBands.first.thresholdDb,
          expectedBand.thresholdDb);
      expect(restored.dynamicEqBands.first.ratio, expectedBand.ratio);
      expect(restored.dynamicEqBands.first.attackMs,
          expectedBand.attackMs);
      expect(restored.dynamicEqBands.first.releaseMs,
          expectedBand.releaseMs);
      expect(restored.dynamicEqBands.first.maxCutDb, expectedBand.maxCutDb);
      expect(restored.dynamicEqBands.first.enabled, expectedBand.enabled);
      restored.dispose();
    });

    test('missing keys fall back to neutral defaults for all 5 stages',
        () async {
      SharedPreferences.setMockInitialValues({});
      final manager = EqualizerManager();
      await manager.init();

      // Saturation: disabled, drive 0.3 / mix 0.5 / tilt 0.3.
      expect(manager.isSaturationEnabled, isFalse);
      expect(manager.saturationDrive, 0.3);
      expect(manager.saturationMix, 0.5);
      expect(manager.saturationTilt, 0.3);

      // Stereo width: disabled, unity width.
      expect(manager.isStereoWidthEnabled, isFalse);
      expect(manager.stereoWidth, 1.0);

      // Loudness contour: disabled, zero intensity, unity volume.
      expect(manager.isLoudnessContourEnabled, isFalse);
      expect(manager.loudnessContourIntensity, 0.0);
      expect(manager.loudnessVolumeLinear, 1.0);

      // Sub crossover: disabled, 80 Hz / 24 dB/oct / 0.8 gain.
      expect(manager.isSubCrossoverEnabled, isFalse);
      expect(manager.subCrossoverCornerHz, 80.0);
      expect(manager.subCrossoverSlopeDbPerOct, 24.0);
      expect(manager.subCrossoverGain, 0.8);

      // Dynamic EQ: disabled, one default band.
      expect(manager.isDynamicEqEnabled, isFalse);
      expect(manager.dynamicEqBands.length, 1);
      expect(manager.dynamicEqBands.first.frequency, 1000.0);
      expect(manager.dynamicEqBands.first.thresholdDb, -30.0);
      expect(manager.dynamicEqBands.first.maxCutDb, -12.0);
      expect(manager.dynamicEqBands.first.enabled, isTrue);
      manager.dispose();
    });

    test('setters clamp out-of-range values for the new stages', () async {
      final manager = EqualizerManager();
      await manager.setSaturation(true, drive: 2.0, mix: -1.0, tilt: 5.0);
      expect(manager.saturationDrive, 1.0);
      expect(manager.saturationMix, 0.0);
      expect(manager.saturationTilt, 1.0);

      await manager.setStereoWidth(true, width: 9.0);
      expect(manager.stereoWidth, 2.0);

      await manager.setLoudnessContour(true, intensity: -3.0);
      expect(manager.loudnessContourIntensity, 0.0);

      await manager.setSubCrossover(true,
          cornerHz: 300.0, slopeDbPerOct: 18.0, gain: 4.0);
      expect(manager.subCrossoverCornerHz, 150.0);
      expect(manager.subCrossoverSlopeDbPerOct, 24.0); // 18 snaps up to 24
      expect(manager.subCrossoverGain, 1.0);
      await manager.onAppPaused();
      manager.dispose();
    });
  });
}
