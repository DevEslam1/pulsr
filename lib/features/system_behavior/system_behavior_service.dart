// lib/features/system_behavior/system_behavior_service.dart
//
// Delivery layer for the system-behaviour pack. The service owns the platform
// wiring (audio_session interruptions, app lifecycle events) and executes the
// pure table in system_behavior_policy.dart through a small playback port.
//
// Audio-focus bookkeeping is NOT reimplemented here: every focus event is
// routed through the existing PlaybackInterruptionManager, which owns the
// pause/resume decision. This service only decides *how* that pause is
// delivered (fade, USB release, plain pause) and how playback comes back.

import 'dart:async';

import 'package:audio_service/audio_service.dart'
    show AudioHandler, PlaybackState;
import 'package:audio_session/audio_session.dart';
import 'package:flutter/widgets.dart';

import '../../core/utils/error_logger.dart';
import '../../data/audio/interruption_state_machine.dart';
import '../../data/audio/playback_interruption_manager.dart';
import '../../data/services/usb_exclusive_service.dart';
import 'system_behavior_policy.dart';
import 'system_behavior_settings.dart';

/// The playback capabilities the system-behaviour service may drive.
///
/// Kept as a narrow interface so the service can be tested with a recording
/// fake and so the audio handler stays the only owner of playback state.
abstract interface class SystemPlaybackPort {
  /// Resumes playback from the handler's own resume path.
  Future<void> play();

  /// Pauses playback, keeping the queue and position.
  Future<void> pause();

  /// Stops playback and releases the session.
  Future<void> stop();

  /// Skips to the next queue item.
  Future<void> next();

  /// Sets the software volume on the 0..1 linear gain scale.
  Future<void> setVolume(double volume);
}

/// Software-volume read/write pair an audio handler can expose.
///
/// `AudioHandler` itself has no volume members, so the app supplies the two
/// closures its handler already has. Without them the fade degrades to a plain
/// pause and every other operation still works.
@immutable
class AudioHandlerVolumeControls {
  /// Creates the pair from a reader and a writer.
  const AudioHandlerVolumeControls({
    required this.read,
    required this.write,
  });

  /// Current volume on the 0..1 linear gain scale.
  final double Function() read;

  /// Applies a volume on the 0..1 linear gain scale.
  final Future<void> Function(double volume) write;
}

/// [SystemPlaybackPort] over the live audio handler.
///
/// Every call is guarded: a transport failure must never escape into the
/// interruption stream listener, where it would kill the subscription.
class AudioHandlerSystemPlaybackPort implements SystemPlaybackPort {
  /// Wraps [handler]; [volume] supplies the software volume the handler's
  /// `AudioHandler` interface does not publish.
  AudioHandlerSystemPlaybackPort(this.handler, {this.volume});

  /// The handler this port drives.
  final AudioHandler handler;

  /// Optional software-volume access; null disables fades only.
  final AudioHandlerVolumeControls? volume;

  /// Current handler volume on the 0..1 scale, used as the fade start level.
  /// Null when no volume controls were supplied.
  double? get currentVolume => volume?.read();

  /// Latest handler playback state snapshot.
  PlaybackState get playbackState => handler.playbackState.value;

  /// Whether the handler is playing right now.
  bool get isPlaying => handler.playbackState.value.playing;

  @override
  Future<void> play() async {
    try {
      await handler.play();
    } catch (e, st) {
      _logPortFailure('play', e, st);
    }
  }

  @override
  Future<void> pause() async {
    try {
      await handler.pause();
    } catch (e, st) {
      _logPortFailure('pause', e, st);
    }
  }

  @override
  Future<void> stop() async {
    try {
      await handler.stop();
    } catch (e, st) {
      _logPortFailure('stop', e, st);
    }
  }

