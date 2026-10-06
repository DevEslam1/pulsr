// lib/data/audio/playback_interruption_manager.dart
import 'interruption_state_machine.dart';

/// Decisions returned by [PlaybackInterruptionManager] for platform events.
enum InterruptionDecision {
  ignore,
  pause,
  resume,
  duck,
  unduck,
}

/// Transition Table:
/// ─────────────────────────────────────────────────────────────────────────────
/// Current State         | Event                      | Decision | Next State
/// ─────────────────────────────────────────────────────────────────────────────
/// idle (playing: true)  | duckBegin                  | duck     | ducked
/// idle (playing: false) | duckBegin                  | ignore   | idle
/// ducked                | duckBegin (nested)         | ignore   | ducked (depth++)
/// ducked                | duckEnd (depth > 1)        | ignore   | ducked (depth--)
/// ducked                | duckEnd (depth == 1)       | unduck   | idle
/// idle (playing: true)  | pauseInterruptionBegin     | pause    | paused(interruption)
/// idle (playing: false) | pauseInterruptionBegin     | ignore   | idle
/// paused(interruption)  | pauseInterruptionEnd       | resume*  | idle
/// idle (playing: true)  | becomingNoisy              | pause    | paused(noisy)
/// paused(noisy)         | headsetReconnected(<limit) | resume*  | idle
/// paused(noisy)         | headsetReconnected(>limit) | ignore   | idle
/// any                   | userPlay / userPause       | ignore   | idle (clears all)
/// ─────────────────────────────────────────────────────────────────────────────
/// * resume only occurs if resumeAfterInterruption / autoResumeOnReconnect is enabled.
class PlaybackInterruptionManager {
  final InterruptionStateMachine _stateMachine = InterruptionStateMachine();

  int _duckDepth = 0;
  DateTime? _lastNoisyTime;
  DateTime? _noisyPauseTime;
  bool _pausedForNoisy = false;

  bool get isDucked => _duckDepth > 0;
  bool get isPausedForNoisy => _pausedForNoisy;
  bool get hasActiveInterruption => _stateMachine.isActive;
  InterruptionKind? get activeKind => _stateMachine.activeKind;

  /// User action (play or pause) unconditionally clears any pending auto-resumes.
  void onUserAction() {
    _stateMachine.onUserPause();
    _pausedForNoisy = false;
    _noisyPauseTime = null;
    _duckDepth = 0;
  }

  /// Processes transient duck focus loss event.
  InterruptionDecision onDuckBegin({required bool isPlaying, required bool shouldPauseInstead}) {
    if (shouldPauseInstead) {
      if (isPlaying) {
        _stateMachine.begin(InterruptionKind.duck, playing: true);
        return InterruptionDecision.pause;
      }
      return InterruptionDecision.ignore;
    }

    if (!isPlaying && _duckDepth == 0) {
      return InterruptionDecision.ignore;
    }

    _duckDepth++;
    if (_duckDepth == 1) {
      return InterruptionDecision.duck;
    }
    return InterruptionDecision.ignore;
  }

  /// Processes duck focus end event.
  InterruptionDecision onDuckEnd({required bool shouldPauseInstead, required bool resumeAllowed}) {
    if (shouldPauseInstead) {
      final wasPlaying = _stateMachine.end(InterruptionKind.duck);
      if (wasPlaying && resumeAllowed) {
        return InterruptionDecision.resume;
      }
      return InterruptionDecision.ignore;
    }

    if (_duckDepth > 0) {
      _duckDepth--;
      if (_duckDepth == 0) {
        return InterruptionDecision.unduck;
      }
    }
    return InterruptionDecision.ignore;
  }

  /// Processes pause interruption begin (e.g. phone call).
  InterruptionDecision onPauseInterruptionBegin({required bool isPlaying}) {
    if (isPlaying) {
      _stateMachine.begin(InterruptionKind.pause, playing: true);
      return InterruptionDecision.pause;
    }
    return InterruptionDecision.ignore;
  }

  /// Processes pause interruption end (call hangup).
  InterruptionDecision onPauseInterruptionEnd({required bool resumeAllowed}) {
    final wasPlaying = _stateMachine.end(InterruptionKind.pause);
    if (wasPlaying && resumeAllowed) {
      return InterruptionDecision.resume;
    }
    return InterruptionDecision.ignore;
  }

  /// Processes becoming noisy (headphone disconnect).
  InterruptionDecision onBecomingNoisy({
    required bool isPlaying,
    required DateTime now,
    Duration debounce = const Duration(milliseconds: 800),
  }) {
    if (_lastNoisyTime != null && now.difference(_lastNoisyTime!) < debounce) {
      return InterruptionDecision.ignore;
    }
    _lastNoisyTime = now;

    if (!isPlaying) {
      return InterruptionDecision.ignore;
    }

    _noisyPauseTime = now;
    _pausedForNoisy = true;
    return InterruptionDecision.pause;
  }

  /// Processes device reconnection after unplug.
  InterruptionDecision onDeviceReconnect({
    required DateTime now,
    required bool autoResumeEnabled,
    required Duration timeout,
    required bool hasHeadsetOutput,
  }) {
    if (!_pausedForNoisy) {
      return InterruptionDecision.ignore;
    }

    _pausedForNoisy = false;
    final pauseTime = _noisyPauseTime;
    _noisyPauseTime = null;

    if (!autoResumeEnabled || pauseTime == null) {
      return InterruptionDecision.ignore;
    }

    if (now.difference(pauseTime) > timeout) {
      return InterruptionDecision.ignore;
    }

    if (!hasHeadsetOutput) {
      return InterruptionDecision.ignore;
    }

    return InterruptionDecision.resume;
  }
}
