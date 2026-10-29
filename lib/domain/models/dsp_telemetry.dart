// lib/domain/models/dsp_telemetry.dart
import 'package:flutter/foundation.dart';

@immutable
class DspTelemetry {
  final double limiterGrDb;
  final List<double> dynEqGrDb;
  final List<double> multibandGrDb;
  final double rollingRtf;
  final int autoDegradedStages;
  final double weeklyDose;
  final bool safetyAttenuationActive;

  const DspTelemetry({
    required this.limiterGrDb,
    required this.dynEqGrDb,
    required this.multibandGrDb,
    required this.rollingRtf,
    required this.autoDegradedStages,
    this.weeklyDose = 0.0,
    this.safetyAttenuationActive = false,
  });

  const DspTelemetry.zero()
      : limiterGrDb = 0.0,
        dynEqGrDb = const [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
        multibandGrDb = const [0.0, 0.0, 0.0, 0.0],
        rollingRtf = 0.0,
        autoDegradedStages = 0,
        weeklyDose = 0.0,
        safetyAttenuationActive = false;

  /// Tolerant numeric reader: the platform channel is untyped at runtime, so a
  /// malformed/legacy payload must not throw (the cubit would treat it as a
  /// poll failure) and NaN/Infinity must not enter the UI state (NaN != NaN
  /// would make every later emit look changed).
  static double _readDouble(List<dynamic> list, int index) {
    if (index < 0 || index >= list.length) return 0.0;
    final value = list[index];
    if (value is num) {
      final d = value.toDouble();
      return d.isFinite ? d : 0.0;
    }
    if (value is String) {
      final d = double.tryParse(value);
      return (d != null && d.isFinite) ? d : 0.0;
    }
    return 0.0;
  }

  static int _readInt(List<dynamic> list, int index) {
    if (index < 0 || index >= list.length) return 0;
    final value = list[index];
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  factory DspTelemetry.fromNativeList(List<dynamic> list) {
    if (list.length < 15) {
      return const DspTelemetry.zero();
    }
    final limiter = _readDouble(list, 0).clamp(-60.0, 0.0).toDouble();
    final dynEq = List<double>.generate(8, (i) => _readDouble(list, 1 + i));
    final mb = List<double>.generate(4, (i) => _readDouble(list, 9 + i));
    // RTF above 1 means overload; keep it visible but bounded so a corrupt
    // value cannot break percent formatting. Dose is a 0..100 multiple of the
    // weekly threshold.
    final rtf = _readDouble(list, 13).clamp(0.0, 10.0).toDouble();
    final degraded = _readInt(list, 14);
    final dose = _readDouble(list, 15).clamp(0.0, 100.0).toDouble();
    final attenuation = _readDouble(list, 16) > 0.5;

    return DspTelemetry(
      limiterGrDb: limiter,
      dynEqGrDb: List.unmodifiable(dynEq),
      multibandGrDb: List.unmodifiable(mb),
      rollingRtf: rtf,
      autoDegradedStages: degraded,
      weeklyDose: dose,
      safetyAttenuationActive: attenuation,
    );
  }

  bool get isThrottling => rollingRtf > 0.85;
  bool get hasLimiterActive => limiterGrDb < -0.1;
  bool get isAutoDegraded => autoDegradedStages != 0;
  double get rtfPercent => (rollingRtf * 100.0).clamp(0.0, 999.0);
  double get weeklyDosePercent => (weeklyDose * 100.0).clamp(0.0, 999.0);
  bool get isDoseWarning => weeklyDose >= 0.8 && weeklyDose < 1.0;
  bool get isDoseExceeded => weeklyDose >= 1.0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DspTelemetry &&
          runtimeType == other.runtimeType &&
          limiterGrDb == other.limiterGrDb &&
          listEquals(dynEqGrDb, other.dynEqGrDb) &&
          listEquals(multibandGrDb, other.multibandGrDb) &&
          rollingRtf == other.rollingRtf &&
          autoDegradedStages == other.autoDegradedStages &&
          weeklyDose == other.weeklyDose &&
          safetyAttenuationActive == other.safetyAttenuationActive;

  @override
  int get hashCode => Object.hash(
        limiterGrDb,
        Object.hashAll(dynEqGrDb),
        Object.hashAll(multibandGrDb),
        rollingRtf,
        autoDegradedStages,
        weeklyDose,
        safetyAttenuationActive,
      );
}