  @override
  Future<void> next() async {
    try {
      await handler.skipToNext();
    } catch (e, st) {
      _logPortFailure('next', e, st);
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    final AudioHandlerVolumeControls? controls = this.volume;
    if (controls == null) return;
    try {
      await controls.write(volume);
    } catch (e, st) {
      _logPortFailure('setVolume', e, st);
    }
  }

  void _logPortFailure(String operation, Object error, StackTrace stackTrace) {
    ErrorLogger.log(
      'System-behaviour port $operation failed',
      error: error,
      stackTrace: stackTrace,
      category: 'SystemBehavior',
    );
  }
}

/// Runs one fade-out ramp: steps a volume setter down to zero, then pauses.
///
/// The timer, the ramp position and the level to restore live here so the
/// service stays a dispatcher. Both callbacks come from the service, which owns
/// the logging policy.
class FadeOutController {
  /// Creates a controller over [setVolume] and [pause].
  FadeOutController({
    required Future<void> Function(double volume) setVolume,
    required Future<void> Function() pause,
  })  : _setVolume = setVolume,
        _pause = pause;

  final Future<void> Function(double volume) _setVolume;
  final Future<void> Function() _pause;

  Timer? _timer;
  FadeRamp? _ramp;
  int _step = 0;
  double? _savedVolume;

  /// Whether a ramp is currently running.
  bool get isRunning => _ramp != null;

  /// Starts a ramp from [from] down to zero over [duration].
  ///
  /// Returns false when there is nothing to ramp (silence, zero length or a
  /// sub-tick duration); the caller then pauses immediately.
  bool start({required double from, required Duration duration}) {
    cancelTimer();
    final FadeRamp ramp = FadeRamp(startVolume: from, total: duration);
    if (!ramp.isAudible || ramp.stepInterval <= Duration.zero) return false;
    // Keep the first level a fade started from: two overlapping fades must
    // still restore the volume the user actually had.
    _savedVolume ??= ramp.volumeAtStep(0);
    _ramp = ramp;
    _step = 0;
    _timer = Timer.periodic(ramp.stepInterval, _onTick);
    return true;
  }

  /// Stops a running ramp; restores the saved level when [restoreVolume].
  Future<void> cancel({required bool restoreVolume}) async {
    cancelTimer();
    if (restoreVolume) await restore();
  }

  /// Pushes the saved pre-fade level back to the player, exactly once.
  Future<void> restore() async {
    final double? saved = _savedVolume;
    if (saved == null) return;
    _savedVolume = null;
    await _setVolume(saved);
  }

  /// Forgets the saved level without touching the volume (used by stop).
  void clearSavedVolume() {
    _savedVolume = null;
  }

  /// Cancels the timer and the ramp. Safe to call more than once.
  void dispose() => cancelTimer();

  /// Cancels the timer and drops the running ramp, keeping the saved level.
  void cancelTimer() {
    _timer?.cancel();
    _timer = null;
    _ramp = null;
    _step = 0;
  }

  void _onTick(Timer timer) {
    final FadeRamp? ramp = _ramp;
    if (ramp == null) {
      timer.cancel();
      return;
    }
    _step += 1;
    final double volume = ramp.volumeAtStep(_step);
    final bool done = _step >= ramp.steps;
    if (done) {
      timer.cancel();
      _timer = null;
      _ramp = null;
      _step = 0;
    }
    unawaited(_applyStep(volume, pauseWhenDone: done));
  }

