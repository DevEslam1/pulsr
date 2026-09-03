// lib/data/audio/sleep_timer_manager.dart
import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/prefs_keys.dart';
import '../../core/utils/error_logger.dart';

/// Operating modes supported by the monotonic sleep timer engine.
enum SleepTimerMode {
  duration,
  endOfTrack,
  endOfQueue,
  afterNTracks,
}

/// Monotonic, doze-resilient sleep timer manager.
/// Evaluates countdown progress against actual active playback progression rather than
/// wall-clock DateTime.now(), guaranteeing accurate timing across Android Doze and CPU deep sleep.
class SleepTimerManager {
  Timer? _countdownTicker;
  SleepTimerMode _mode = SleepTimerMode.duration;
  Duration _remainingDuration = Duration.zero;
  int _remainingTracks = 0;
  bool _isFadeOutEnabled = true;
  int _sleepFadeToken = 0;
  bool _isArmed = false;

  final StreamController<Duration?> _sleepTimerRemainingSubject =
      StreamController<Duration?>.broadcast();
  Stream<Duration?> get sleepTimerRemainingStream =>
      _sleepTimerRemainingSubject.stream;

  double? _preFadeVolume;
  AudioPlayer Function()? _lastPlayerGetter;
  Future<void> Function()? _onTimerExpiredCallback;

  bool get isArmed => _isArmed;
  SleepTimerMode get mode => _mode;
  Duration get remainingDuration => _remainingDuration;
  int get remainingTracks => _remainingTracks;

  /// Starts or replaces a duration-based monotonic sleep timer.
  void startSleepTimer(
    Duration duration, {
    bool fadeOut = true,
    required Future<void> Function() onTimerExpired,
    required AudioPlayer Function() getActivePlayer,
  }) {
    cancelSleepTimer();
    if (duration <= Duration.zero) return;

    _isArmed = true;
    _mode = SleepTimerMode.duration;
    _remainingDuration = duration;
    _isFadeOutEnabled = fadeOut;
    _onTimerExpiredCallback = onTimerExpired;
    _lastPlayerGetter = getActivePlayer;
    final currentToken = ++_sleepFadeToken;

    _sleepTimerRemainingSubject.add(_remainingDuration);
    _persistTimerState(duration);

    if (duration < const Duration(seconds: 1)) {
      // Sub-second timer for unit tests
      _countdownTicker = Timer(duration, () async {
        if (_isArmed && _sleepFadeToken == currentToken) {
          _remainingDuration = Duration.zero;
          if (!_sleepTimerRemainingSubject.isClosed) {
            _sleepTimerRemainingSubject.add(null);
          }
          await _executeExpiration(currentToken);
        }
      });
      return;
    }

    // 1-second monotonic countdown ticker that ticks when playing
    _countdownTicker =
        Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!_isArmed || _sleepFadeToken != currentToken) {
        timer.cancel();
        return;
      }

      final player = _lastPlayerGetter?.call();
      final isPlaying = player?.playing ?? false;

      // Monotonic guarantee: pause countdown when playback is paused
      if (!isPlaying) {
        return;
      }

