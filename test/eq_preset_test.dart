// test/eq_preset_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/models/eq_preset.dart';

void main() {
  group('EqPreset 10-band migration', () {
    test('centerFrequencies are the 10 ISO octave centers', () {
      expect(EqPreset.centerFrequencies,
          [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]);
    });

    test('all built-in presets are 10-band', () {
      for (final preset in EqPreset.defaultPresets) {
        expect(preset.gains.length, 10,
            reason: '${preset.name} must have 10 bands');
      }
    });

    test('a length-10 list passes through unchanged', () {
      final tenBand = <double>[1, -2, 3, -4, 5, -6, 7, -8, 9, -10];
      expect(EqPreset.interpolateGains(tenBand), tenBand);
    });

    test('a legacy 5-band list up-samples to 10 values', () {
      final migrated = EqPreset.interpolateGains([6, 4, 1, 0, 0]);
      expect(migrated.length, 10);
    });

    test('migration preserves the endpoints of the legacy curve', () {
      // Legacy band 0 (60 Hz) and band 4 (14 kHz) bound the interpolation, so
      // the first/last target centers clamp to those source gains.
      final migrated = EqPreset.interpolateGains([6, 4, 1, 0, -3]);
      expect(migrated.first, closeTo(6.0, 0.001)); // 32 Hz <= 60 Hz -> clamps
      expect(migrated.last, closeTo(-3.0, 0.001)); // 16 kHz >= 14 kHz -> clamps
    });

    test('interpolation stays within the source gain range', () {
      final src = [6.0, 4.0, 1.0, 0.0, -3.0];
      final migrated = EqPreset.interpolateGains(src);
      final lo = src.reduce((a, b) => a < b ? a : b);
      final hi = src.reduce((a, b) => a > b ? a : b);
      for (final g in migrated) {
        expect(g, greaterThanOrEqualTo(lo - 0.001));
        expect(g, lessThanOrEqualTo(hi + 0.001));
      }
    });

    test('empty input yields 10 zeros', () {
      expect(EqPreset.interpolateGains([]), List<double>.filled(10, 0.0));
    });

    test('a single value fills all 10 bands', () {
      expect(EqPreset.interpolateGains([2.5]), List<double>.filled(10, 2.5));
    });
  });
}
