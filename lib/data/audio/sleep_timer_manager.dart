// lib/data/audio/sleep_timer_manager.dart
import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/prefs_keys.dart';
import '../../core/utils/error_logger.dart';

class SleepTimerManager {
  Timer? _sleepTimer;
  Timer? _sleepCountdownTimer;
  DateTime? _sleepTargetTime;
  int _sleepFadeToken = 0;

  final StreamController<Duration?> _sleepTimerRemainingSubject =
      StreamController<Duration?>.broadcast();
  Stream<Duration?> get sleepTimerRemainingStream =>
      _sleepTimerRemainingSubject.stream;

  double? _preFadeVolume;
  AudioPlayer Function()? _lastPlayerGetter;

  void startSleepTimer(
    Duration duration, {
    bool fadeOut = true,
    required Future<void> Function() onTimerExpired,
    required AudioPlayer Function() getActivePlayer,
  }) {
    cancelSleepTimer();
    final currentToken = ++_sleepFadeToken;
    _lastPlayerGetter = getActivePlayer;
    final target = DateTime.now().add(duration);
    _sleepTargetTime = target;
    _sleepTimerRemainingSubject.add(duration);

    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt(PrefsKeys.sleepTimerTarget, target.millisecondsSinceEpoch);
    }).catchError((e, st) {
      ErrorLogger.log('Failed to persist sleep timer target',
          error: e, stackTrace: st, category: 'SleepTimer');
    });

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

      SharedPreferences.getInstance().then((prefs) {
        prefs.remove(PrefsKeys.sleepTimerTarget);
      }).catchError((_) {});

      final player = getActivePlayer();
      _preFadeVolume = player.volume;

      // Only perform audio fade out if the player is actively playing
      if (fadeOut && player.playing) {
        final baseVol = _preFadeVolume ?? 1.0;
        for (int i = 10; i >= 0; i--) {
          if (_sleepFadeToken != currentToken) return;
          try {
            await player.setVolume(((i / 10.0) * baseVol).clamp(0.0, 1.0));
          } catch (e, st) {
            ErrorLogger.log('Error adjusting volume during sleep timer fade out',
                error: e, stackTrace: st, category: 'SleepTimer');
            break;
          }
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }

      if (_sleepFadeToken != currentToken) return;
      try {
        await onTimerExpired();
      } catch (e, st) {
        ErrorLogger.log('Error triggering sleep timer expiration callback',
            error: e, stackTrace: st, category: 'SleepTimer');
      }

      try {
        await player.setVolume(_preFadeVolume ?? 1.0);
      } catch (e, st) {
        ErrorLogger.log('Error restoring volume after sleep timer expiry',
            error: e, stackTrace: st, category: 'SleepTimer');
      }
      _preFadeVolume = null;
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

    SharedPreferences.getInstance().then((prefs) {
      prefs.remove(PrefsKeys.sleepTimerTarget);
    }).catchError((_) {});

    if (_preFadeVolume != null && _lastPlayerGetter != null) {
      try {
        _lastPlayerGetter!().setVolume(_preFadeVolume!);
      } catch (e, st) {
        ErrorLogger.log(
            'Error restoring player volume upon canceling sleep timer',
            error: e,
            stackTrace: st,
            category: 'SleepTimer');
      }
      _preFadeVolume = null;
    }
  }

  void dispose() {
    cancelSleepTimer();
    _sleepTimerRemainingSubject.close();
  }
}
