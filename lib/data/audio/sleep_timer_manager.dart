// lib/data/audio/sleep_timer_manager.dart
import 'dart:async';
import 'package:just_audio/just_audio.dart';

class SleepTimerManager {
  Timer? _sleepTimer;
  Timer? _sleepCountdownTimer;
  DateTime? _sleepTargetTime;
  int _sleepFadeToken = 0;

  final StreamController<Duration?> _sleepTimerRemainingSubject = StreamController<Duration?>.broadcast();
  Stream<Duration?> get sleepTimerRemainingStream => _sleepTimerRemainingSubject.stream;

  void startSleepTimer(
    Duration duration, {
    bool fadeOut = true,
    required Future<void> Function() onTimerExpired,
    required AudioPlayer Function() getActivePlayer,
  }) {
    cancelSleepTimer();
    final currentToken = ++_sleepFadeToken;
    _sleepTargetTime = DateTime.now().add(duration);
    _sleepTimerRemainingSubject.add(duration);

    _sleepCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_sleepTargetTime == null) {
        timer.cancel();
        return;
      }
      final remaining = _sleepTargetTime!.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        timer.cancel();
        _sleepTimerRemainingSubject.add(null);
      } else {
        _sleepTimerRemainingSubject.add(remaining);
      }
    });

    _sleepTimer = Timer(duration, () async {
      _sleepCountdownTimer?.cancel();
      _sleepCountdownTimer = null;
      _sleepTargetTime = null;
      _sleepTimerRemainingSubject.add(null);

      final player = getActivePlayer();
      if (fadeOut) {
        // Integer steps to eliminate floating point imprecision
        for (int i = 10; i >= 0; i--) {
          if (_sleepFadeToken != currentToken) return;
          await player.setVolume((i / 10.0).clamp(0.0, 1.0));
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }
      if (_sleepFadeToken != currentToken) return;
      await onTimerExpired();
      await player.setVolume(1.0);
    });
  }

  void startAbsoluteSleepTimer(
    DateTime stopTime, {
    bool fadeOut = true,
    required Future<void> Function() onTimerExpired,
    required AudioPlayer Function() getActivePlayer,
  }) {
    final now = DateTime.now();
    final difference = stopTime.isAfter(now)
        ? stopTime.difference(now)
        : stopTime.add(const Duration(days: 1)).difference(now);
    startSleepTimer(
      difference,
      fadeOut: fadeOut,
      onTimerExpired: onTimerExpired,
      getActivePlayer: getActivePlayer,
    );
  }

  void cancelSleepTimer() {
    _sleepFadeToken++;
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepCountdownTimer?.cancel();
    _sleepCountdownTimer = null;
    _sleepTargetTime = null;
    _sleepTimerRemainingSubject.add(null);
  }

  void dispose() {
    cancelSleepTimer();
    _sleepTimerRemainingSubject.close();
  }
}
