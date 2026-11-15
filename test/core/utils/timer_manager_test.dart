import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/utils/timer_manager.dart';

class _TestHost with TimerManager {}

void main() {
  test(
      'scheduleTimer and schedulePeriodic prune externally cancelled (!isActive) timers',
      () {
    final host = _TestHost();
    addTearDown(host.disposeTimers);

    for (var i = 0; i < 5; i++) {
      final oneShot = host.scheduleTimer(const Duration(seconds: 30), () {});
      oneShot.cancel();
      final periodic =
          host.schedulePeriodic(const Duration(seconds: 30), (_) {});
      periodic.cancel();
    }

    // Scheduling a one-shot prunes all previously cancelled timers.
    final activeOneShot =
        host.scheduleTimer(const Duration(seconds: 30), () {});
    expect(host.trackedTimerCountForTesting, 1);
    activeOneShot.cancel();

    // Scheduling a periodic prunes the cancelled one-shot too.
    final activePeriodic =
        host.schedulePeriodic(const Duration(seconds: 30), (_) {});
    expect(host.trackedTimerCountForTesting, 1);
    expect(host.activeTimerCount, 1);
    activePeriodic.cancel();
  });
}
