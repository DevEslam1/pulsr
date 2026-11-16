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

import 'package:audio_session/audio_session.dart';
import 'package:flutter/widgets.dart';

import '../../core/utils/error_logger.dart';
import '../../data/audio/audio_handler.dart';
import '../../data/audio/playback_interruption_manager.dart';
import '../../data/services/usb_exclusive_service.dart';
import 'system_behavior_policy.dart';
import 'system_behavior_settings.dart';

/// The playback capabilities the system-behaviour service may drive.
///
/// Kept as a narrow interface so the service can be tested with a recording
/// fake and so the audio handler stays the only owner of playback state.
abstract interface class SystemPlaybackPort {
  /// Pauses playback, keeping the queue and position.
  Future<void> pause();

  /// Stops playback and releases the session.
  Future<void> stop();

  /// Skips to the next queue item.
  Future<void> next();

  /// Sets the software volume on the 0..1 linear gain scale.
  Future<void> setVolume(double volume);
}

/// [SystemPlaybackPort] over the live [PulsrAudioHandler].
///
/// Every call is guarded: a transport failure must never escape into the
/// interruption stream listener, where it would kill the subscription.
class AudioHandlerSystemPlaybackPort implements SystemPlaybackPort {
  /// Wraps [handler]; [currentVolume] and [isPlaying] are read by the fade and
  /// interruption paths, nothing else is touched.
  AudioHandlerSystemPlaybackPort(this.handler);

  /// The handler this port drives.
  final PulsrAudioHandler handler;

  /// Current handler volume on the 0..1 scale, used as the fade start level.
  double get currentVolume => handler.volume;

  /// Whether the handler is playing right now.
  bool get isPlaying => handler.playbackState.value.playing;

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
    try {
      await handler.setVolume(volume);
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
  /// [resumePlayback] is how a resume reaches the handler (`play()` has no
  /// place in [SystemPlaybackPort] because playback must always be resumed
  /// through the handler's own resume path).
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

  /// Whether a fade-out ramp is currently running.
  bool get isFading => _fade.isRunning;

  /// Whether the platform subscriptions are installed.
  bool get isStarted => _started;

  /// Installs the audio-interruption, becoming-noisy and lifecycle listeners.
  ///
  /// Idempotent. A missing audio session (unit tests, desktop) is logged and
  /// leaves the manual `handle*` entry points fully usable.
  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
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
  Future<void> handleAudioFocusLoss({required bool permanent}) async {
    if (_disposed) return;
    final bool playing = _playing;
    final InterruptionDecision decision = permanent
        ? _interruption.onPauseInterruptionBegin(isPlaying: playing)
        : _interruption
            .onDuckBegin(isPlaying: playing, shouldPauseInstead: true);
    if (decision != InterruptionDecision.pause) {
      ErrorLogger.addBreadcrumb(
        'Focus loss ignored: playback was not running',
        category: 'system_behavior',
      );
      return;
    }
    await _run(
      permanent
          ? SystemEvent.audioFocusLossPermanent
          : SystemEvent.audioFocusLossTransient,
    );
  }

  /// Handles the end of a focus loss: restores the pre-fade volume and lets
  /// the interruption manager decide whether playback resumes.
  Future<void> handleAudioFocusGain() async {
    if (_disposed) return;
    final SystemBehaviorSettingsSnapshot snapshot = _settings.snapshot;
    final InterruptionDecision decision = _interruption
        .onPauseInterruptionEnd(resumeAllowed: snapshot.resumeAfterCall);
    _fade.cancelTimer();
    await _fade.restore();
    if (decision == InterruptionDecision.resume) await _resume();
  }

  /// Handles a short system notification sound (duck begin), pausing when the
  /// user asked for that instead of a duck.
  Future<void> handleNotificationSound() async {
    if (_disposed) return;
    final SystemBehaviorSettingsSnapshot snapshot = _settings.snapshot;
    final InterruptionDecision decision = _interruption.onDuckBegin(
      isPlaying: _playing,
      shouldPauseInstead: snapshot.pauseOnNotificationSound,
    );
    if (decision == InterruptionDecision.ignore) return;
    await _run(SystemEvent.notificationSound);
  }

  /// Handles the end of a notification-sound duck.
  Future<void> handleNotificationSoundEnd() async {
    if (_disposed) return;
    final SystemBehaviorSettingsSnapshot snapshot = _settings.snapshot;
    final InterruptionDecision decision = _interruption.onDuckEnd(
      shouldPauseInstead: snapshot.pauseOnNotificationSound,
      resumeAllowed: snapshot.resumeAfterCall,
    );
    if (decision != InterruptionDecision.resume) return;
    _fade.cancelTimer();
    await _fade.restore();
    await _resume();
  }

  /// Handles a headset unplug (`becoming noisy`): the manager debounces and
  /// decides, then the policy pauses without fading into a dead sink.
  Future<void> handleHeadsetUnplug() async {
    if (_disposed) return;
    final InterruptionDecision decision = _interruption.onBecomingNoisy(
      isPlaying: _playing,
      now: _clock(),
    );
    if (decision != InterruptionDecision.pause) return;
    await _run(SystemEvent.headsetUnplug);
  }

  /// Handles the app being removed from the recents list.
  Future<void> handleTaskRemoved() => _run(SystemEvent.taskRemoved);

  /// Handles a volume-rocker double press.
  Future<void> handleVolumeKeyDoublePress() =>
      _run(SystemEvent.volumeKeyDoublePress);

  /// Releases the exclusive USB claim when the user asked for that.
  Future<void> handleAppBackgrounded() async {
    if (_disposed) return;
    if (!_settings.snapshot.closeUsbWhenBackgrounded) return;
    await _releaseUsb();
  }

  /// Cancels a running fade and restores the level the user had before it.
  Future<void> handleAppResumed() async {
    if (_disposed) return;
    _fade.cancelTimer();
    await _fade.restore();
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

  Future<void> _run(SystemEvent event) async {
    if (_disposed) return;
    final SystemBehaviorSettingsSnapshot snapshot = _settings.snapshot;
    final SystemAction action = decide(event, snapshot);
    ErrorLogger.addBreadcrumb(
      'System event ${event.name} -> ${action.name}',
      category: 'system_behavior',
    );
    await _execute(action, snapshot);
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
    final Future<void> Function()? resume = _resumePlayback;
    if (resume == null) {
      ErrorLogger.addBreadcrumb(
        'Resume requested but no playback handler was wired',
        category: 'system_behavior',
      );
      return;
    }
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
