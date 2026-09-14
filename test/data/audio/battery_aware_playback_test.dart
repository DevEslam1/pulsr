// test/data/audio/battery_aware_playback_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/battery_aware_playback.dart';

void main() {
  group('BatteryAwarePlayback policy transitions', () {
    late List<String> events;
    late BatteryAwarePlayback policy;

    setUp(() {
      events = <String>[];
      policy = BatteryAwarePlayback(
        onLowPowerMode: ({required disableVisualizer, required reduceDsp}) {
          events.add('low:vis=$disableVisualizer,dsp=$reduceDsp');
        },
        onCriticalMode: ({required disableCrossfade, required minimalBuffer}) {
          events.add('critical:xfade=$disableCrossfade,buf=$minimalBuffer');
        },
        onRestoreNormal: () => events.add('restore'),
      );
    });

    test('normal -> lowPower fires only the low-power path', () {
      policy.onBatteryLevelChanged(40);
      expect(events, isEmpty);

      policy.onBatteryLevelChanged(10);
      expect(policy.currentLevel, BatteryOptimizationLevel.lowPower);
      expect(events, ['low:vis=true,dsp=true']);
    });

    test('normal -> critical fires critical then low-power', () {
      policy.onBatteryLevelChanged(3);
      expect(policy.currentLevel, BatteryOptimizationLevel.critical);
      expect(events, [
        'critical:xfade=true,buf=true',
        'low:vis=true,dsp=true',
      ]);
    });

    test('critical -> lowPower restores critical-only degradations (B-8)', () {
      policy.onBatteryLevelChanged(3);
      events.clear();

      policy.onBatteryLevelChanged(10);
      expect(policy.currentLevel, BatteryOptimizationLevel.lowPower);
      // Restore must fire on the way up, before low-power is re-applied.
      expect(events, ['restore', 'low:vis=true,dsp=true']);
    });

    test('lowPower -> normal restores normal', () {
      policy.onBatteryLevelChanged(10);
      events.clear();

      policy.onBatteryLevelChanged(60);
      expect(policy.currentLevel, BatteryOptimizationLevel.normal);
      expect(events, ['restore']);
    });

    test('critical -> normal restores normal directly', () {
      policy.onBatteryLevelChanged(3);
      events.clear();

      policy.onBatteryLevelChanged(60);
      expect(policy.currentLevel, BatteryOptimizationLevel.normal);
      expect(events, ['restore']);
    });

    test('repeated readings at the same level do not re-fire callbacks', () {
      policy.onBatteryLevelChanged(3);
      events.clear();

      policy.onBatteryLevelChanged(4);
      policy.onBatteryLevelChanged(3);
      expect(events, isEmpty);
      expect(policy.currentLevel, BatteryOptimizationLevel.critical);
    });

    test('15% is normal and 14% is low power (boundaries)', () {
      policy.onBatteryLevelChanged(15);
      expect(policy.currentLevel, BatteryOptimizationLevel.normal);
      policy.onBatteryLevelChanged(14);
      expect(policy.currentLevel, BatteryOptimizationLevel.lowPower);
      policy.onBatteryLevelChanged(5);
      expect(policy.currentLevel, BatteryOptimizationLevel.lowPower);
      policy.onBatteryLevelChanged(4);
      expect(policy.currentLevel, BatteryOptimizationLevel.critical);
    });
  });
}
