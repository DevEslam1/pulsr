import 'dart:math' as math;

/// Maps the player's 0..1 volume slider onto a USB DAC's hardware attenuator.
///
/// Linear in dB across the DAC's real range: 0..1 maps directly onto
/// minDb..maxDb, 1.0 is the DAC's maximum (unity, bit-perfect), and exactly 0
/// drives the true minimum. This is the same mapping the UAC2 position API
/// uses, so the settings slider and the app volume show the same percentage.
/// No 0/-60 dB assumption; [rangeDb] exists only for a deliberately compressed
/// slider and is not used by the UAC2 path.
abstract final class UsbHardwareVolumeCurve {
  static double dbFor(
    double volume, {
    required double minDb,
    required double maxDb,
    double rangeDb = double.infinity,
  }) {
    if (!minDb.isFinite || !maxDb.isFinite || minDb > maxDb) return maxDb;
    final v = volume.isFinite ? volume.clamp(0.0, 1.0) : 1.0;
    if (v <= 0.0) return minDb;
    final floor = math.max(minDb, maxDb - rangeDb);
    if (v >= 1.0) return maxDb;
    return (maxDb - (1.0 - v) * (maxDb - floor)).clamp(floor, maxDb).toDouble();
  }

  /// Inverse of [dbFor]: converts a USB Feature Unit gain in dB back to `[0.0, 1.0]`.
  static double linearFor(
    double db, {
    required double minDb,
    required double maxDb,
    double rangeDb = double.infinity,
  }) {
    if (!db.isFinite || !minDb.isFinite || !maxDb.isFinite || minDb > maxDb) {
      return 1.0;
    }
    if (db >= maxDb) return 1.0;
    if (db <= minDb) return 0.0;
    final floor = math.max(minDb, maxDb - rangeDb);
    if (db <= floor) return 0.0;
    return ((db - floor) / (maxDb - floor)).clamp(0.0, 1.0);
  }
}
