// test/data/audio/graphic_eq_q_test.dart
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/equalizer_manager.dart';

void main() {
  group('graphicEqQs', () {
    test('octave spacing (10-band) yields the classic ~1.414', () {
      final octave = <double>[
        31.25, 62.5, 125, 250, 500, 1000, 2000, 4000, 8000, 16000
      ];
      final qs = graphicEqQs(octave);
      expect(qs.length, octave.length);
      for (final q in qs) {
        expect(q, closeTo(1.414, 0.05));
      }
    });

    test('third-octave spacing yields a much higher Q (~4.3)', () {
      final ratio = math.pow(2.0, 1 / 3).toDouble();
      final bands = <double>[20.0];
      while (bands.last * ratio <= 20000) {
        bands.add(bands.last * ratio);
      }
      final qs = graphicEqQs(bands);
      // Interior bands should sit around 4.3 (not the 1.414 that caused
      // 3-6x overlap/overshoot and limiter pumping).
      final mid = qs[qs.length ~/ 2];
      expect(mid, closeTo(4.3, 0.3));
      expect(mid, greaterThan(3.0));
    });

    test('denser spacing gives a higher Q than sparser spacing', () {
      final ratio6 = math.pow(2.0, 1 / 6).toDouble();
      final sixth = <double>[20.0];
      while (sixth.last * ratio6 <= 20000) {
        sixth.add(sixth.last * ratio6);
      }
      final sixthQs = graphicEqQs(sixth);
      expect(sixthQs[sixthQs.length ~/ 2], greaterThan(7.0));
    });

    test('edge cases: empty, single, and degenerate frequencies are safe', () {
      expect(graphicEqQs(const []), isEmpty);
      expect(graphicEqQs(const [1000.0]).single, closeTo(1.414, 1e-9));
      // Non-increasing / zero frequencies must not produce NaN/Inf.
      for (final q in graphicEqQs(const [0.0, 1000.0, 1000.0])) {
        expect(q.isFinite, isTrue);
        expect(q, inInclusiveRange(0.3, 12.0));
      }
    });
  });
}
