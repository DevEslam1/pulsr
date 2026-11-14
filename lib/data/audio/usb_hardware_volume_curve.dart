import 'dart:math' as math;

/// Maps the player's 0..1 volume slider onto a USB DAC's hardware attenuator.
///
/// Amplitude-linear (20*log10(v)), so 0.5 is -6 dB and 1.0 is the DAC's maximum
/// (unity, bit-perfect). The audible range is limited to [rangeDb] below the
/// maximum so the bottom of the slider isn't spent on inaudible attenuation;
/// exactly 0 drives the DAC's minimum (its mute / floor).
abstract final class UsbHardwareVolumeCurve {
  static double dbFor(
    double volume, {
    required double minDb,
    required double maxDb,
    double rangeDb = 60.0,
  }) {
    if (!minDb.isFinite || !maxDb.isFinite || minDb > maxDb) return maxDb;
    final v = volume.isFinite ? volume.clamp(0.0, 1.0) : 1.0;
    if (v <= 0.0) return minDb;
    final floor = math.max(minDb, maxDb - rangeDb);
    final db = maxDb + 20.0 * math.log(v) / math.ln10;
    return db.clamp(floor, maxDb).toDouble();
  }

  /// Inverse of [dbFor]: converts a USB Feature Unit gain in dB back to `[0.0, 1.0]`.
  static double linearFor(
    double db, {
    required double minDb,
    required double maxDb,
    double rangeDb = 60.0,
  }) {
    if (!db.isFinite || !minDb.isFinite || !maxDb.isFinite || minDb > maxDb) {
      return 1.0;
    }
    if (db >= maxDb) return 1.0;
    if (db <= minDb) return 0.0;
    final floor = math.max(minDb, maxDb - rangeDb);
    final clamped = db.clamp(floor, maxDb).toDouble();
    return math.pow(10.0, (clamped - maxDb) / 20.0).toDouble().clamp(0.0, 1.0);
  }
}
