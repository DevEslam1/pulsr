import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/crossfade_manager.dart';

/// Focused invariants for [CrossfadeManager.evaluateSumSafeGainPair], the
/// dual-player overlap path: the raw equal-power pair sums to √2 at the
/// midpoint (hard-clips the AudioFlinger mixer), so the sum-safe variant
/// must guarantee `old + new <= ceiling` everywhere while keeping the
/// endpoints bit-exact.
void main() {
  group('evaluateSumSafeGainPair invariants', () {
    test('endpoints are exact for every curve', () {
      final mgr = CrossfadeManager();
      for (final curve in CrossfadeCurve.values) {
        mgr.curve = curve;
        final (o0, n0) = mgr.evaluateSumSafeGainPair(0.0);
        final (o1, n1) = mgr.evaluateSumSafeGainPair(1.0);
        expect(o0, closeTo(1.0, 1e-9), reason: '$curve f=0 old');
        expect(n0, closeTo(0.0, 1e-9), reason: '$curve f=0 new');
        expect(o1, closeTo(0.0, 1e-9), reason: '$curve f=1 old');
        expect(n1, closeTo(1.0, 1e-9), reason: '$curve f=1 new');
      }
    });

    test('summed gains never exceed the ceiling on any curve', () {
      final mgr = CrossfadeManager();
      for (final curve in CrossfadeCurve.values) {
        mgr.curve = curve;
        for (var i = 0; i <= 200; i++) {
          final (o, n) = mgr.evaluateSumSafeGainPair(i / 200);
          expect(o + n, lessThanOrEqualTo(1.0 + 1e-9),
              reason: '$curve f=${i / 200}');
          expect(o, greaterThanOrEqualTo(0.0));
          expect(n, greaterThanOrEqualTo(0.0));
        }
      }
    });

    test('equal-power midpoint is scaled by k = ceiling / sum', () {
      final mgr = CrossfadeManager()..curve = CrossfadeCurve.equalPower;
      final (rawO, rawN) = mgr.evaluateGainPair(0.5);
      // cos(π/4) == sin(π/4): raw pair sums to √2.
      expect(rawO + rawN, closeTo(math.sqrt2, 1e-9));
      final (safeO, safeN) = mgr.evaluateSumSafeGainPair(0.5);
      expect(safeO + safeN, closeTo(1.0, 1e-9));
      expect(safeO, closeTo(rawO / math.sqrt2, 1e-9));
      expect(safeN, closeTo(rawN / math.sqrt2, 1e-9));
    });

    test('custom ceiling is honored', () {
      final mgr = CrossfadeManager()..curve = CrossfadeCurve.equalPower;
      for (var i = 0; i <= 100; i++) {
        final (o, n) =
            mgr.evaluateSumSafeGainPair(i / 100, sumCeiling: 0.8);
        expect(o + n, lessThanOrEqualTo(0.8 + 1e-9));
      }
    });

    test('repeat-one linear pairs pass through unscaled', () {
      final mgr = CrossfadeManager()..curve = CrossfadeCurve.linear;
      final (o, n) = mgr.evaluateSumSafeGainPair(0.5, isRepeatOne: true);
      expect(o, 0.5);
      expect(n, 0.5);
    });
  });
}
