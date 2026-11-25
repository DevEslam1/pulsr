// lib/data/audio/headphone_target_curve.dart
//
// Reference headphone targets as small immutable value types. They exist so
// the EQ / AutoEQ UI can plot a correction against a reference shape and so
// callers can evaluate "how far from target is this curve at frequency X"
// without pulling in the AutoEQ dataset tooling.
//
// Accuracy note: these are deliberately *approximate* anchors. Each anchor was
// sampled (and rounded to 0.1 dB) from AutoEQ's published target CSVs
// (https://github.com/jaakkopasanen/AutoEq/tree/master/targets), and values
// between anchors are log-frequency interpolations of those samples. They are
// suitable for display and normalisation reference only; they are not a
// measurement of any headphone and must not be presented as measurement-grade
// data.
import 'dart:math' as math;

/// One anchor of a [HeadphoneTargetCurve]: a frequency in Hz and its target
/// level in dB.
class HeadphoneTargetPoint {
  const HeadphoneTargetPoint(this.hz, this.db);

  /// Anchor frequency in Hz. Positive and finite for every bundled curve.
  final double hz;

  /// Target level in dB, relative to the curve's own 1 kHz anchor.
  final double db;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HeadphoneTargetPoint && hz == other.hz && db == other.db;

  @override
  int get hashCode => Object.hash(hz, db);

  @override
  String toString() => 'HeadphoneTargetPoint($hz Hz, $db dB)';
}

/// A named reference curve defined by [points], ascending in frequency.
///
/// [interpolateDbAt] is piecewise linear in log frequency, which is the
/// conventional way to read a target between octave-spaced anchors: a
/// geometric-mean frequency lands exactly halfway (in dB) between its
/// neighbours, while a linear-in-Hz midpoint does not.
class HeadphoneTargetCurve {
  const HeadphoneTargetCurve({
    required this.name,
    required this.points,
    this.description = '',
  });

  final String name;

  /// Short human-readable note, including the approximation caveat.
  final String description;

  /// Anchor points, ascending in [HeadphoneTargetPoint.hz].
  final List<HeadphoneTargetPoint> points;

  bool get isEmpty => points.isEmpty;

  /// Lowest anchor frequency in Hz (0 when [isEmpty]).
  double get minHz => points.isEmpty ? 0.0 : points.first.hz;

  /// Highest anchor frequency in Hz (0 when [isEmpty]).
  double get maxHz => points.isEmpty ? 0.0 : points.last.hz;

