// test/dsp_validation_test.dart
// Regression tests for the DSP input-validation sweep: every setter must
// clamp or reject out-of-range values so the stored Dart state never diverges
// from what the native engine actually applies.
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/equalizer_manager.dart';
import 'package:pulsr/domain/models/audio_effects_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('DSP input validation', () {
    test('crossfeed clamps delay, feed and mode', () async {
      final manager = EqualizerManager();
      await manager.setCrossfeed(
        true,
        delayUs: 5000.0,
        feedDb: 0.0,
        mode: 99,
      );
      expect(manager.crossfeedDelayUs, 700.0);
      expect(manager.crossfeedFeedDb, -6.0);
      expect(manager.crossfeedMode, 3);

      await manager.setCrossfeed(
        true,
        delayUs: -10.0,
        feedDb: -100.0,
        mode: -4,
      );
      expect(manager.crossfeedDelayUs, 200.0);
      expect(manager.crossfeedFeedDb, -15.0);
      expect(manager.crossfeedMode, 0);
      manager.dispose();
    });

    test('reverb clamps preset ordinal and wet/dry', () async {
      final manager = EqualizerManager();
      await manager.setReverb(true, preset: 999, wetDry: 5.0);
      expect(manager.reverbPreset, lessThanOrEqualTo(8));
      expect(manager.reverbWetDry, 1.0);

      await manager.setReverb(true, preset: -3, wetDry: -2.0);
      expect(manager.reverbPreset, greaterThanOrEqualTo(0));
      expect(manager.reverbWetDry, 0.0);
      manager.dispose();
    });

    test('stereo width crossovers keep low below high', () async {
      final manager = EqualizerManager();
      await manager.setStereoWidth(
        true,
        lowCrossoverHz: 1000.0,
        highCrossoverHz: 1000.0,
      );
      expect(
        manager.stereoWidthLowCrossoverHz,
        lessThan(manager.stereoWidthHighCrossoverHz),
      );
      manager.dispose();
    });

    test('multiband crossovers stay strictly ordered', () async {
      final manager = EqualizerManager();
      await manager.setMultibandCompressor(
        true,
        f0: 500.0,
        f1: 200.0,
        f2: 1000.0,
      );
      expect(manager.multibandCompressorF0, lessThan(manager.multibandCompressorF1));
      expect(manager.multibandCompressorF1, lessThan(manager.multibandCompressorF2));
      manager.dispose();
    });

    test('dynamic bass preset overrides custom values', () async {
      final manager = EqualizerManager();
      await manager.setDynamicBass(
        enabled: true,
        preset: 1,
        xLow: 999,
        yHigh: 299,
      );
      // Preset 1 (Extreme Headphone v2) wins over the custom values.
      expect(manager.dynamicBassPreset, 1);
      expect(manager.dynamicBassXLow, 140);
      expect(manager.dynamicBassYHigh, 60);
      manager.dispose();
    });

    test('liveprog sliders accept 1..8 and reject the rest', () async {
      final manager = EqualizerManager();
      await manager.setLiveProgSlider(1, 0.5);
      await manager.setLiveProgSlider(8, 0.5);
      expect(manager.liveProgSliders[1], 0.5);
      expect(manager.liveProgSliders[8], 0.5);

      await manager.setLiveProgSlider(0, 0.5);
      await manager.setLiveProgSlider(9, 0.5);
      await manager.setLiveProgSlider(-2, 0.5);
      await manager.setLiveProgSlider(2, double.nan);
      expect(manager.liveProgSliders.containsKey(0), isFalse);
      expect(manager.liveProgSliders.containsKey(9), isFalse);
      expect(manager.liveProgSliders.containsKey(-2), isFalse);
      expect(manager.liveProgSliders.containsKey(2), isFalse);
      manager.dispose();
    });

    test('empty impulse response is rejected', () async {
      final manager = EqualizerManager();
      expect(await manager.loadCustomImpulseResponse([]), isFalse);
      manager.dispose();
    });

    test('dynamic eq bands are sanitized to native ranges', () async {
      final manager = EqualizerManager();
      await manager.setDynamicEqBand(
        0,
        const DynamicEqBandConfig(
          frequency: 99999.0,
          q: 500.0,
          thresholdDb: 10.0,
          ratio: 100.0,
          attackMs: 0.0,
          releaseMs: 99999.0,
          maxCutDb: -500.0,
          maxBoostDb: 500.0,
          mode: 7,
          filterType: 42,
        ),
      );
      final band = manager.dynamicEqBands[0];
      expect(band.frequency, lessThanOrEqualTo(20000.0));
      expect(band.q, lessThanOrEqualTo(12.0));
      expect(band.thresholdDb, lessThanOrEqualTo(0.0));
      expect(band.ratio, lessThanOrEqualTo(20.0));
      expect(band.maxCutDb, greaterThanOrEqualTo(-24.0));
      expect(band.maxBoostDb, lessThanOrEqualTo(24.0));
      expect(band.mode, lessThanOrEqualTo(1));
      expect(band.filterType, lessThanOrEqualTo(2));

      // Out-of-range indices no longer fail silently or throw.
      await manager.setDynamicEqBand(-1, const DynamicEqBandConfig());
      await manager.setDynamicEqBand(99, const DynamicEqBandConfig());
      await manager.removeDynamicEqBand(99);
      expect(manager.dynamicEqBands.length, 1);
      manager.dispose();
    });
  });
}
