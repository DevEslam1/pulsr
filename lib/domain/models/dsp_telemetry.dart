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

  factory DspTelemetry.fromNativeList(List<dynamic> list) {
    if (list.length < 15) {
      return const DspTelemetry.zero();
    }
    final limiter = (list[0] as num?)?.toDouble() ?? 0.0;
    final dynEq = List<double>.generate(8, (i) => (list[1 + i] as num?)?.toDouble() ?? 0.0);
    final mb = List<double>.generate(4, (i) => (list[9 + i] as num?)?.toDouble() ?? 0.0);
    final rtf = (list[13] as num?)?.toDouble() ?? 0.0;
    final degraded = (list[14] as num?)?.toInt() ?? 0;
    final dose = list.length >= 16 ? ((list[15] as num?)?.toDouble() ?? 0.0) : 0.0;
    final attenuation = list.length >= 17 ? (((list[16] as num?)?.toDouble() ?? 0.0) > 0.5) : false;

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