  Future<void> _applyStep(
    double volume, {
    required bool pauseWhenDone,
  }) async {
    await _setVolume(volume);
    if (pauseWhenDone) await _pause();
  }
}

/// Owns the platform wiring and executes the system-behaviour decisions.
///
/// Call [start] once from the composition root, then feed
/// [handleAudioFocusLoss] and the other `handle*` methods from wherever the app
/// learns about the event. Everything the platform path does is also reachable
/// through a public `handle*` method, so the delivery behaviour can be
/// exercised without a device.
class SystemBehaviorService with WidgetsBindingObserver {
  /// Creates the service.
  ///
  /// [volumeReader] and [isPlaying] are the only readings the service needs
  /// from the audio stack; without them the fade and the interruption guard
  /// degrade to a plain pause / no-op instead of guessing.
  /// [resumePlayback] overrides the port's own [SystemPlaybackPort.play] when
  /// the caller needs the handler's dedicated resume path.
  SystemBehaviorService({
    required SystemBehaviorSettings settings,
    required SystemPlaybackPort port,
    double Function()? volumeReader,
    bool Function()? isPlaying,
    Future<void> Function()? resumePlayback,
    Future<bool> Function(bool enabled)? usbRelease,
    DateTime Function()? clock,
    PlaybackInterruptionManager? interruptionManager,
  })  : _settings = settings,
        _port = port,
        _volumeReader = volumeReader,
        _isPlaying = isPlaying,
        _resumePlayback = resumePlayback,
        _usbRelease = usbRelease ?? _defaultUsbRelease,
        _clock = clock ?? DateTime.now,
        _interruption = interruptionManager ?? PlaybackInterruptionManager() {
    _fade = FadeOutController(setVolume: _setVolume, pause: _pause);
  }

  final SystemBehaviorSettings _settings;
  final SystemPlaybackPort _port;
  final double Function()? _volumeReader;
  final bool Function()? _isPlaying;
  final Future<void> Function()? _resumePlayback;
  final Future<bool> Function(bool enabled) _usbRelease;
  final DateTime Function() _clock;
  final PlaybackInterruptionManager _interruption;
  late final FadeOutController _fade;

  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<void>? _noisySub;
  bool _started = false;
  bool _disposed = false;
  bool _usbReleasedForBackground = false;
  bool _usbReleasedForFocusLoss = false;

  /// Whether a fade-out ramp is currently running.
  bool get isFading => _fade.isRunning;

  /// Whether the platform subscriptions are installed.
  bool get isStarted => _started;

  /// Installs the lifecycle listener and, unless [subscribeInterruptions] is
  /// false, the audio-interruption and becoming-noisy listeners.
  ///
  /// The audio handler already owns those two streams (its duck/pause path is
  /// wired into crossfade, replay gain and the duck-depth counter). Production
  /// starts this service with [subscribeInterruptions] false to avoid handling
  /// one focus event twice; the manual `handle*` methods remain available for a
  /// future unification. Idempotent. A missing audio session (unit tests,
  /// desktop) is logged and leaves the manual entry points fully usable.
  Future<void> start({bool subscribeInterruptions = true}) async {
    if (_started || _disposed) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    if (!subscribeInterruptions) return;
    try {
      final AudioSession session = await AudioSession.instance;
      _interruptionSub = session.interruptionEventStream.listen(
        _onInterruptionEvent,
        onError: (Object error, StackTrace stackTrace) {
          ErrorLogger.log(
            'Audio interruption stream failed',
            error: error,
            stackTrace: stackTrace,
            category: 'SystemBehavior',
          );
        },
      );
      _noisySub = session.becomingNoisyEventStream.listen(
        (void _) => unawaited(handleHeadsetUnplug()),
        onError: (Object error, StackTrace stackTrace) {
          ErrorLogger.log(
            'Becoming-noisy stream failed',
            error: error,
            stackTrace: stackTrace,
            category: 'SystemBehavior',
          );
        },
      );
    } catch (e, st) {
      ErrorLogger.log(
        'Audio session unavailable; system-behaviour listeners are off',
        error: e,
        stackTrace: st,
        category: 'SystemBehavior',
      );
    }
  }

