import 'dart:async';
import 'package:injectable/injectable.dart';

@singleton
class ThemeSchedulerService {
  Timer? _timer;
  final StreamController<bool> _isNightSubject =
      StreamController<bool>.broadcast();
  int startHour = 19;
  int endHour = 6;

  Stream<bool> get isNightStream => _isNightSubject.stream;

  void updateScheduleHours({int start = 19, int end = 6}) {
    startHour = start;
    endHour = end;
  }

  void startScheduler(void Function(bool isNight) onThemeChange) {
    _timer?.cancel();
    _checkSchedule(onThemeChange);
    // Check every 15 minutes
    _timer = Timer.periodic(const Duration(minutes: 15), (_) {
      _checkSchedule(onThemeChange);
    });
  }

  void _checkSchedule(void Function(bool isNight) onThemeChange) {
    final now = DateTime.now();
    final bool isNight;
    if (startHour > endHour) {
      isNight = now.hour >= startHour || now.hour < endHour;
    } else {
      isNight = now.hour >= startHour && now.hour < endHour;
    }
    _isNightSubject.add(isNight);
    onThemeChange(isNight);
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _isNightSubject.close();
  }
}

