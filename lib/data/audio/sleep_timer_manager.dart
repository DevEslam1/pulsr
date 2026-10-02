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

/// Playback-aware sleep timer manager with persistence recovery.
/// Evaluates countdown progress against active playback progression and persists
/// target timestamps for recovery across Android Doze and CPU deep sleep cycles.
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

  /// Volume-coordination hooks installed by the audio handler (both optional).
  ///
  /// When [onFadeFactor] is set the manager reports its stepped fade progress
  /// as a FACTOR (0..1, 1.0 = no attenuation) instead of writing the active
  /// player's volume itself. The handler is then the single volume writer and
  /// composes this factor with the duck-aware ReplayGain/user target (and
  /// defers to the crossfade manager), so a duck-end can no longer wipe the
  /// fade for a tick and the fade can no longer undo a duck.
  ///
  /// [baseVolumeProvider] returns the handler's clean (un-faded) target volume
  /// so the standalone fallback path derives its baseline from the real target
  /// instead of snapshotting whatever the player happens to read — which may be
  /// a ducked level. When both are null the manager behaves exactly as before
  /// (drives the player volume directly), which keeps it usable without a
  /// handler (e.g. unit tests).
  void Function(double factor)? onFadeFactor;
  double Function()? baseVolumeProvider;

  /// Clean baseline for the standalone fade path: the handler's un-faded target
  /// when available (never a ducked snapshot), else the player's live volume.
  double _resolveFadeBaseline(AudioPlayer player) {
    final provided = baseVolumeProvider?.call();
    if (provided != null && provided.isFinite) {
      return provided.clamp(0.0, 1.0);
    }
    return player.volume.clamp(0.0, 1.0);
  }

  bool countDownWhilePaused = false;
  List<Duration> _queuedDurations = [];

  bool get isArmed => _isArmed;
  bool get isActive => _isArmed;
  SleepTimerMode get mode => _mode;
  Duration get remainingDuration => _remainingDuration;
  int get remainingTracks => _remainingTracks;

  void startDurationTimer(
    Duration duration, {
    AudioPlayer Function()? playerGetter,
    Future<void> Function()? onExpired,
  }) {
    startSleepTimer(
      duration,
      getActivePlayer: playerGetter ??
          _lastPlayerGetter ??
          () => throw StateError('No player available'),
      onTimerExpired: onExpired ?? _onTimerExpiredCallback ?? () async {},
    );
  }

  Duration _calculateRemainingTracksDuration() {
    if (_remainingTracks <= 0) return Duration.zero;

    var knownTotal = Duration.zero;
    var knownCount = 0;
    final tracksToInspect = _queuedDurations.take(_remainingTracks);

    for (final d in tracksToInspect) {
      if (d > Duration.zero) {
        knownTotal += d;
        knownCount++;
      }
    }

    final unknownCount = _remainingTracks - knownCount;
    if (unknownCount <= 0) {
      return knownTotal;
    }

    // Derive per-track average from the known durations in queue
    var averageDuration = Duration.zero;
    if (knownCount > 0) {
      averageDuration =
          Duration(milliseconds: knownTotal.inMilliseconds ~/ knownCount);
    } else {
      final allKnown =
          _queuedDurations.where((d) => d > Duration.zero).toList();
      if (allKnown.isNotEmpty) {
        final totalAll =
            allKnown.fold<Duration>(Duration.zero, (prev, d) => prev + d);
        averageDuration =
            Duration(milliseconds: totalAll.inMilliseconds ~/ allKnown.length);
      }
    }

    if (averageDuration <= Duration.zero) {
      averageDuration = const Duration(minutes: 3);
    }

    return knownTotal + (averageDuration * unknownCount);
  }

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

    if (!_sleepTimerRemainingSubject.isClosed) {
      _sleepTimerRemainingSubject.add(_remainingDuration);
    }
    if (!_sleepTimerRemainingTracksSubject.isClosed) {
      _sleepTimerRemainingTracksSubject.add(null);
    }
    _persistTimerState(duration);

    if (duration < const Duration(seconds: 1)) {
      // Sub-second timer for unit tests — tracked so cancel/dispose can stop it.
      _oneShotTimer?.cancel();
      _oneShotTimer = Timer(duration, () async {
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

    // 1-second countdown ticker evaluated against active playback
    _countdownTicker =
        Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!_isArmed || _sleepFadeToken != currentToken) {
        timer.cancel();
        return;
      }

      final player = _lastPlayerGetter?.call();
      final isPlaying = player?.playing ?? true;
      if (!countDownWhilePaused && !isPlaying) {
        // Paused: countdown suspended while playback is paused
        return;
      }

      if (_remainingDuration > const Duration(seconds: 1)) {
        _remainingDuration -= const Duration(seconds: 1);
        if (!_sleepTimerRemainingSubject.isClosed) {
          _sleepTimerRemainingSubject.add(_remainingDuration);
        }
        if (!countDownWhilePaused && _remainingDuration.inSeconds % 5 == 0) {
          _persistTimerState(_remainingDuration);
        }

        // Trigger smooth fade-out during the final 15 seconds
        if (_isFadeOutEnabled &&
            _remainingDuration <= const Duration(seconds: 15)) {
          _applyFadeOut(player, _remainingDuration.inSeconds);
        }
      } else {
        _remainingDuration = Duration.zero;
        if (!_sleepTimerRemainingSubject.isClosed) {
          _sleepTimerRemainingSubject.add(null);
        }
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
    if (!_sleepTimerRemainingSubject.isClosed) {
      _sleepTimerRemainingSubject
          .add(const Duration(minutes: 1)); // Symbolic active state
    }
    if (!_sleepTimerRemainingTracksSubject.isClosed) {
      _sleepTimerRemainingTracksSubject.add(1);
    }
    _persistTimerState();
  }

  /// Configures sleep timer to fire after [trackCount] tracks finish playing.
  void startAfterNTracksTimer(
    int trackCount, {
    bool fadeOut = true,
    required Future<void> Function() onTimerExpired,
    required AudioPlayer Function() getActivePlayer,
    List<Duration>? trackDurations,
  }) {
    cancelSleepTimer();
    if (trackCount <= 0) return;

    _isArmed = true;
    _mode = SleepTimerMode.afterNTracks;
    _remainingTracks = trackCount;
    _queuedDurations = trackDurations != null ? List.from(trackDurations) : [];
    _isFadeOutEnabled = fadeOut;
    _onTimerExpiredCallback = onTimerExpired;
    _lastPlayerGetter = getActivePlayer;
    _sleepFadeToken++;

    final remainingDur = _calculateRemainingTracksDuration();
    _remainingDuration = remainingDur;
    if (!_sleepTimerRemainingSubject.isClosed) {
      _sleepTimerRemainingSubject.add(remainingDur);
    }
    if (!_sleepTimerRemainingTracksSubject.isClosed) {
      _sleepTimerRemainingTracksSubject.add(trackCount);
    }
    _persistTimerState();
  }

  /// Configures sleep timer to fire at the end of the playback queue.
  /// The host must call [onQueueCompleted] when the queue is exhausted
  /// (or [onTrackCompleted] with [isLastInQueue] info via [notifyQueueEnd]).
  void startEndOfQueueTimer({
    bool fadeOut = true,
    required Future<void> Function() onTimerExpired,
    required AudioPlayer Function() getActivePlayer,
  }) {
    cancelSleepTimer();
    _isArmed = true;
    _mode = SleepTimerMode.endOfQueue;
    _remainingTracks = -1; // unknown until queue end
    _isFadeOutEnabled = fadeOut;
    _onTimerExpiredCallback = onTimerExpired;
    _lastPlayerGetter = getActivePlayer;
    _sleepFadeToken++;
    if (!_sleepTimerRemainingSubject.isClosed) {
      _sleepTimerRemainingSubject.add(const Duration(minutes: 1));
    }
    if (!_sleepTimerRemainingTracksSubject.isClosed) {
      _sleepTimerRemainingTracksSubject.add(null);
    }
    _persistTimerState();
  }

  /// Call when the queue is exhausted (last track completed with no repeat).
  Future<void> onQueueCompleted() async {
    if (!_isArmed || _mode != SleepTimerMode.endOfQueue) return;
    final token = _sleepFadeToken;
    await _executeExpiration(token);
  }

  /// Updates remaining queue durations when the playback queue is mutated.
  void updateQueueDurations(List<Duration> durations) {
    _queuedDurations = List.from(durations);
    if (_isArmed && _mode == SleepTimerMode.afterNTracks) {
      final rem = _calculateRemainingTracksDuration();
      _remainingDuration = rem;
      if (!_sleepTimerRemainingSubject.isClosed) {
        _sleepTimerRemainingSubject.add(rem);
      }
    }
  }

  /// Notifies the sleep timer of a track completion event.
  Future<void> onTrackCompleted({List<Duration>? currentQueueDurations}) async {
    if (!_isArmed) return;

    if (_mode == SleepTimerMode.endOfTrack) {
      final token = _sleepFadeToken;
      await _executeExpiration(token);
    } else if (_mode == SleepTimerMode.afterNTracks) {
      _remainingTracks--;
      if (currentQueueDurations != null) {
        _queuedDurations = List.from(currentQueueDurations);
      } else if (_queuedDurations.isNotEmpty) {
        _queuedDurations.removeAt(0);
      }
      if (_remainingTracks <= 0) {
        final token = _sleepFadeToken;
        await _executeExpiration(token);
      } else {
        final rem = _calculateRemainingTracksDuration();
        _remainingDuration = rem;
        if (!_sleepTimerRemainingSubject.isClosed) {
          _sleepTimerRemainingSubject.add(rem);
        }
        if (!_sleepTimerRemainingTracksSubject.isClosed) {
          _sleepTimerRemainingTracksSubject.add(_remainingTracks);
        }
      }
    }
  }

  bool _nativeCurveArmed = false;

  void _applyFadeOut(AudioPlayer? player, int remainingSeconds) {
    if (player == null || !player.playing) return;
    _preFadeVolume ??= _resolveFadeBaseline(player);

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
    final f = fraction.clamp(0.0, 1.0);
    // Coordinated path: report the fade as a FACTOR and let the handler perform
    // the single volume write (composing with ducking/ReplayGain, deferring to
    // crossfade). Avoids this manager and the duck path both writing setVolume.
    final sink = onFadeFactor;
    if (sink != null) {
      sink(f);
      return;
    }
    // Standalone fallback: drive the player directly from a clean baseline.
    _preFadeVolume ??= _resolveFadeBaseline(player);
    try {
      final target = (_preFadeVolume! * f).clamp(0.0, 1.0);
      player.setVolume(target);
    } catch (_) {}
  }

  /// Short volume ramp used by the track/queue sleep modes at their boundary,
  /// where the duration-mode countdown's gradual fade never runs. Reuses the
  /// same per-step ramp primitive as [_applyFadeOut] ([_applyFadeOutStep]) and
  /// aborts early if the timer is cancelled or re-armed, or playback stops,
  /// mid-fade. The pre-fade volume is restored by [_executeExpiration]'s
  /// finally block once the pause completes.
  Future<void> _fadeBeforePause(AudioPlayer player, int token) async {
    _preFadeVolume ??= _resolveFadeBaseline(player);
    const steps = 16;
    const stepDelay = Duration(milliseconds: 100); // ~1.6s total ramp
    for (var i = steps - 1; i >= 0; i--) {
      if (_sleepFadeToken != token || !player.playing) return;
      _applyFadeOutStep(player, i / steps);
      await Future.delayed(stepDelay);
    }
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
    // The track/queue modes (endOfTrack/afterNTracks/endOfQueue) expire at a
    // playback boundary via onTrackCompleted/onQueueCompleted and have no
    // countdown, so the duration ticker's final-15s fade never runs for them.
    // Honor their `fadeOut` request with a short ramp here, right before the
    // pause callback, instead of silently hard-pausing (fixes: fadeOut ignored
    // for non-duration modes).
    if (_isFadeOutEnabled &&
        _mode != SleepTimerMode.duration &&
        player != null &&
        player.playing) {
      await _fadeBeforePause(player, token);
    }
    try {
      if (_onTimerExpiredCallback != null) {
        await _onTimerExpiredCallback!();
      }
    } catch (e, st) {
      ErrorLogger.log('Error triggering sleep timer callback',
          error: e, stackTrace: st, category: 'SleepTimer');
    } finally {
      if (onFadeFactor != null) {
        // Coordinated mode: hand volume authority back to the handler by
        // releasing the fade factor; it re-applies the clean, duck-aware
        // target itself (the player is paused by now, so this just leaves the
        // right level for the next resume). Never a stale/ducked snapshot.
        try {
          onFadeFactor!(1.0);
        } catch (_) {}
      } else if (_preFadeVolume != null && player != null) {
        // Standalone mode: restore the pre-fade volume cleanly — but only if
        // the player is still sitting at (or below) the faded level. If the
        // user touched volume mid-fade, don't clobber their choice.
        try {
          final current = player.volume;
          if (current <= _preFadeVolume! + 0.02) {
            await player.setVolume(_preFadeVolume!.clamp(0.0, 1.0));
          }
        } catch (_) {}
      }
      _preFadeVolume = null;
      _clearPersistedState();
    }
  }

  void _sleepCountdownTickerCancel() {
    _countdownTicker?.cancel();
    _countdownTicker = null;
    _oneShotTimer?.cancel();
    _oneShotTimer = null;
    if (!_sleepTimerRemainingSubject.isClosed) {
      _sleepTimerRemainingSubject.add(null);
    }
    if (!_sleepTimerRemainingTracksSubject.isClosed) {
      _sleepTimerRemainingTracksSubject.add(null);
    }
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
      if (onFadeFactor != null) {
        // Coordinated mode: release the fade factor so the handler restores the
        // clean, duck-aware target (not a possibly-ducked snapshot).
        try {
          onFadeFactor!(1.0);
        } catch (_) {}
        _preFadeVolume = null;
      } else if (_preFadeVolume != null) {
        try {
          player.setVolume(_preFadeVolume!);
        } catch (_) {}
        _preFadeVolume = null;
      }
    } else if (onFadeFactor != null) {
      try {
        onFadeFactor!(1.0);
      } catch (_) {}
      _preFadeVolume = null;
    }
    _clearPersistedState();
  }

  // Persisted alongside [PrefsKeys.sleepTimerTarget] so restore can tell whether
  // the saved wall-clock target is a real deadline (duration mode) or only an
  // estimate of a track/queue boundary that must NOT be re-armed as a clock.
  static const String _modeKey = 'sleep_timer_mode_v1';

  void _persistTimerState([Duration? duration]) {
    final dur = duration ?? _remainingDuration;
    final targetMs = DateTime.now().add(dur).millisecondsSinceEpoch;
    final modeName = _mode.name;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt(PrefsKeys.sleepTimerTarget, targetMs);
      prefs.setString(_modeKey, modeName);
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

      // Only pure duration timers represent a real fixed deadline. The
      // track/queue modes (afterNTracks/endOfTrack/endOfQueue) persist a
      // wall-clock ESTIMATE of their boundary; re-arming that as a duration
      // timer would resurrect e.g. "stop after 3 tracks" as an unrelated clock
      // countdown (the bug this guards). Refuse to restore them. A missing mode
      // means an older payload — treat it as duration for backward compat.
      final modeName = prefs.getString(_modeKey);
      final persistedMode = modeName == null
          ? SleepTimerMode.duration
          : SleepTimerMode.values.firstWhere(
              (m) => m.name == modeName,
              orElse: () => SleepTimerMode.duration,
            );
      if (persistedMode != SleepTimerMode.duration) {
        await prefs.remove(PrefsKeys.sleepTimerTarget);
        await prefs.remove(_modeKey);
        return false;
      }

      final remainingMs = targetMs - DateTime.now().millisecondsSinceEpoch;
      if (remainingMs <= 0) {
        await prefs.remove(PrefsKeys.sleepTimerTarget);
        await prefs.remove(_modeKey);
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
      prefs.remove(_modeKey);
    }).catchError((_) {});
  }

  void dispose() {
    _sleepFadeToken++;
    _isArmed = false;
    _countdownTicker?.cancel();
    _oneShotTimer?.cancel();
    // Drop coordination hooks so no late fade-factor callback fires into a
    // handler that is tearing down.
    onFadeFactor = null;
    baseVolumeProvider = null;
    if (!_sleepTimerRemainingSubject.isClosed) {
      _sleepTimerRemainingSubject.close();
    }
    if (!_sleepTimerRemainingTracksSubject.isClosed) {
      _sleepTimerRemainingTracksSubject.close();
    }
  }
}