  /// Handles a permanent or transient audio-focus loss.
  ///
  /// The interruption manager decides whether playback should pause at all;
  /// only then does the policy choose the delivery (fade, USB release, pause).
  ///
  /// Returns true when a pause delivery was started (immediately or through a
  /// fade ramp). The audio handler uses that answer to skip its own pause, so
  /// one focus loss produces exactly one pause.
  ///
  /// Both variants are recorded as [InterruptionKind.pause] because this path
  /// always delivers a pause. Recording a duck and ending a pause used to leave
  /// the manager stuck in the duck state, so no later gain could ever resume.
  Future<bool> handleAudioFocusLoss({required bool permanent}) async {
    if (_disposed) return false;
    final bool playing = _playing;
    final InterruptionDecision decision =
        _interruption.onPauseInterruptionBegin(isPlaying: playing);
    if (decision != InterruptionDecision.pause) {
      ErrorLogger.addBreadcrumb(
        'Focus loss ignored: playback was not running',
        category: 'system_behavior',
      );
      return false;
    }
    final SystemAction action = await _run(
      permanent
          ? SystemEvent.audioFocusLossPermanent
          : SystemEvent.audioFocusLossTransient,
    );
    return action != SystemAction.ignore;
  }

  /// Handles the end of a focus loss: restores the pre-fade volume and lets
  /// the interruption manager decide whether playback resumes.
  ///
  /// Ends whichever kind is actually active. A duck-only event ends as a duck;
  /// everything else ends as a pause, so the state can never stay half-open.
  ///
  /// Returns true when playback was resumed here, so the audio handler does not
  /// resume a second time.
  Future<bool> handleAudioFocusGain() async {
    if (_disposed) return false;
    final SystemBehaviorSettingsSnapshot snapshot = _settings.snapshot;
    final InterruptionDecision decision =
        _interruption.activeKind == InterruptionKind.duck
            ? _interruption.onDuckEnd(
                shouldPauseInstead: true,
                resumeAllowed: snapshot.resumeAfterCall,
              )
            : _interruption.onPauseInterruptionEnd(
                resumeAllowed: snapshot.resumeAfterCall,
              );
    _fade.cancelTimer();
    await _fade.restore();
    if (decision != InterruptionDecision.resume) return false;
    if (_usbReleasedForFocusLoss) {
      _usbReleasedForFocusLoss = false;
      try {
        await _usbRelease(true);
      } catch (e, st) {
        ErrorLogger.log(
          'Re-claiming the exclusive USB stream after focus loss failed',
          error: e,
          stackTrace: st,
          category: 'SystemBehavior',
        );
      }
    }
    await _resume();
    return true;
  }

  /// Handles a short system notification sound (duck begin), pausing when the
  /// user asked for that instead of a duck.
  ///
  /// Returns true when this call delivered a pause, so a caller that also pauses
  /// (the audio handler's duck path) can stand down.
  Future<bool> handleNotificationSound() async {
    if (_disposed) return false;
    final SystemBehaviorSettingsSnapshot snapshot = _settings.snapshot;
    final InterruptionDecision decision = _interruption.onDuckBegin(
      isPlaying: _playing,
      shouldPauseInstead: snapshot.pauseOnNotificationSound,
    );
    if (decision == InterruptionDecision.ignore) return false;
    if (decision == InterruptionDecision.duck) return false;
    final SystemAction action = await _run(SystemEvent.notificationSound);
    return action != SystemAction.ignore;
  }

  /// Handles the end of a notification-sound duck. Returns true when playback
  /// was resumed here.
  Future<bool> handleNotificationSoundEnd() async {
    if (_disposed) return false;
    final SystemBehaviorSettingsSnapshot snapshot = _settings.snapshot;
    final InterruptionDecision decision = _interruption.onDuckEnd(
      shouldPauseInstead: snapshot.pauseOnNotificationSound,
      resumeAllowed: snapshot.resumeAfterCall,
    );
    if (decision != InterruptionDecision.resume) return false;
    _fade.cancelTimer();
    await _fade.restore();
    await _resume();
    return true;
  }

