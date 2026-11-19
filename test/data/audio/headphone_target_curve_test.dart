// test/data/audio/headphone_target_curve_test.dart
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/headphone_target_curve.dart';

void main() {
  group('HeadphoneTargetCurve', () {
    test('bundles three labelled, ascending, approximate Harman targets', () {
      expect(HeadphoneTargetCurve.all.length, 3);
      expect(
        HeadphoneTargetCurve.all.map((curve) => curve.name).toSet().length,
        3,
      );

      for (final curve in HeadphoneTargetCurve.all) {
        expect(curve.name, isNotEmpty);
        expect(curve.description.toLowerCase(), contains('approximate'));
        expect(curve.description.toLowerCase(), contains('not a measurement'));
        expect(curve.points.length, greaterThanOrEqualTo(15));
        expect(curve.isEmpty, isFalse);
        expect(curve.minHz, 20);
        expect(curve.maxHz, 20000);
        for (var i = 1; i < curve.points.length; i++) {
          expect(
            curve.points[i].hz,
            greaterThan(curve.points[i - 1].hz),
            reason: '${curve.name} anchors must ascend',
          );
        }
      }
    });

    test('returns the anchor value exactly at every anchor', () {
      for (final curve in HeadphoneTargetCurve.all) {
        for (final point in curve.points) {
          expect(
            curve.interpolateDbAt(point.hz),
            closeTo(point.db, 1e-12),
            reason: '${curve.name} @ ${point.hz} Hz',
          );
        }
      }
    });

    test('interpolates linearly in log frequency between anchors', () {
      final curve = HeadphoneTargetCurve.harmanInEar2019;
      final lower = curve.points[9]; // 1000 Hz, 0.0 dB
      final upper = curve.points[10]; // 1500 Hz, 2.6 dB
      expect(lower.hz, 1000);
      expect(upper.hz, 1500);

      final geometricMid = math.sqrt(lower.hz * upper.hz);
      expect(
        curve.interpolateDbAt(geometricMid),
        closeTo((lower.db + upper.db) / 2, 1e-12),
      );

      // A linear-in-Hz midpoint sits at a different fraction of the segment,
      // which is exactly what log-frequency interpolation avoids.
      final linearMid = (lower.hz + upper.hz) / 2;
      expect(
        curve.interpolateDbAt(linearMid),
        isNot(closeTo((lower.db + upper.db) / 2, 0.05)),
      );
    });

    test('clamps below and above the anchor range', () {
      for (final curve in HeadphoneTargetCurve.all) {
        final first = curve.points.first.db;
        final last = curve.points.last.db;

        expect(curve.interpolateDbAt(1), first);
        expect(curve.interpolateDbAt(0), first);
        expect(curve.interpolateDbAt(-50), first);
        expect(curve.interpolateDbAt(double.negativeInfinity), first);
        expect(curve.interpolateDbAt(double.nan), first);

        expect(curve.interpolateDbAt(40000), last);
        expect(curve.interpolateDbAt(double.infinity), last);
      }
    });

    test('is monotone across monotone segments', () {
      final inEar = HeadphoneTargetCurve.harmanInEar2019;

      // 500 Hz -> 3 kHz is the rising ear-gain shelf.
      var previous = inEar.interpolateDbAt(500);
      for (var hz = 520.0; hz <= 3000; hz += 20) {
        final value = inEar.interpolateDbAt(hz);
        expect(value, greaterThanOrEqualTo(previous - 1e-9),
            reason: 'in-ear should rise at $hz Hz');
        previous = value;
      }

      // 4 kHz -> 20 kHz is the treble fall-off.
      previous = inEar.interpolateDbAt(4000);
      for (var hz = 4100.0; hz <= 20000; hz += 100) {
        final value = inEar.interpolateDbAt(hz);
        expect(value, lessThanOrEqualTo(previous + 1e-9),
            reason: 'in-ear should fall at $hz Hz');
        previous = value;
      }

      // Over-ear 2018 recovers monotonically from its 200 Hz dip to 1 kHz.
      final overEar = HeadphoneTargetCurve.harmanOverEar2018;
      previous = overEar.interpolateDbAt(200);
      for (var hz = 220.0; hz <= 1000; hz += 20) {
        final value = overEar.interpolateDbAt(hz);
        expect(value, greaterThanOrEqualTo(previous - 1e-9),
            reason: 'over-ear 2018 should rise at $hz Hz');
        previous = value;
      }

      // Over-ear 2013 rises from its low-mid dip to 1 kHz as well.
      final overEar2013 = HeadphoneTargetCurve.harmanOverEar2013;
      previous = overEar2013.interpolateDbAt(300);
      for (var hz = 320.0; hz <= 1000; hz += 20) {
        final value = overEar2013.interpolateDbAt(hz);
        expect(value, greaterThanOrEqualTo(previous - 1e-9),
            reason: 'over-ear 2013 should rise at $hz Hz');
        previous = value;
      }
    });

    test('every bundled curve is normalised to 0 dB at 1 kHz', () {
      for (final curve in HeadphoneTargetCurve.all) {
        expect(curve.interpolateDbAt(1000), 0.0, reason: curve.name);
      }
    });

    test('an empty curve is inert rather than throwing', () {
      const empty = HeadphoneTargetCurve(name: 'empty', points: []);

      expect(empty.isEmpty, isTrue);
      expect(empty.minHz, 0);
      expect(empty.maxHz, 0);
      expect(empty.interpolateDbAt(1000), 0.0);
      expect(empty.interpolateDbAt(double.nan), 0.0);
    });

    test('value equality compares name, description and points', () {
      const point = HeadphoneTargetPoint(1000, 0);
      const a = HeadphoneTargetCurve(
        name: 'test',
        description: 'd',
        points: [point, HeadphoneTargetPoint(2000, 3)],
      );
      const b = HeadphoneTargetCurve(
        name: 'test',
        description: 'd',
        points: [point, HeadphoneTargetPoint(2000, 3)],
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.interpolateDbAt(1000), 0);
      expect(a.interpolateDbAt(2000), 3);
      expect(
        a,
        isNot(const HeadphoneTargetCurve(name: 'test', points: [point])),
      );
      expect(point.toString(), contains('1000'));
    });
  });
}
