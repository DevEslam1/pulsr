// test/eq_preset_test.dart
import 'dart:convert';
import 'dart:math' as math;
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

  // E-01: EQ preset export/import JSON round-trip + validation.
  group('EqPreset JSON export/import', () {
    test('round-trips name, gains, bassBoost, freqs and Q factors', () {
      final preset = EqPreset(
        name: 'My Custom',
        gains: const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
        bassBoost: 0.3,
        customFrequencies: const [
          31,
          62,
          125,
          250,
          500,
          1000,
          2000,
          4000,
          8000,
          16000,
        ],
        qFactors: const [1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
      );
      final decoded = EqPreset.fromJson(
          jsonDecode(jsonEncode(preset.toJson())) as Map<String, dynamic>);
      expect(decoded.name, 'My Custom');
      expect(decoded.gains, preset.gains);
      expect(decoded.bassBoost, 0.3);
      expect(decoded.customFrequencies, preset.customFrequencies);
      expect(decoded.qFactors, preset.qFactors);
    });

    test('missing fields fall back to safe defaults', () {
      final decoded = EqPreset.fromJson(const {});
      expect(decoded.name, 'Custom');
      expect(decoded.gains, isEmpty);
      expect(decoded.bassBoost, 0.0);
    });
  });

  group('EqPreset 32-band plan alignment', () {
    test('the 32-band plan is 32 entries; the ISO series is 31 (misnamed)', () {
      expect(EqPreset.iso32BandFrequencies, hasLength(32));
      expect(EqPreset.iso31Frequencies, hasLength(31));
      expect(EqPreset.iso32Frequencies, same(EqPreset.iso31Frequencies));
      expect(EqPreset.iso32BandFrequencies.first, closeTo(20.0, 1e-9));
      expect(EqPreset.iso32BandFrequencies.last, closeTo(20000.0, 1e-9));
    });

    test('a 32-band curve maps onto 10 bands using the 20 Hz–20 kHz plan', () {
      // Gains linear in log-frequency: correct log-linear interpolation must
      // reproduce log(f) exactly at every 10-band target center. The old code
      // treated the 32-entry source as _logSpread(32, target), shifting every
      // value (20 Hz was read as 32 Hz).
      final source = [
        for (final f in EqPreset.iso32BandFrequencies) math.log(f),
      ];
      final out = EqPreset.interpolateGains(source);

      expect(out, hasLength(EqPreset.centerFrequencies.length));
      for (var i = 0; i < EqPreset.centerFrequencies.length; i++) {
        expect(
          out[i],
          closeTo(math.log(EqPreset.centerFrequencies[i]), 1e-9),
          reason: 'band $i must align with its 32-band source frequency',
        );
      }
    });

    test('round-trips 32 -> 10 -> 32 within the source curve envelope', () {
      final source = List<double>.generate(32, (i) => i.toDouble());
      final ten = EqPreset.interpolateGains(source);
      final back = EqPreset.interpolateGains(
        ten,
        targetFrequencies: EqPreset.iso32BandFrequencies,
      );

      expect(back, hasLength(32));
      // Endpoints clamp to the 10-band endpoints (20 Hz < 32 Hz, 20 kHz >
      // 16 kHz), everything in between reconstructs the linear-in-log curve.
      expect(back.first, closeTo(ten.first, 1e-9));
      expect(back.last, closeTo(ten.last, 1e-9));
      for (var i = 1; i < source.length - 1; i++) {
        final freq = EqPreset.iso32BandFrequencies[i];
        if (freq < EqPreset.centerFrequencies.first ||
            freq > EqPreset.centerFrequencies.last) {
          continue;
        }
        expect((back[i] - source[i]).abs(), lessThan(1e-6),
            reason: 'band $i must round-trip closely');
      }
    });

    test('the 31-entry ISO source still maps with its own centers', () {
      final source = [
        for (final f in EqPreset.iso31Frequencies) math.log(f),
      ];
      final out = EqPreset.interpolateGains(source);

      for (var i = 0; i < EqPreset.centerFrequencies.length; i++) {
        final target = EqPreset.centerFrequencies[i];
        if (target < EqPreset.iso31Frequencies.first ||
            target > EqPreset.iso31Frequencies.last) {
          continue;
        }
        expect(out[i], closeTo(math.log(target), 1e-9));
      }
    });
  });

  group('EqPreset / EqBand value equality', () {
    test('structurally equal presets are equal with equal hashCodes', () {
      const a = EqPreset(
        name: 'X',
        gains: <double>[1, 2, 3],
        bandsMap: {
          10: <double>[1, 2]
        },
      );
      const b = EqPreset(
        name: 'X',
        gains: <double>[1, 2, 3],
        bandsMap: {
          10: <double>[1, 2]
        },
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different gains or bandsMap break equality', () {
      const base = EqPreset(name: 'X', gains: <double>[1, 2, 3]);
      expect(base,
          isNot(equals(const EqPreset(name: 'X', gains: <double>[1, 2, 4]))));
      expect(base,
          isNot(equals(const EqPreset(name: 'X', gains: <double>[1, 2]))));
      expect(
        const EqPreset(name: 'X', gains: <double>[
          0
        ], bandsMap: {
          10: <double>[1]
        }),
        isNot(equals(
          const EqPreset(name: 'X', gains: <double>[
            0
          ], bandsMap: {
            10: <double>[2]
          }),
        )),
      );
    });

    test('EqBand equality considers every field', () {
      const a = EqBand(index: 0, centerFrequency: 1000, gain: 3);
      expect(a, equals(const EqBand(index: 0, centerFrequency: 1000, gain: 3)));
      expect(
          a.hashCode,
          equals(
              const EqBand(index: 0, centerFrequency: 1000, gain: 3).hashCode));
      expect(
          a,
          isNot(
              equals(const EqBand(index: 1, centerFrequency: 1000, gain: 3))));
      expect(
          a,
          isNot(
              equals(const EqBand(index: 0, centerFrequency: 2000, gain: 3))));
      expect(
          a,
          isNot(
              equals(const EqBand(index: 0, centerFrequency: 1000, gain: 4))));
      expect(
          a,
          isNot(equals(
              const EqBand(index: 0, centerFrequency: 1000, gain: 3, q: 2))));
      expect(
          a,
          isNot(equals(const EqBand(
              index: 0, centerFrequency: 1000, gain: 3, filterType: 1))));
      expect(
          a,
          isNot(equals(const EqBand(
              index: 0, centerFrequency: 1000, gain: 3, enabled: false))));
    });
  });
}
