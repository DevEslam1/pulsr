import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulsr/core/services/theme_scheduler_service.dart';
import 'package:pulsr/features/settings/cubit/theme_schedule_controller.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ThemeScheduleController', () {
    test('setHours persists the window and updates the scheduler', () async {
      final scheduler = ThemeSchedulerService();
      final controller = ThemeScheduleController(
        scheduler: scheduler,
        isAutoEnabled: () => true,
        onNightChanged: (_) {},
      );
      await controller.init();

      await controller.setHours(start: 21, end: 7);

      expect(scheduler.startHour, 21);
      expect(scheduler.endHour, 7);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('setting_theme_schedule_start'), 21);
      expect(prefs.getInt('setting_theme_schedule_end'), 7);
      controller.dispose();
    });

    test('night changes reach the callback only when auto mode is on',
        () async {
      final scheduler = ThemeSchedulerService();
      var enabled = true;
      bool? lastNight;
      final controller = ThemeScheduleController(
        scheduler: scheduler,
        isAutoEnabled: () => enabled,
        onNightChanged: (v) => lastNight = v,
      );
      await controller.init();

      controller.start();
      // startScheduler checks immediately and emits through the stream.
      await Future<void>.delayed(Duration.zero);
      expect(lastNight, isNotNull);

      // Disabling stops propagation without throwing.
      enabled = false;
      lastNight = null;
      controller.start();
      await Future<void>.delayed(Duration.zero);
      expect(lastNight, isNull);

      controller.dispose();
    });

    test('init applies a previously persisted window', () async {
      SharedPreferences.setMockInitialValues({
        'setting_theme_schedule_start': 22,
        'setting_theme_schedule_end': 5,
      });
      final scheduler = ThemeSchedulerService();
      final controller = ThemeScheduleController(
        scheduler: scheduler,
        isAutoEnabled: () => false,
        onNightChanged: (_) {},
      );
      await controller.init();

      expect(scheduler.startHour, 22);
      expect(scheduler.endHour, 5);
      controller.dispose();
    });
  });
}
