// test/domain/models/audio_effects_config_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/models/audio_effects_config.dart';

void main() {
  group('DynamicsPreset', () {
    test('every preset exposes a non-empty label and description', () {
      for (final preset in DynamicsPreset.values) {
        expect(preset.label, isNotEmpty);
        expect(preset.description, isNotEmpty);
      }
    });
  });

  group('AudioEffectsConfig copyWith', () {
    test('defaults are applied when no arguments are supplied', () {
      const config = AudioEffectsConfig();
      final copy = config.copyWith();
      expect(copy.isVirtualizerEnabled, isFalse);
      expect(copy.virtualizerStrength, 0.0);
      expect(copy.isDynamicsEnabled, isFalse);
      expect(copy.dynamicsPreset, DynamicsPreset.off);
      expect(copy.isDynamicsBypassed, isFalse);
      expect(copy.isSaturationEnabled, isFalse);
      expect(copy.saturationDrive, 0.3);
      expect(copy.saturationMix, 0.5);
      expect(copy.saturationTilt, 0.3);
      expect(copy.saturationMode, 0);
      expect(copy.isStereoWidthEnabled, isFalse);
      expect(copy.stereoWidth, 1.0);
      expect(copy.stereoWidthMultiband, isFalse);
      expect(copy.stereoWidthLow, 1.0);
      expect(copy.stereoWidthMid, 1.0);
      expect(copy.stereoWidthHigh, 1.0);
      expect(copy.stereoWidthLowCrossoverHz, 160.0);
      expect(copy.stereoWidthHighCrossoverHz, 2500.0);
      expect(copy.isLoudnessContourEnabled, isFalse);
      expect(copy.loudnessContourIntensity, 0.0);
      expect(copy.isSubCrossoverEnabled, isFalse);
      expect(copy.subCrossoverCornerHz, 80.0);
      expect(copy.subCrossoverSlopeDbPerOct, 24.0);
      expect(copy.subCrossoverGain, 0.8);
      expect(copy.subCrossoverBassMono, isFalse);
      expect(copy.subCrossoverAntiPop, isTrue);
      expect(copy.isDynamicEqEnabled, isFalse);
      expect(copy.dynamicEqBands, isEmpty);
      expect(copy.isMultibandCompressorEnabled, isFalse);
      expect(copy.multibandCompressorBands, isEmpty);
      expect(copy.isDynamicBassEnabled, isFalse);
      expect(copy.dynamicBassStrength, 1.0);
      expect(copy.dynamicBassXLow, 100);
      expect(copy.dynamicBassXHigh, 5600);
      expect(copy.dynamicBassYLow, 40);
      expect(copy.dynamicBassYHigh, 80);
      expect(copy.dynamicBassSideGainLow, 0.10);
      expect(copy.dynamicBassSideGainHigh, 0.50);
      expect(copy.dynamicBassPreset, 0);
    });

    test('overrides only the supplied fields', () {
      final config = const AudioEffectsConfig().copyWith(
        isVirtualizerEnabled: true,
        virtualizerStrength: 0.75,
        isDynamicsEnabled: true,
        dynamicsPreset: DynamicsPreset.studioPunch,
        isDynamicsBypassed: true,
        isSaturationEnabled: true,
        saturationDrive: 0.9,
        saturationMix: 0.1,
        saturationTilt: 0.2,
        saturationMode: 2,
        isStereoWidthEnabled: true,
        stereoWidth: 1.8,
        stereoWidthMultiband: true,
        stereoWidthLow: 0.2,
        stereoWidthMid: 1.1,
        stereoWidthHigh: 1.9,
        stereoWidthLowCrossoverHz: 200.0,
        stereoWidthHighCrossoverHz: 3000.0,
        isLoudnessContourEnabled: true,
        loudnessContourIntensity: 0.4,
        isSubCrossoverEnabled: true,
        subCrossoverCornerHz: 120.0,
        subCrossoverSlopeDbPerOct: 12.0,
        subCrossoverGain: 0.5,
        subCrossoverBassMono: true,
        subCrossoverAntiPop: false,
        isDynamicEqEnabled: true,
        dynamicEqBands: const [DynamicEqBandConfig(frequency: 80)],
        isMultibandCompressorEnabled: true,
        multibandCompressorBands: const [MultibandCompressorBandConfig()],
        isDynamicBassEnabled: true,
        dynamicBassStrength: 3.0,
        dynamicBassXLow: 140,
        dynamicBassXHigh: 6200,
        dynamicBassYLow: 40,
        dynamicBassYHigh: 60,
        dynamicBassSideGainLow: 0.2,
        dynamicBassSideGainHigh: 0.7,
        dynamicBassPreset: 1,
      );

      expect(config.isVirtualizerEnabled, isTrue);
      expect(config.virtualizerStrength, 0.75);
      expect(config.isDynamicsEnabled, isTrue);
      expect(config.dynamicsPreset, DynamicsPreset.studioPunch);
      expect(config.isDynamicsBypassed, isTrue);
      expect(config.isSaturationEnabled, isTrue);
      expect(config.saturationDrive, 0.9);
      expect(config.saturationMix, 0.1);
      expect(config.saturationTilt, 0.2);
      expect(config.saturationMode, 2);
      expect(config.isStereoWidthEnabled, isTrue);
      expect(config.stereoWidth, 1.8);
      expect(config.stereoWidthMultiband, isTrue);
      expect(config.stereoWidthLow, 0.2);
      expect(config.stereoWidthMid, 1.1);
      expect(config.stereoWidthHigh, 1.9);
      expect(config.stereoWidthLowCrossoverHz, 200.0);
      expect(config.stereoWidthHighCrossoverHz, 3000.0);
      expect(config.isLoudnessContourEnabled, isTrue);
      expect(config.loudnessContourIntensity, 0.4);
      expect(config.isSubCrossoverEnabled, isTrue);
      expect(config.subCrossoverCornerHz, 120.0);
      expect(config.subCrossoverSlopeDbPerOct, 12.0);
      expect(config.subCrossoverGain, 0.5);
      expect(config.subCrossoverBassMono, isTrue);
      expect(config.subCrossoverAntiPop, isFalse);
      expect(config.isDynamicEqEnabled, isTrue);
      expect(config.dynamicEqBands, hasLength(1));
      expect(config.isMultibandCompressorEnabled, isTrue);
      expect(config.multibandCompressorBands, hasLength(1));
      expect(config.isDynamicBassEnabled, isTrue);
      expect(config.dynamicBassStrength, 3.0);
      expect(config.dynamicBassXLow, 140);
      expect(config.dynamicBassXHigh, 6200);
      expect(config.dynamicBassYLow, 40);
      expect(config.dynamicBassYHigh, 60);
      expect(config.dynamicBassSideGainLow, 0.2);
      expect(config.dynamicBassSideGainHigh, 0.7);
      expect(config.dynamicBassPreset, 1);
    });
  });

  group('DynamicEqBandConfig', () {
    test('equality and hashCode consider every field', () {
      const a = DynamicEqBandConfig();
      const b = DynamicEqBandConfig();
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(identical(a, a), isTrue);
      expect(a == Object(), isFalse);

      expect(a, isNot(const DynamicEqBandConfig(frequency: 1200)));
      expect(a, isNot(const DynamicEqBandConfig(q: 3)));
      expect(a, isNot(const DynamicEqBandConfig(thresholdDb: -20)));
      expect(a, isNot(const DynamicEqBandConfig(ratio: 4)));
      expect(a, isNot(const DynamicEqBandConfig(attackMs: 10)));
      expect(a, isNot(const DynamicEqBandConfig(releaseMs: 200)));
      expect(a, isNot(const DynamicEqBandConfig(maxCutDb: -6)));
      expect(a, isNot(const DynamicEqBandConfig(maxBoostDb: 6)));
      expect(a, isNot(const DynamicEqBandConfig(mode: 1)));
      expect(a, isNot(const DynamicEqBandConfig(filterType: 1)));
      expect(a, isNot(const DynamicEqBandConfig(enabled: false)));
    });

    test('copyWith overrides supplied fields', () {
      final band = const DynamicEqBandConfig().copyWith(
        frequency: 250.0,
        q: 4.0,
        thresholdDb: -10.0,
        ratio: 6.0,
        attackMs: 1.0,
        releaseMs: 5.0,
        maxCutDb: -3.0,
        maxBoostDb: 3.0,
        mode: 1,
        filterType: 2,
        enabled: false,
      );
      expect(band.frequency, 250.0);
      expect(band.q, 4.0);
      expect(band.thresholdDb, -10.0);
      expect(band.ratio, 6.0);
      expect(band.attackMs, 1.0);
      expect(band.releaseMs, 5.0);
      expect(band.maxCutDb, -3.0);
      expect(band.maxBoostDb, 3.0);
      expect(band.mode, 1);
      expect(band.filterType, 2);
      expect(band.enabled, isFalse);
    });

    test('fromJson defaults and numeric coercion', () {
      final def = DynamicEqBandConfig.fromJson(const {});
      expect(def.frequency, 1000.0);
      expect(def.q, 2.0);
      expect(def.thresholdDb, -30.0);
      expect(def.ratio, 3.0);
      expect(def.attackMs, 5.0);
      expect(def.releaseMs, 120.0);
      expect(def.maxCutDb, -12.0);
      expect(def.maxBoostDb, 12.0);
      expect(def.mode, 0);
      expect(def.filterType, 0);
      expect(def.enabled, isTrue);

      final parsed = DynamicEqBandConfig.fromJson(const {
        'frequency': 500,
        'q': 1,
        'thresholdDb': -18,
        'ratio': 2,
        'attackMs': 3,
        'releaseMs': 60,
        'maxCutDb': -4,
        'maxBoostDb': 4,
        'mode': 1,
        'filterType': 2,
        'enabled': false,
      });
      expect(parsed.frequency, 500.0);
      expect(parsed.enabled, isFalse);
      expect(parsed.filterType, 2);
    });

    test('fromJson clamps maxCutDb and maxBoostDb into range', () {
      final over = DynamicEqBandConfig.fromJson(const {
        'maxCutDb': -500.0,
        'maxBoostDb': 500.0,
      });
      expect(over.maxCutDb, -96.0);
      expect(over.maxBoostDb, 96.0);

      final under = DynamicEqBandConfig.fromJson(const {
        'maxCutDb': 500.0,
        'maxBoostDb': -500.0,
      });
      expect(under.maxCutDb, 0.0);
      expect(under.maxBoostDb, 0.0);
    });

    test('toJson round-trips', () {
      const band = DynamicEqBandConfig(
        frequency: 120.0,
        q: 1.5,
        thresholdDb: -24.0,
        ratio: 5.0,
        attackMs: 2.0,
        releaseMs: 80.0,
        maxCutDb: -8.0,
        maxBoostDb: 8.0,
        mode: 1,
        filterType: 1,
        enabled: false,
      );
      final json = band.toJson();
      final back = DynamicEqBandConfig.fromJson(json);
      expect(back, equals(band));
    });

    test('sanitized clamps every field', () {
      const wild = DynamicEqBandConfig(
        frequency: 100000.0,
        q: 100.0,
        thresholdDb: 50.0,
        ratio: 100.0,
        attackMs: 1000.0,
        releaseMs: 1.0,
        maxCutDb: -100.0,
        maxBoostDb: 100.0,
        mode: 5,
        filterType: 9,
        enabled: false,
      );
      final s = wild.sanitized();
      expect(s.frequency, 20000.0);
      expect(s.q, 12.0);
      expect(s.thresholdDb, 0.0);
      expect(s.ratio, 20.0);
      expect(s.attackMs, 200.0);
      expect(s.releaseMs, 5.0);
      expect(s.maxCutDb, -24.0);
      expect(s.maxBoostDb, 24.0);
      expect(s.mode, 1);
      expect(s.filterType, 2);
      expect(s.enabled, isFalse);

      const low = DynamicEqBandConfig(
        frequency: 1.0,
        q: 0.0,
        thresholdDb: -200.0,
        ratio: 0.0,
        attackMs: 0.0,
        releaseMs: 10000.0,
        maxCutDb: 10.0,
        maxBoostDb: -10.0,
        mode: -1,
        filterType: -1,
      );
      final sl = low.sanitized();
      expect(sl.frequency, 20.0);
      expect(sl.q, 0.1);
      expect(sl.thresholdDb, -80.0);
      expect(sl.ratio, 1.0);
      expect(sl.attackMs, 0.1);
      expect(sl.releaseMs, 2000.0);
      expect(sl.maxCutDb, 0.0);
      expect(sl.maxBoostDb, 0.0);
      expect(sl.mode, 0);
      expect(sl.filterType, 0);
    });
  });

  group('MultibandCompressorBandConfig', () {
    test('equality and hashCode consider every field', () {
      const a = MultibandCompressorBandConfig();
      expect(a, equals(const MultibandCompressorBandConfig()));
      expect(a.hashCode, const MultibandCompressorBandConfig().hashCode);
      expect(identical(a, a), isTrue);
      expect(a == Object(), isFalse);
      expect(a, isNot(const MultibandCompressorBandConfig(thresholdDb: -30)));
      expect(a, isNot(const MultibandCompressorBandConfig(ratio: 4)));
      expect(a, isNot(const MultibandCompressorBandConfig(attackMs: 5)));
      expect(a, isNot(const MultibandCompressorBandConfig(releaseMs: 200)));
      expect(a, isNot(const MultibandCompressorBandConfig(kneeDb: 3)));
      expect(
          a, isNot(const MultibandCompressorBandConfig(makeupGainDb: 2)));
      expect(a, isNot(const MultibandCompressorBandConfig(enabled: false)));
    });

    test('copyWith overrides supplied fields', () {
      final b = const MultibandCompressorBandConfig().copyWith(
        thresholdDb: -30.0,
        ratio: 8.0,
        attackMs: 5.0,
        releaseMs: 250.0,
        kneeDb: 3.0,
        makeupGainDb: 2.0,
        enabled: false,
      );
      expect(b.thresholdDb, -30.0);
      expect(b.ratio, 8.0);
      expect(b.attackMs, 5.0);
      expect(b.releaseMs, 250.0);
      expect(b.kneeDb, 3.0);
      expect(b.makeupGainDb, 2.0);
      expect(b.enabled, isFalse);
    });

    test('fromJson defaults and toJson round-trip', () {
      final def = MultibandCompressorBandConfig.fromJson(const {});
      expect(def.thresholdDb, -20.0);
      expect(def.ratio, 2.0);
      expect(def.attackMs, 20.0);
      expect(def.releaseMs, 100.0);
      expect(def.kneeDb, 6.0);
      expect(def.makeupGainDb, 0.0);
      expect(def.enabled, isTrue);

      const band = MultibandCompressorBandConfig(
        thresholdDb: -35.0,
        ratio: 5.0,
        attackMs: 4.0,
        releaseMs: 300.0,
        kneeDb: 2.0,
        makeupGainDb: 1.5,
        enabled: false,
      );
      final back = MultibandCompressorBandConfig.fromJson(band.toJson());
      expect(back, equals(band));
    });
  });

  group('DynamicBassConfig', () {
    test('copyWith overrides supplied fields', () {
      final c = const DynamicBassConfig().copyWith(
        enabled: true,
        strength: 4.0,
        xLow: 200,
        xHigh: 5000,
        yLow: 50,
        yHigh: 90,
        sideGainLow: 0.3,
        sideGainHigh: 0.6,
        preset: 3,
      );
      expect(c.enabled, isTrue);
      expect(c.strength, 4.0);
      expect(c.xLow, 200);
      expect(c.xHigh, 5000);
      expect(c.yLow, 50);
      expect(c.yHigh, 90);
      expect(c.sideGainLow, 0.3);
      expect(c.sideGainHigh, 0.6);
      expect(c.preset, 3);
    });

    test('fromJson defaults and toJson round-trip', () {
      final def = DynamicBassConfig.fromJson(const {});
      expect(def.enabled, isFalse);
      expect(def.strength, 1.0);
      expect(def.xLow, 100);
      expect(def.xHigh, 5600);
      expect(def.yLow, 40);
      expect(def.yHigh, 80);
      expect(def.sideGainLow, 0.10);
      expect(def.sideGainHigh, 0.50);
      expect(def.preset, 0);

      const cfg = DynamicBassConfig(
        enabled: true,
        strength: 2.5,
        xLow: 140,
        xHigh: 6200,
        yLow: 40,
        yHigh: 60,
        sideGainLow: 0.1,
        sideGainHigh: 0.8,
        preset: 1,
      );
      final back = DynamicBassConfig.fromJson(cfg.toJson());
      expect(back.enabled, cfg.enabled);
      expect(back.strength, cfg.strength);
      expect(back.xLow, cfg.xLow);
      expect(back.xHigh, cfg.xHigh);
      expect(back.yLow, cfg.yLow);
      expect(back.yHigh, cfg.yHigh);
      expect(back.sideGainLow, cfg.sideGainLow);
      expect(back.sideGainHigh, cfg.sideGainHigh);
      expect(back.preset, cfg.preset);
    });

    test('builtinPresets are well-formed with unique ids', () {
      final presets = DynamicBassConfig.builtinPresets;
      expect(presets, hasLength(9));
      final ids = presets.map((p) => p.id).toSet();
      expect(ids, hasLength(9));
      for (final p in presets) {
        expect(p.id, inInclusiveRange(1, 9));
        expect(p.name, isNotEmpty);
        expect(p.xLow, greaterThan(0));
        expect(p.xHigh, greaterThan(p.xLow));
        expect(p.yLow, greaterThan(0));
        expect(p.yHigh, greaterThan(p.yLow));
        expect(p.sideGainLow, inInclusiveRange(0.0, 1.0));
        expect(p.sideGainHigh, inInclusiveRange(0.0, 1.0));
      }
    });
  });
}
