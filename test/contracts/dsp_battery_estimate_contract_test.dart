import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/models/dsp_battery_estimate.dart';

void main() {
  test('DspBatteryEstimate matches golden contract fixture', () {
    final file = File('test/fixtures/contracts/dsp_battery_estimate.json');
    expect(file.existsSync(), isTrue, reason: 'Fixture file must exist');

    final jsonMap = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final estimate = DspBatteryEstimate.fromMap(jsonMap);

    expect(estimate.estimatedMahPerHour, 93.5);
    expect(estimate.lowPowerBypassActive, isFalse);
    expect(estimate.activeStageCount, 3);
    expect(estimate.stageBreakdown['reverb'], 12.0);
    expect(estimate.stageBreakdown['saturation'], 3.5);
    expect(estimate.stageBreakdown['equalizer'], 3.0);
    expect(estimate.stagePowerSpecs['reverb'], 12.0);
    expect(estimate.stagePowerSpecs['hrtf'], 14.0);
  });
}