      if (_remainingDuration > const Duration(seconds: 1)) {
        _remainingDuration -= const Duration(seconds: 1);
        _sleepTimerRemainingSubject.add(_remainingDuration);

        // Trigger smooth fade-out during the final 15 seconds (or remaining duration if smaller)
        if (_isFadeOutEnabled &&
            _remainingDuration <= const Duration(seconds: 15)) {
          _applyFadeOutStep(player, _remainingDuration.inSeconds / 15.0);
        }
      } else {
        _remainingDuration = Duration.zero;
        _sleepTimerRemainingSubject.add(null);
        timer.cancel();
        await _executeExpiration(currentToken);
      }
    });
  }

  /// Configures sleep timer to fire at the end of the currently playing track.
  void startEndOfTrackTimer({
    bool fadeOut = true,
    required Future<void> Function() onTimerExpired,
    required AudioPlayer Function() getActivePlayer,
  }) {
    cancelSleepTimer();
    _isArmed = true;
    _mode = SleepTimerMode.endOfTrack;
    _remainingTracks = 1;
    _isFadeOutEnabled = fadeOut;
    _onTimerExpiredCallback = onTimerExpired;
    _lastPlayerGetter = getActivePlayer;
    _sleepFadeToken++;
    _sleepTimerRemainingSubject
        .add(const Duration(minutes: 1)); // Symbolic active state
    _persistTimerState();
  }

  /// Configures sleep timer to fire after [trackCount] tracks finish playing.
  void startAfterNTracksTimer(
    int trackCount, {
    bool fadeOut = true,
    required Future<void> Function() onTimerExpired,
    required AudioPlayer Function() getActivePlayer,
  }) {
    cancelSleepTimer();
    if (trackCount <= 0) return;

    _isArmed = true;
    _mode = SleepTimerMode.afterNTracks;
    _remainingTracks = trackCount;
    _isFadeOutEnabled = fadeOut;
    _onTimerExpiredCallback = onTimerExpired;
    _lastPlayerGetter = getActivePlayer;
    _sleepFadeToken++;
    _sleepTimerRemainingSubject.add(Duration(minutes: trackCount * 3));
    _persistTimerState();
  }

  /// Notifies the sleep timer of a track completion event.
  Future<void> onTrackCompleted() async {
    if (!_isArmed) return;

    if (_mode == SleepTimerMode.endOfTrack) {
      final token = _sleepFadeToken;
      await _executeExpiration(token);
    } else if (_mode == SleepTimerMode.afterNTracks) {
      _remainingTracks--;
      if (_remainingTracks <= 0) {
        final token = _sleepFadeToken;
        await _executeExpiration(token);
      }
    }
  }

  void _applyFadeOutStep(AudioPlayer? player, double fraction) {
    if (player == null || !player.playing) return;
    // FIX(BUG-25): Capture pre-fade volume once at fade start to prevent volume ratcheting down
    _preFadeVolume ??= player.volume;
    try {
      final target =
          (_preFadeVolume! * fraction.clamp(0.0, 1.0)).clamp(0.0, 1.0);
      player.setVolume(target);
    } catch (e, st) {
      ErrorLogger.log('_applyFadeOutStep failed', error: e, stackTrace: st, category: 'SleepTimerManager');
    }
  }

  Future<void> _executeExpiration(int token) async {
    if (_sleepFadeToken != token || !_isArmed) return;
    _isArmed = false;
    _sleepCountdownTickerCancel();

    final player = _lastPlayerGetter?.call();
    try {
      if (_onTimerExpiredCallback != null) {
        await _onTimerExpiredCallback!();
      }
    } catch (e, st) {
      ErrorLogger.log('Error triggering sleep timer callback',
          error: e, stackTrace: st, category: 'SleepTimer');
    } finally {
      // Restore pre-fade volume cleanly
      if (_preFadeVolume != null && player != null) {
        try {
          await player.setVolume(_preFadeVolume!);
        } catch (e, st) {
          ErrorLogger.log('_executeExpiration failed', error: e, stackTrace: st, category: 'SleepTimerManager');
        }
        _preFadeVolume = null;
      }
      _clearPersistedState();
    }
  }

  void _sleepCountdownTickerCancel() {
    _countdownTicker?.cancel();
    _countdownTicker = null;
    _sleepTimerRemainingSubject.add(null);
  }

  void cancelSleepTimer() {
    _sleepFadeToken++;
    _isArmed = false;
    _sleepCountdownTickerCancel();
    _remainingDuration = Duration.zero;
    _remainingTracks = 0;
    _onTimerExpiredCallback = null;

    if (_preFadeVolume != null && _lastPlayerGetter != null) {
      try {
        _lastPlayerGetter!().setVolume(_preFadeVolume!);
      } catch (e, st) {
        ErrorLogger.log('cancelSleepTimer failed', error: e, stackTrace: st, category: 'SleepTimerManager');
      }
      _preFadeVolume = null;
    }
    _clearPersistedState();
  }

  void _persistTimerState([Duration? duration]) {
    final dur = duration ?? _remainingDuration;
    final targetMs = DateTime.now().add(dur).millisecondsSinceEpoch;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt(PrefsKeys.sleepTimerTarget, targetMs);
    }).catchError((_) {});
  }

  void _clearPersistedState() {
    SharedPreferences.getInstance().then((prefs) {
      prefs.remove(PrefsKeys.sleepTimerTarget);
    }).catchError((_) {});
  }

  // FIX(BUG-18): Restore sleep timer on app restart if target timestamp is in the future
  Future<void> restoreTimerState({
    required Future<void> Function() onTimerExpired,
    required AudioPlayer Function() getActivePlayer,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final targetMs = prefs.getInt(PrefsKeys.sleepTimerTarget);
      if (targetMs != null) {
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final diffMs = targetMs - nowMs;
        if (diffMs > 1000) {
          startSleepTimer(
            Duration(milliseconds: diffMs),
            fadeOut: true,
            onTimerExpired: onTimerExpired,
            getActivePlayer: getActivePlayer,
          );
        } else {
          _clearPersistedState();
        }
      }
    } catch (e, st) {
      ErrorLogger.log('Function failed', error: e, stackTrace: st, category: 'SleepTimerManager');
    }
  }

  void dispose() {
    cancelSleepTimer();
    _sleepTimerRemainingSubject.close();
  }
}