  /// Handles a headset unplug (`becoming noisy`): the manager debounces and
  /// decides, then the policy pauses without fading into a dead sink.
  ///
  /// Returns true when this call delivered the pause.
  Future<bool> handleHeadsetUnplug() async {
    if (_disposed) return false;
    final InterruptionDecision decision = _interruption.onBecomingNoisy(
      isPlaying: _playing,
      now: _clock(),
    );
    if (decision != InterruptionDecision.pause) return false;
    final SystemAction action = await _run(SystemEvent.headsetUnplug);
    return action != SystemAction.ignore;
  }

  /// Handles the app being removed from the recents list.
  Future<void> handleTaskRemoved() async {
    await _run(SystemEvent.taskRemoved);
  }

  /// Handles a volume-rocker double press.
  Future<void> handleVolumeKeyDoublePress() async {
    await _run(SystemEvent.volumeKeyDoublePress);
  }

  /// Releases the exclusive USB claim when the user asked for that, but only
  /// while nothing is playing.
  ///
  /// The playing guard is the important half: Android reports
  /// [AppLifecycleState.paused] on screen-off too, and releasing the claim then
  /// would tear down the live USB stream and cut the music. A paused player can
  /// hand the DAC back to the system.
  Future<void> handleAppBackgrounded() => releaseUsbWhenBackgrounded();

  /// Releases the claim if `closeUsbWhenBackgrounded` is on and playback is
  /// idle. Returns whether a release was attempted.
  Future<bool> releaseUsbWhenBackgrounded() async {
    if (_disposed) return false;
    if (!_settings.snapshot.closeUsbWhenBackgrounded) return false;
    if (_playing) {
      ErrorLogger.addBreadcrumb(
        'USB claim kept while backgrounded: playback is running',
        category: 'system_behavior',
      );
      return false;
    }
    if (_usbReleasedForBackground) return false;
    _usbReleasedForBackground = true;
    await _releaseUsb();
    return true;
  }

  /// Cancels a running fade, restores the level the user had before it and
  /// re-claims the USB device if backgrounding released it.
  Future<void> handleAppResumed() async {
    if (_disposed) return;
    _fade.cancelTimer();
    await _fade.restore();
    await reclaimUsbOnResume();
  }

  /// Re-claims the USB device after a background release. Returns whether a
  /// claim was attempted.
  Future<bool> reclaimUsbOnResume() async {
    if (_disposed || !_usbReleasedForBackground) return false;
    _usbReleasedForBackground = false;
    try {
      await _usbRelease(true);
      return true;
    } catch (e, st) {
      ErrorLogger.log(
        'Re-claiming the exclusive USB stream failed',
        error: e,
        stackTrace: st,
        category: 'SystemBehavior',
      );
      return false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(handleAppResumed());
      case AppLifecycleState.inactive:
        break;
      case AppLifecycleState.hidden:
        break;
      case AppLifecycleState.paused:
        unawaited(handleAppBackgrounded());
      case AppLifecycleState.detached:
        unawaited(handleTaskRemoved());
    }
  }

  /// Cancels the fade timer, the stream subscriptions and the lifecycle
  /// observer. Safe to call twice.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _fade.dispose();
    if (_started) {
      WidgetsBinding.instance.removeObserver(this);
    }
    final List<StreamSubscription<Object?>?> subscriptions =
        <StreamSubscription<Object?>?>[_interruptionSub, _noisySub];
    for (final StreamSubscription<Object?>? sub in subscriptions) {
      if (sub != null) unawaited(sub.cancel());
    }
    _interruptionSub = null;
    _noisySub = null;
    _usbReleasedForFocusLoss = false;
  }

  void _onInterruptionEvent(AudioInterruptionEvent event) {
    switch (event.type) {
      case AudioInterruptionType.pause:
        unawaited(event.begin
            ? handleAudioFocusLoss(permanent: true)
            : handleAudioFocusGain());
      case AudioInterruptionType.unknown:
        unawaited(event.begin
            ? handleAudioFocusLoss(permanent: true)
            : handleAudioFocusGain());
      case AudioInterruptionType.duck:
        unawaited(event.begin
            ? handleNotificationSound()
            : handleNotificationSoundEnd());
    }
  }

