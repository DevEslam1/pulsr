import 'dart:async';
import 'package:flutter/foundation.dart';

/// Mixin for stateful classes, widgets, or cubits that need tracked, safe timer management.
/// Automatically cancels all active timers when [cancelAllTimers] or [disposeTimers] is called.
mixin TimerManager {
  final List<Timer> _activeTimers = [];

  /// Returns the number of currently active timers.
  @visibleForTesting
  int get activeTimerCount => _activeTimers.where((t) => t.isActive).length;

  /// Registers and starts a one-shot [Timer].
  Timer scheduleTimer(Duration duration, void Function() callback) {
    late final Timer timer;
    timer = Timer(duration, () {
      _activeTimers.remove(timer);
      callback();
    });
    _activeTimers.add(timer);
    return timer;
  }

  /// Registers and starts a recurring [Timer.periodic].
  Timer schedulePeriodic(Duration period, void Function(Timer timer) callback) {
    final timer = Timer.periodic(period, callback);
    _activeTimers.add(timer);
    return timer;
  }

  /// Cancels a specific timer and removes it from tracking.
  void cancelTimer(Timer? timer) {
    if (timer == null) return;
    timer.cancel();
    _activeTimers.remove(timer);
  }

  /// Cancels all active timers.
  void cancelAllTimers() {
    for (final timer in _activeTimers) {
      timer.cancel();
    }
    _activeTimers.clear();
  }

  /// Disposes and cancels all timers.
  void disposeTimers() => cancelAllTimers();
}
