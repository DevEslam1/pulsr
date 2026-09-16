// lib/features/settings/cubit/theme_schedule_controller.dart
import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/theme_scheduler_service.dart';
import '../../../core/utils/error_logger.dart';

/// Owns the automatic day/night theme schedule on behalf of [SettingsCubit]
/// (god-object split): scheduler lifecycle, the persisted dark-hours window,
/// and the night→theme callback.
///
/// The cubit stays the single emitter of [SettingsState]; this controller
/// never touches state directly — it asks [isAutoEnabled] and reports night
/// changes through [onNightChanged]. All prefs keys for the window live here.
class ThemeScheduleController {
  static const String keyScheduleStart = 'setting_theme_schedule_start';
  static const String keyScheduleEnd = 'setting_theme_schedule_end';

  final ThemeSchedulerService _scheduler;
  final bool Function() _isAutoEnabled;
  final void Function(bool isNight) _onNightChanged;
  StreamSubscription<bool>? _nightSub;
  bool _disposed = false;

  ThemeScheduleController({
    ThemeSchedulerService? scheduler,
    required bool Function() isAutoEnabled,
    required void Function(bool isNight) onNightChanged,
  })  : _scheduler = scheduler ?? ThemeSchedulerService(),
        _isAutoEnabled = isAutoEnabled,
        _onNightChanged = onNightChanged;

  /// Resolves the persisted window into the scheduler and subscribes to night
  /// changes. Safe to call once from the cubit constructor.
  Future<void> init() async {
    try {
      await _applyHoursFromPrefs();
      _nightSub = _scheduler.isNightStream.listen((isNight) {
        if (_disposed) return;
        if (!_isAutoEnabled()) return;
        _onNightChanged(isNight);
      });
    } catch (e, st) {
      ErrorLogger.log('Failed to start theme scheduler',
          error: e, stackTrace: st, category: 'ThemeScheduleController');
    }
  }

  /// Starts the periodic check. Only ever called when the preference is on,
  /// so installs that never opt in carry no timer.
  void start() {
    try {
      if (_disposed || !_isAutoEnabled()) return;
      _scheduler.startScheduler((_) {});
    } catch (e, st) {
      ErrorLogger.log('Failed to start theme schedule check',
          error: e, stackTrace: st, category: 'ThemeScheduleController');
    }
  }

  /// Cancels the periodic check without tearing down the stream, so the
  /// scheduler can be started again later.
  void stop() {
    try {
      _scheduler.stopScheduler();
    } catch (_) {}
  }

  /// Persists and applies a new dark-hours window. Restarts the scheduler so
  /// the change is reflected immediately when scheduled theming is on.
  Future<void> setHours({required int start, required int end}) async {
    final s = start.clamp(0, 23);
    final e = end.clamp(0, 23);
    _scheduler.updateScheduleHours(start: s, end: e);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(keyScheduleStart, s);
      await prefs.setInt(keyScheduleEnd, e);
    } catch (err, st) {
      ErrorLogger.log('Failed to persist theme schedule hours',
          error: err, stackTrace: st, category: 'ThemeScheduleController');
    }
    if (_isAutoEnabled()) this.start();
  }

  /// Loads the persisted dark-hours window into the scheduler singleton so a
  /// cold start with scheduled theming enabled uses the user's chosen window
  /// rather than the 19:00–06:00 default.
  Future<void> _applyHoursFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final start = prefs.getInt(keyScheduleStart) ?? _scheduler.startHour;
      final end = prefs.getInt(keyScheduleEnd) ?? _scheduler.endHour;
      _scheduler.updateScheduleHours(start: start, end: end);
    } catch (e, st) {
      ErrorLogger.log('Failed to apply persisted theme schedule hours',
          error: e, stackTrace: st, category: 'ThemeScheduleController');
    }
  }

  void dispose() {
    _disposed = true;
    _nightSub?.cancel();
    _nightSub = null;
    stop();
  }
}
