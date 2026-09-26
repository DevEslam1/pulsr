import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/sound_dose_tracker_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SoundDoseTrackerService', () {
    late SoundDoseTrackerService tracker;

    setUp(() {
      tracker = SoundDoseTrackerService();
    });

    test('calculates correct dose for 40 hours at 80 dBA as exactly 100%', () async {
      tracker.recordSession(
        duration: const Duration(hours: 40),
        estimatedDba: 80.0,
      );

      final dose = await tracker.getWeeklyDosePercent();
      expect(dose, closeTo(100.0, 0.01));
    });

    test('halves allowed time every 3 dB (20 hours at 83 dBA = 100%)', () async {
      tracker.recordSession(
        duration: const Duration(hours: 20),
        estimatedDba: 83.0,
      );

      final dose = await tracker.getWeeklyDosePercent();
      expect(dose, closeTo(100.0, 0.01));
    });

    test('10 hours at 86 dBA = 100% dose', () async {
      tracker.recordSession(
        duration: const Duration(hours: 10),
        estimatedDba: 86.0,
      );

      final dose = await tracker.getWeeklyDosePercent();
      expect(dose, closeTo(100.0, 0.01));
    });

    test('triggers 80% warning and 100% limit warnings', () async {
      // 32 hours at 80 dBA = 80%
      tracker.recordSession(
        duration: const Duration(hours: 32),
        estimatedDba: 80.0,
      );

      var warning = await tracker.checkDoseWarning();
      expect(warning, 'WEEKLY_DOSE_WARNING_80_PERCENT');

      // Add 8 more hours at 80 dBA -> 100%
      tracker.recordSession(
        duration: const Duration(hours: 8),
        estimatedDba: 80.0,
      );

      warning = await tracker.checkDoseWarning();
      expect(warning, 'WEEKLY_DOSE_LIMIT_REACHED');
    });

    test('prunes sessions older than 7 days', () async {
      final eightDaysAgo = DateTime.now().subtract(const Duration(days: 8));
      tracker.recordSession(
        duration: const Duration(hours: 40),
        estimatedDba: 80.0,
        timestamp: eightDaysAgo,
      );

      final dose = await tracker.getWeeklyDosePercent();
      expect(dose, 0.0);
      expect(tracker.activeSessions.isEmpty, isTrue);
    });

    test('reset clears recorded sessions', () async {
      tracker.recordSession(
        duration: const Duration(hours: 10),
        estimatedDba: 80.0,
      );

      await tracker.resetDose();
      final dose = await tracker.getWeeklyDosePercent();
      expect(dose, 0.0);
    });
  });
}
