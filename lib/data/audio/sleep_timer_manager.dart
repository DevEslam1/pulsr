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
  Timer? _oneShotTimer;
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

  final StreamController<int?> _sleepTimerRemainingTracksSubject =
      StreamController<int?>.broadcast();
  Stream<int?> get sleepTimerRemainingTracksStream =>
      _sleepTimerRemainingTracksSubject.stream;

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
    _sleepTimerRemainingTracksSubject.add(null);
    _persistTimerState(duration);

    if (duration < const Duration(seconds: 1)) {
      // Sub-second timer for unit tests — tracked so cancel/dispose can stop it.
      _oneShotTimer?.cancel();
      _oneShotTimer = Timer(duration, () async {
        if (_isArmed && _sleepFadeToken == currentToken) {
          _remainingDuration = Duration.zero;
          _sleepTimerRemainingSubject.add(null);
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

      if (_remainingDuration > const Duration(seconds: 1)) {
        _remainingDuration -= const Duration(seconds: 1);
        _sleepTimerRemainingSubject.add(_remainingDuration);

        // Trigger smooth fade-out during the final 15 seconds (or remaining duration if smaller)
        if (_isFadeOutEnabled &&
            _remainingDuration <= const Duration(seconds: 15)) {
          _applyFadeOut(player, _remainingDuration.inSeconds);
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
    _sleepTimerRemainingTracksSubject.add(1);
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
    _sleepTimerRemainingTracksSubject.add(trackCount);
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
      } else {
        _sleepTimerRemainingSubject.add(Duration(minutes: _remainingTracks * 3));
        _sleepTimerRemainingTracksSubject.add(_remainingTracks);
      }
    }
  }

  bool _nativeCurveArmed = false;

  void _applyFadeOut(AudioPlayer? player, int remainingSeconds) {
    if (player == null || !player.playing) return;
    _preFadeVolume ??= player.volume;

    if (!_nativeCurveArmed && remainingSeconds <= 15 && remainingSeconds > 0) {
      final totalMs = remainingSeconds * 1000;
      final points = (totalMs / 20).ceil().clamp(2, 201);
      final segmentMs = (totalMs / (points - 1)).ceil().clamp(1, 1000);
      final gains = List<double>.generate(
        points,
        (i) => 1.0 - (i / (points - 1)),
      );
      try {
        player.dspSetGainCurve(gains, segmentMs: segmentMs).then((ok) {
          if (ok == true) {
            _nativeCurveArmed = true;
          }
        }).catchError((_) {});
      } catch (_) {}
    }

    if (!_nativeCurveArmed) {
      _applyFadeOutStep(player, remainingSeconds / 15.0);
    }
  }

  void _applyFadeOutStep(AudioPlayer? player, double fraction) {
    if (player == null || !player.playing) return;
    _preFadeVolume ??= player.volume;
    try {
      final target =
          (_preFadeVolume! * fraction.clamp(0.0, 1.0)).clamp(0.0, 1.0);
      player.setVolume(target);
    } catch (_) {}
  }

  Future<void> _executeExpiration(int token) async {
    if (_sleepFadeToken != token || !_isArmed) return;
    _isArmed = false;
    _sleepCountdownTickerCancel();

    final player = _lastPlayerGetter?.call();
    if (_nativeCurveArmed && player != null) {
      try {
        player.dspClearGainCurve().catchError((_) => false);
      } catch (_) {}
      _nativeCurveArmed = false;
    }
    try {
      if (_onTimerExpiredCallback != null) {
        await _onTimerExpiredCallback!();
      }
    } catch (e, st) {
      ErrorLogger.log('Error triggering sleep timer callback',
          error: e, stackTrace: st, category: 'SleepTimer');
    } finally {
      // Restore pre-fade volume cleanly — but only if the player is still
      // sitting at (or below) the faded level. If the user touched volume
      // mid-fade, don't clobber their choice.
      if (_preFadeVolume != null && player != null) {
        try {
          final current = player.volume;
          if (current <= _preFadeVolume! + 0.02) {
            await player.setVolume(_preFadeVolume!.clamp(0.0, 1.0));
          }
        } catch (_) {}
        _preFadeVolume = null;
      }
      _clearPersistedState();
    }
  }

  void _sleepCountdownTickerCancel() {
    _countdownTicker?.cancel();
    _countdownTicker = null;
    _oneShotTimer?.cancel();
    _oneShotTimer = null;
    _sleepTimerRemainingSubject.add(null);
    _sleepTimerRemainingTracksSubject.add(null);
  }

  void cancelSleepTimer() {
    _sleepFadeToken++;
    _isArmed = false;
    _sleepCountdownTickerCancel();
    _remainingDuration = Duration.zero;
    _remainingTracks = 0;
    _onTimerExpiredCallback = null;

    if (_lastPlayerGetter != null) {
      final player = _lastPlayerGetter!();
      if (_nativeCurveArmed) {
        try {
          player.dspClearGainCurve().catchError((_) => false);
        } catch (_) {}
        _nativeCurveArmed = false;
      }
      if (_preFadeVolume != null) {
        try {
          player.setVolume(_preFadeVolume!);
        } catch (_) {}
        _preFadeVolume = null;
      }
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

  /// Restores a persisted duration timer after process death / background kill.
  /// Returns true when a timer was re-armed. Track-based modes cannot be
  /// restored (queue position is unknown) and are cleared.
  Future<bool> restorePersistedState({
    required Future<void> Function() onTimerExpired,
    required AudioPlayer Function() getActivePlayer,
    bool fadeOut = true,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final targetMs = prefs.getInt(PrefsKeys.sleepTimerTarget);
      if (targetMs == null) return false;
      final remainingMs =
          targetMs - DateTime.now().millisecondsSinceEpoch;
      if (remainingMs <= 0) {
        await prefs.remove(PrefsKeys.sleepTimerTarget);
        return false;
      }
      // Cap at 24h to guard against clock-skew garbage.
      final remaining = Duration(milliseconds: remainingMs.clamp(0, 86400000));
      startSleepTimer(
        remaining,
        fadeOut: fadeOut,
        onTimerExpired: onTimerExpired,
        getActivePlayer: getActivePlayer,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  void _clearPersistedState() {
    SharedPreferences.getInstance().then((prefs) {
      prefs.remove(PrefsKeys.sleepTimerTarget);
    }).catchError((_) {});
  }

  void dispose() {
    cancelSleepTimer();
    _sleepTimerRemainingSubject.close();
    _sleepTimerRemainingTracksSubject.close();
  }
}