  /// Target level in dB at [hz], interpolated linearly in log frequency.
  ///
  /// Frequencies at or below [minHz] clamp to the first anchor; frequencies at
  /// or above [maxHz] clamp to the last anchor. Non-finite and non-positive
  /// inputs clamp to the first anchor rather than producing NaN.
  double interpolateDbAt(double hz) {
    if (points.isEmpty) return 0.0;
    if (hz.isNaN || hz <= 0 || hz <= points.first.hz) return points.first.db;
    if (hz >= points.last.hz) return points.last.db;

    final logHz = math.log(hz);
    for (var i = 0; i < points.length - 1; i++) {
      final lower = points[i];
      final upper = points[i + 1];
      if (hz < lower.hz) return lower.db;
      if (hz > upper.hz) continue;
      final logLower = math.log(lower.hz);
      final logUpper = math.log(upper.hz);
      if (logUpper <= logLower) return lower.db;
      final t = (logHz - logLower) / (logUpper - logLower);
      return lower.db + (upper.db - lower.db) * t;
    }
    return points.last.db;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! HeadphoneTargetCurve ||
        name != other.name ||
        description != other.description ||
        points.length != other.points.length) {
      return false;
    }
    for (var i = 0; i < points.length; i++) {
      if (points[i] != other.points[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(name, description, Object.hashAll(points));

  @override
  String toString() => 'HeadphoneTargetCurve($name, ${points.length} points)';

  /// Approximate Harman in-ear target (2019). Anchor values are rounded
  /// samples of AutoEQ's `Harman in-ear 2019.csv`; between anchors the curve is
  /// interpolated. Approximate — not a measurement claim.
  static const HeadphoneTargetCurve harmanInEar2019 = HeadphoneTargetCurve(
    name: 'Harman in-ear 2019',
    description: 'Approximate Harman in-ear target (2019); anchor points '
        'sampled from AutoEQ\'s published target CSV, not a measurement.',
    points: _harmanInEar2019,
  );

  /// Approximate Harman over-ear target (2018). Anchor values are rounded
  /// samples of AutoEQ's `Harman over-ear 2018.csv`. Approximate — not a
  /// measurement claim.
  static const HeadphoneTargetCurve harmanOverEar2018 = HeadphoneTargetCurve(
    name: 'Harman over-ear 2018',
    description: 'Approximate Harman over-ear target (2018); anchor points '
        'sampled from AutoEQ\'s published target CSV, not a measurement.',
    points: _harmanOverEar2018,
  );

  /// Approximate Harman over-ear target (2013). Anchor values are rounded
  /// samples of AutoEQ's `Harman over-ear 2013.csv`. Approximate — not a
  /// measurement claim.
  static const HeadphoneTargetCurve harmanOverEar2013 = HeadphoneTargetCurve(
    name: 'Harman over-ear 2013',
    description: 'Approximate Harman over-ear target (2013); anchor points '
        'sampled from AutoEQ\'s published target CSV, not a measurement.',
    points: _harmanOverEar2013,
  );

  /// The three bundled targets, in display order.
  static const List<HeadphoneTargetCurve> all = [
    harmanInEar2019,
    harmanOverEar2018,
    harmanOverEar2013,
  ];
}

/// Anchor sample of `targets/Harman in-ear 2019.csv` (0.1 dB rounding).
const List<HeadphoneTargetPoint> _harmanInEar2019 = [
  HeadphoneTargetPoint(20, 7.6),
  HeadphoneTargetPoint(30, 7.7),
  HeadphoneTargetPoint(50, 6.7),
  HeadphoneTargetPoint(100, 2.8),
  HeadphoneTargetPoint(150, 0.4),
  HeadphoneTargetPoint(200, -1.0),
  HeadphoneTargetPoint(300, -1.7),
  HeadphoneTargetPoint(500, -1.4),
  HeadphoneTargetPoint(700, -0.9),
  HeadphoneTargetPoint(1000, 0.0),
  HeadphoneTargetPoint(1500, 2.6),
  HeadphoneTargetPoint(2000, 5.8),
  HeadphoneTargetPoint(2500, 8.3),
  HeadphoneTargetPoint(3000, 9.3),
  HeadphoneTargetPoint(4000, 8.9),
  HeadphoneTargetPoint(5000, 7.7),
  HeadphoneTargetPoint(6000, 6.8),
  HeadphoneTargetPoint(8000, 3.6),
  HeadphoneTargetPoint(10000, -0.9),
  HeadphoneTargetPoint(12000, -4.6),
  HeadphoneTargetPoint(16000, -10.2),
  HeadphoneTargetPoint(20000, -20.6),
];

/// Anchor sample of `targets/Harman over-ear 2018.csv` (0.1 dB rounding).
const List<HeadphoneTargetPoint> _harmanOverEar2018 = [
  HeadphoneTargetPoint(20, 3.9),
  HeadphoneTargetPoint(30, 4.0),
  HeadphoneTargetPoint(50, 3.3),
  HeadphoneTargetPoint(100, 1.0),
  HeadphoneTargetPoint(150, -0.9),
  HeadphoneTargetPoint(200, -1.9),
  HeadphoneTargetPoint(300, -1.7),
  HeadphoneTargetPoint(500, -0.8),
  HeadphoneTargetPoint(700, -0.3),
  HeadphoneTargetPoint(1000, 0.0),
  HeadphoneTargetPoint(1500, 2.1),
  HeadphoneTargetPoint(2000, 5.3),
  HeadphoneTargetPoint(2500, 7.4),
  HeadphoneTargetPoint(3000, 8.3),
  HeadphoneTargetPoint(3500, 8.6),
  HeadphoneTargetPoint(4000, 8.2),
  HeadphoneTargetPoint(5000, 6.4),
  HeadphoneTargetPoint(6000, 5.1),
  HeadphoneTargetPoint(8000, 2.4),
  HeadphoneTargetPoint(10000, -0.8),
  HeadphoneTargetPoint(12000, -4.3),
  HeadphoneTargetPoint(16000, -9.2),
  HeadphoneTargetPoint(20000, -22.9),
];

/// Anchor sample of `targets/Harman over-ear 2013.csv` (0.1 dB rounding).
const List<HeadphoneTargetPoint> _harmanOverEar2013 = [
  HeadphoneTargetPoint(20, 1.5),
  HeadphoneTargetPoint(30, 1.3),
  HeadphoneTargetPoint(50, 1.3),
  HeadphoneTargetPoint(100, -0.4),
  HeadphoneTargetPoint(150, -1.8),
  HeadphoneTargetPoint(200, -2.4),
  HeadphoneTargetPoint(300, -2.0),
  HeadphoneTargetPoint(500, -1.2),
  HeadphoneTargetPoint(1000, 0.0),
  HeadphoneTargetPoint(1500, 2.1),
  HeadphoneTargetPoint(2000, 5.4),
  HeadphoneTargetPoint(2500, 8.1),
  HeadphoneTargetPoint(3000, 9.2),
  HeadphoneTargetPoint(3500, 8.5),
  HeadphoneTargetPoint(4000, 7.6),
  HeadphoneTargetPoint(5000, 5.4),
  HeadphoneTargetPoint(6000, 3.8),
  HeadphoneTargetPoint(8000, 0.9),
  HeadphoneTargetPoint(10000, -2.0),
  HeadphoneTargetPoint(12000, -5.6),
  HeadphoneTargetPoint(16000, -11.6),
  HeadphoneTargetPoint(20000, -16.6),
];
