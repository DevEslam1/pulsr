// test/features/system_behavior/system_behavior_volume_test.dart
//
// Volume-key stepping: the linear and logarithmic tapers must both clamp at the
// rails, move exactly one step, and round-trip so a double press that goes up
// then down does not drift.

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/system_behavior/system_behavior_policy.dart';
import 'package:pulsr/features/system_behavior/system_behavior_settings.dart';

const SystemBehaviorSettingsSnapshot _linear = SystemBehaviorSettingsSnapshot(
  softwareVolumeCurve: SoftwareVolumeCurve.linear,
  volumeStepPercent: 5,
);

const SystemBehaviorSettingsSnapshot _logarithmic =
    SystemBehaviorSettingsSnapshot(
  softwareVolumeCurve: SoftwareVolumeCurve.logarithmic,
  volumeStepPercent: 5,
);

void main() {
  group('linear taper', () {
    test('one step up and one step down move by the configured percent', () {
      expect(
        nextVolume(current: 0.5, direction: 1, settings: _linear),
        closeTo(0.55, 1e-12),
      );
      expect(
        nextVolume(current: 0.5, direction: -1, settings: _linear),
        closeTo(0.45, 1e-12),
      );
    });

    test('the step size follows the setting', () {
      const SystemBehaviorSettingsSnapshot ten =
          SystemBehaviorSettingsSnapshot(volumeStepPercent: 10);
      const SystemBehaviorSettingsSnapshot two =
          SystemBehaviorSettingsSnapshot(volumeStepPercent: 2);
      expect(
        nextVolume(current: 0.2, direction: 1, settings: ten),
        closeTo(0.3, 1e-12),
      );
      expect(
        nextVolume(current: 0.2, direction: 1, settings: two),
        closeTo(0.22, 1e-12),
      );
    });

    test('the rails are exact', () {
      expect(nextVolume(current: 1, direction: 1, settings: _linear), 1.0);
      expect(nextVolume(current: 0.98, direction: 1, settings: _linear), 1.0);
      expect(nextVolume(current: 0, direction: -1, settings: _linear), 0.0);
      expect(nextVolume(current: 0.01, direction: -1, settings: _linear), 0.0);
    });

    test('direction zero and garbage inputs are safe', () {
      expect(
        nextVolume(current: 0.42, direction: 0, settings: _linear),
        0.42,
      );
      expect(
        nextVolume(current: double.nan, direction: 1, settings: _linear),
        closeTo(0.05, 1e-12),
      );
      expect(
        nextVolume(current: double.infinity, direction: -1, settings: _linear),
        0.0,
        reason: 'a non-finite level is treated as silence, never as full scale',
      );
      expect(
        nextVolume(current: 3, direction: -1, settings: _linear),
        closeTo(0.95, 1e-12),
      );
    });
  });

  group('logarithmic taper', () {
    test('perceptual level and gain are inverse at the anchor points', () {
      expect(perceptualLevel(0), 0.0);
      expect(perceptualLevel(0.25), 0.5);
      expect(perceptualLevel(1), 1.0);
      expect(gainForPerceptualLevel(0), 0.0);
      expect(gainForPerceptualLevel(0.5), 0.25);
      expect(gainForPerceptualLevel(1), 1.0);
    });

    test('one step moves the perceived level, not the gain', () {
      // sqrt(0.25) = 0.5; +0.05 -> 0.55; 0.55^2 = 0.3025.
      expect(
        nextVolume(current: 0.25, direction: 1, settings: _logarithmic),
        closeTo(0.3025, 1e-12),
      );
      // 0.45^2 = 0.2025.
      expect(
        nextVolume(current: 0.25, direction: -1, settings: _logarithmic),
        closeTo(0.2025, 1e-12),
      );
      // From silence the first step is deliberately quiet: 0.05^2 = 0.0025.
      expect(
        nextVolume(current: 0, direction: 1, settings: _logarithmic),
        closeTo(0.0025, 1e-12),
      );
    });

    test('the rails are exact', () {
      expect(nextVolume(current: 1, direction: 1, settings: _logarithmic), 1.0);
      expect(
          nextVolume(current: 0, direction: -1, settings: _logarithmic), 0.0);
      expect(
        nextVolume(current: 0.999, direction: 1, settings: _logarithmic),
        1.0,
      );
    });

    test('up then down returns to the level it started from', () {
      for (final double start in <double>[0.05, 0.25, 0.5, 0.8]) {
        final double up =
            nextVolume(current: start, direction: 1, settings: _logarithmic);
        final double back =
            nextVolume(current: up, direction: -1, settings: _logarithmic);
        expect(back, closeTo(start, 1e-12), reason: 'start $start');
      }
    });

    test(
        'the taper keeps gain steps small at low levels and large at high ones',
        () {
      const double top = 0.8;
      final double logTop =
          nextVolume(current: top, direction: 1, settings: _logarithmic);
      final double linearTop =
          nextVolume(current: top, direction: 1, settings: _linear);
      expect(logTop - top, greaterThan(linearTop - top));

      const double bottom = 0.01;
      final double logBottom =
          nextVolume(current: bottom, direction: 1, settings: _logarithmic);
      final double linearBottom =
          nextVolume(current: bottom, direction: 1, settings: _linear);
      expect(logBottom - bottom, lessThan(linearBottom - bottom));
    });

    test('garbage levels do not produce NaN', () {
      expect(perceptualLevel(double.nan), 0.0);
      expect(perceptualLevel(-1), 0.0);
      expect(gainForPerceptualLevel(double.nan), 0.0);
      expect(gainForPerceptualLevel(-1), 0.0);
      expect(gainForPerceptualLevel(2), 1.0);
      expect(
        nextVolume(current: double.nan, direction: 1, settings: _logarithmic)
            .isNaN,
        isFalse,
      );
    });
  });

  test('every curve and step keeps the volume inside 0..1', () {
    for (final SoftwareVolumeCurve curve in SoftwareVolumeCurve.values) {
      for (final int step in <int>[2, 5, 10]) {
        for (final int direction in <int>[-1, 1]) {
          for (int i = 0; i <= 100; i += 1) {
            final SystemBehaviorSettingsSnapshot settings =
                SystemBehaviorSettingsSnapshot(
              softwareVolumeCurve: curve,
              volumeStepPercent: step,
            );
            final double result = nextVolume(
              current: i / 100,
              direction: direction,
              settings: settings,
            );
            expect(result.isFinite, isTrue);
            expect(result, inInclusiveRange(0, 1));
          }
        }
      }
    }
  });
}
