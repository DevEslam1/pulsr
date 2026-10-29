// test/domain/models/dsp_telemetry_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/models/dsp_telemetry.dart';

void main() {
  group('DspTelemetry.fromNativeList', () {
    test('parses the full 17-slot native payload', () {
      final list = <dynamic>[
        -3.5, // limiter GR
        0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, // dyn EQ (8)
        0.0, 0.0, 0.0, 0.0, // multiband (4)
        0.45, // rolling RTF
        3, // auto-degraded mask
        0.85, // weekly dose
        1.0, // safety attenuation active
      ];
      final telemetry = DspTelemetry.fromNativeList(list);

      expect(telemetry.limiterGrDb, -3.5);
      expect(telemetry.dynEqGrDb.length, 8);
      expect(telemetry.dynEqGrDb[1], -1.0);
      expect(telemetry.multibandGrDb.length, 4);
      expect(telemetry.rollingRtf, 0.45);
      expect(telemetry.autoDegradedStages, 3);
      expect(telemetry.weeklyDose, 0.85);
      expect(telemetry.safetyAttenuationActive, isTrue);
    });

    test('tolerates short, foreign and non-finite values', () {
      expect(DspTelemetry.fromNativeList(const [1.0, 2.0]),
          const DspTelemetry.zero());

      final list = <dynamic>[
        double.nan, 'not-a-number', double.infinity, null, 0, 0, 0, 0, 0, //
        double.nan, 0, 0, 0, double.nan, '7', double.infinity, 'true',
      ];
      final telemetry = DspTelemetry.fromNativeList(list);

      expect(telemetry.limiterGrDb, 0.0);
      expect(telemetry.dynEqGrDb.every((v) => v == 0.0), isTrue);
      expect(telemetry.multibandGrDb.every((v) => v == 0.0), isTrue);
      expect(telemetry.rollingRtf, 0.0);
      expect(telemetry.autoDegradedStages, 7);
      expect(telemetry.weeklyDose, 0.0);
      expect(telemetry.safetyAttenuationActive, isFalse);
    });

    test('clamps corrupt ranges instead of propagating them', () {
      final list = <dynamic>[
        99.0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 99.0, 0, 999.0, 1.0,
      ];
      final telemetry = DspTelemetry.fromNativeList(list);

      expect(telemetry.limiterGrDb, 0.0);
      expect(telemetry.rollingRtf, 10.0);
      expect(telemetry.weeklyDose, 100.0);
      expect(telemetry.rtfPercent, 999.0);
    });
  });
}
