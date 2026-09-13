import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/models/eq_preset.dart';

void main() {
  group('EqPreset 64-band plan', () {
    test('iso64Frequencies has 64 log-spaced monotonic entries', () {
      final freqs = EqPreset.iso64Frequencies;
      expect(freqs.length, 64);
      expect(freqs.first, closeTo(20.0, 1e-9));
      expect(freqs.last, closeTo(20000.0, 1e-9));

      // Strictly ascending.
      for (var i = 1; i < freqs.length; i++) {
        expect(freqs[i], greaterThan(freqs[i - 1]));
      }

      // Constant log-spacing: every adjacent ratio is identical.
      final expectedRatio = math.pow(20000.0 / 20.0, 1 / 63).toDouble();
      for (var i = 1; i < freqs.length; i++) {
        expect(freqs[i] / freqs[i - 1], closeTo(expectedRatio, 1e-9));
      }

      // Every log step spans the same octave fraction.
      final expectedLogStep = math.log(20000.0 / 20.0) / 63;
      for (var i = 1; i < freqs.length; i++) {
        expect(
          math.log(freqs[i]) - math.log(freqs[i - 1]),
          closeTo(expectedLogStep, 1e-9),
        );
      }
    });

    test('interpolateGains maps 10 bands onto the 64-band plan', () {
      final source = List<double>.generate(10, (i) => i.toDouble());
      final out = EqPreset.interpolateGains(
        source,
        targetFrequencies: EqPreset.iso64Frequencies,
      );

      expect(out.length, 64);
      // 20 Hz is below the first 10-band center (32 Hz) and 20 kHz is above the
      // last (16 kHz), so both ends clamp to the source endpoints.
      expect(out.first, closeTo(source.first, 1e-9));
      expect(out.last, closeTo(source.last, 1e-9));
      for (var i = 1; i < out.length; i++) {
        expect(out[i], greaterThanOrEqualTo(out[i - 1] - 1e-9));
      }
    });

    test('interpolateGains maps 32 bands onto the 64-band plan', () {
      // iso32Frequencies is the 31-band 1/3-octave list (misnamed); build the
      // source from its actual centers so endpoints line up exactly.
      final srcFreqs = EqPreset.iso32Frequencies;
      final source =
          List<double>.generate(srcFreqs.length, (i) => i.toDouble());
      final out = EqPreset.interpolateGains(
        source,
        targetFrequencies: EqPreset.iso64Frequencies,
      );

      expect(out.length, 64);
      expect(out.first, closeTo(source.first, 1e-9));
      // 20 kHz is exactly iso32Frequencies.last, so the top lands on that gain.
      expect(out.last, closeTo(source.last, 1e-9));
      for (var i = 1; i < out.length; i++) {
        expect(out[i], greaterThanOrEqualTo(out[i - 1] - 1e-9));
      }
    });

    test('interpolateGains is log-linear between adjacent source bands', () {
      const target = [32.0, 40.0, 64.0];
      final out = EqPreset.interpolateGains(
        const [0.0, 1.0],
        targetFrequencies: target,
      );

      expect(out.length, 3);
      expect(out[0], closeTo(0.0, 1e-9));
      expect(out[2], closeTo(1.0, 1e-9));
      final t = (math.log(40.0) - math.log(32.0)) /
          (math.log(64.0) - math.log(32.0));
      expect(out[1], closeTo(t, 1e-9));
    });

    test('interpolateGains accepts a 64-band source onto 10/32-band targets',
        () {
      final source = List<double>.generate(64, (i) => (i % 13) - 6.0);

      final ten = EqPreset.interpolateGains(source);
      expect(ten.length, 10);

      final thirtyTwo = EqPreset.interpolateGains(
        source,
        targetFrequencies: EqPreset.iso32Frequencies,
      );
      expect(thirtyTwo.length, EqPreset.iso32Frequencies.length);
    });
  });
}