  Future<SystemAction> _run(SystemEvent event) async {
    if (_disposed) return SystemAction.ignore;
    final SystemBehaviorSettingsSnapshot snapshot = _settings.snapshot;
    final SystemAction action = decide(event, snapshot);
    ErrorLogger.addBreadcrumb(
      'System event ${event.name} -> ${action.name}',
      category: 'system_behavior',
    );
    await _execute(action, snapshot);
    return action;
  }

  Future<void> _execute(
    SystemAction action,
    SystemBehaviorSettingsSnapshot snapshot,
  ) async {
    switch (action) {
      case SystemAction.ignore:
        return;
      case SystemAction.pauseKeepUsb:
        await _fade.cancel(restoreVolume: true);
        await _pause();
        return;
      case SystemAction.pauseAndReleaseUsb:
        _usbReleasedForFocusLoss = true;
        await _fade.cancel(restoreVolume: true);
        await _releaseUsb();
        await _pause();
        return;
      case SystemAction.fadeOutPause:
        await _startFadeOut(snapshot);
        return;
      case SystemAction.stop:
        await _fade.cancel(restoreVolume: false);
        _fade.clearSavedVolume();
        await _stop();
        return;
      case SystemAction.nextTrack:
        await _next();
        return;
      case SystemAction.seekDelta:
        ErrorLogger.log(
          'seekDelta has no delivery path in the system-behaviour service',
          category: 'SystemBehavior',
        );
        return;
    }
  }

  /// Starts a fade-out that pauses at the end.
  ///
  /// Falls back to a plain pause when the fade is disabled, when the current
  /// volume cannot be read, or when the fade would be shorter than one tick.
  Future<void> _startFadeOut(SystemBehaviorSettingsSnapshot snapshot) async {
    final Duration duration =
        fadeDurationFor(SystemAction.fadeOutPause, snapshot);
    final double? start = _volumeReader?.call();
    final bool ramping = duration > Duration.zero &&
        start != null &&
        _fade.start(from: start, duration: duration);
    if (!ramping) await _pause();
  }

  Future<void> _resume() async {
    final Future<void> Function() resume = _resumePlayback ?? _port.play;
    try {
      await resume();
    } catch (e, st) {
      ErrorLogger.log(
        'Resuming after an interruption failed',
        error: e,
        stackTrace: st,
        category: 'SystemBehavior',
      );
    }
  }

  Future<void> _pause() async {
    try {
      await _port.pause();
    } catch (e, st) {
      _logActionFailure('pause', e, st);
    }
  }

  Future<void> _stop() async {
    try {
      await _port.stop();
    } catch (e, st) {
      _logActionFailure('stop', e, st);
    }
  }

  Future<void> _next() async {
    try {
      await _port.next();
    } catch (e, st) {
      _logActionFailure('next', e, st);
    }
  }

  Future<void> _setVolume(double volume) async {
    try {
      await _port.setVolume(volume);
    } catch (e, st) {
      _logActionFailure('setVolume', e, st);
    }
  }

  Future<void> _releaseUsb() async {
    try {
      await _usbRelease(false);
    } catch (e, st) {
      ErrorLogger.log(
        'Releasing the exclusive USB claim failed',
        error: e,
        stackTrace: st,
        category: 'SystemBehavior',
      );
    }
  }

  void _logActionFailure(String action, Object error, StackTrace stackTrace) {
    ErrorLogger.log(
      'System-behaviour action $action failed',
      error: error,
      stackTrace: stackTrace,
      category: 'SystemBehavior',
    );
  }

  bool get _playing => _isPlaying?.call() ?? false;

  static Future<bool> _defaultUsbRelease(bool enabled) =>
      UsbExclusiveService().setExclusive(enabled);
}
