// lib/features/system_behavior/system_behavior_runtime.dart
//
// Composition root for the system-behaviour pack: it turns the persisted
// settings into a live [SystemBehaviorService], wires the real playback port
// over [PulsrAudioHandler], and listens for the native task-removal signal.
//
// Without this file the service is never constructed and every setting is
// decorative. The host calls [SystemBehaviorRuntime.start] once and
// [SystemBehaviorRuntime.dispose] with the app.

import 'dart:async';

import 'package:audio_service/audio_service.dart' show AudioHandler;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/utils/error_logger.dart';
import '../../data/audio/audio_handler.dart';
import '../../data/audio/system_behavior_hooks.dart';
import '../../data/services/usb_exclusive_service.dart';
import 'system_behavior_service.dart';
import 'system_behavior_settings.dart';

/// Live wiring of the system-behaviour service.
///
/// Owns the service, the task-removal channel handler and the settings
/// subscription that mirrors `stopWhenTaskRemoved` to the native plugin. The
/// settings object itself is owned by the caller.
class SystemBehaviorRuntime {
  SystemBehaviorRuntime._({
    required SystemBehaviorService service,
    required MethodChannel channel,
    required SystemBehaviorSettings settings,
  })  : _service = service,
        _channel = channel,
        _settings = settings;

  /// Native channel shared with `SystemBehaviorPlugin`.
  static const MethodChannel defaultChannel =
      MethodChannel('com.pulsr.music/system_behavior');

  /// Method the native side invokes when the UI task is removed.
  static const String taskRemovedMethod = 'taskRemoved';

  /// Method that mirrors the task-removal policy to the native side.
  static const String setStopWhenTaskRemovedMethod = 'setStopWhenTaskRemoved';

  final SystemBehaviorService _service;
  final MethodChannel _channel;
  final SystemBehaviorSettings _settings;

  VoidCallback? _settingsListener;
  bool _disposed = false;
  PulsrAudioHandler? _attachedHandler;

  /// Whether the service subscriptions are installed and the runtime is live.
  bool get isStarted => !_disposed && _service.isStarted;

  /// Whether a fade-out ramp is running right now.
  bool get isFading => _service.isFading;

  /// Builds the real port over [handler], starts the service and subscribes to
  /// the native task-removal signal.
  ///
  /// [handler] is the app's [AudioHandler] (PulsrAudioHandler). [readVolume]
  /// and [writeVolume] supply the software-volume pair `AudioHandler` does not
  /// expose; pass `() => handler.volume` and `handler.setVolume` in production
  /// so fades start from the real level. Without them fades fall back to a
  /// plain pause.
  ///
  /// Add this once, after the audio handler is ready:
  /// `await SystemBehaviorRuntime.start(settings: settings, handler: handler,
  /// readVolume: () => handler.volume, writeVolume: handler.setVolume)`.
  static Future<SystemBehaviorRuntime> start({
    required SystemBehaviorSettings settings,
    required AudioHandler handler,
    double Function()? readVolume,
    Future<void> Function(double volume)? writeVolume,
    MethodChannel? channel,
    bool subscribeInterruptions = false,
  }) async {
    final AudioHandlerVolumeControls? volume =
        readVolume == null || writeVolume == null
            ? null
            : AudioHandlerVolumeControls(
                read: readVolume,
                write: writeVolume,
              );
    final AudioHandlerSystemPlaybackPort port =
        AudioHandlerSystemPlaybackPort(handler, volume: volume);
    final SystemBehaviorRuntime runtime = await _start(
      settings: settings,
      port: port,
      volumeReader: volume == null ? null : () => port.currentVolume ?? 0,
      isPlaying: () => port.isPlaying,
      resumePlayback: port.play,
      usbRelease: (bool enabled) => UsbExclusiveService().setExclusive(enabled),
      channel: channel ?? defaultChannel,
      subscribeInterruptions: subscribeInterruptions,
    );
    // Delivery is live from here on: the handler forwards its focus / duck /
    // noisy events to this service and stops pausing on its own, so one event
    // produces exactly one pause (fade or immediate, as the settings decide).
    runtime._attachToHandler(handler);
    return runtime;
  }

  /// Bridges [handler]'s interruption path to this runtime's service.
  ///
  /// Only a [PulsrAudioHandler] exposes the attach point; any other
  /// `AudioHandler` keeps its own delivery and the service stays reachable
  /// through the manual `handle*` methods. Public so a test can wire a fake
  /// handler and assert the one-pause contract without booting the app.
  @visibleForTesting
  void attachToHandler(AudioHandler handler) => _attachToHandler(handler);

  void _attachToHandler(AudioHandler handler) {
    if (handler is! PulsrAudioHandler) return;
    _attachedHandler = handler;
    handler.attachSystemBehaviorHooks(SystemBehaviorHooks(
      onAudioFocusLoss: ({required bool permanent}) =>
          _service.handleAudioFocusLoss(permanent: permanent),
      onAudioFocusGain: _service.handleAudioFocusGain,
      onNotificationSound: _service.handleNotificationSound,
      onNotificationSoundEnd: _service.handleNotificationSoundEnd,
      onHeadsetUnplug: _service.handleHeadsetUnplug,
    ));
  }

  /// Starts the runtime over an injected port. Used by tests, which cannot
  /// construct the app's audio handler.
  @visibleForTesting
  static Future<SystemBehaviorRuntime> startWithPort({
    required SystemBehaviorSettings settings,
    required SystemPlaybackPort port,
    double Function()? volumeReader,
    bool Function()? isPlaying,
    Future<void> Function()? resumePlayback,
    Future<bool> Function(bool enabled)? usbRelease,
    DateTime Function()? clock,
    MethodChannel? channel,
    bool subscribeInterruptions = false,
  }) {
    return _start(
      settings: settings,
      port: port,
      volumeReader: volumeReader,
      isPlaying: isPlaying,
      resumePlayback: resumePlayback,
      usbRelease: usbRelease,
      clock: clock,
      channel: channel ?? defaultChannel,
      subscribeInterruptions: subscribeInterruptions,
    );
  }

  static Future<SystemBehaviorRuntime> _start({
    required SystemBehaviorSettings settings,
    required SystemPlaybackPort port,
    required MethodChannel channel,
    double Function()? volumeReader,
    bool Function()? isPlaying,
    Future<void> Function()? resumePlayback,
    Future<bool> Function(bool enabled)? usbRelease,
    DateTime Function()? clock,
    bool subscribeInterruptions = false,
  }) async {
    final SystemBehaviorService service = SystemBehaviorService(
      settings: settings,
      port: port,
      volumeReader: volumeReader,
      isPlaying: isPlaying,
      resumePlayback: resumePlayback,
      usbRelease: usbRelease,
      clock: clock,
    );
    final SystemBehaviorRuntime runtime = SystemBehaviorRuntime._(
      service: service,
      channel: channel,
      settings: settings,
    );
    runtime._settingsListener = () => unawaited(runtime._pushTaskPolicy());
    settings.addListener(runtime._settingsListener!);
    channel.setMethodCallHandler(runtime._onPlatformCall);
    unawaited(runtime._pushTaskPolicy());
    await service.start(subscribeInterruptions: subscribeInterruptions);
    return runtime;
  }

  /// Handles a task removal delivered directly (instead of over the channel).
  Future<void> handleTaskRemoved() => _service.handleTaskRemoved();

  /// Releases the USB claim when backgrounded, unless playback is running.
  Future<bool> releaseUsbWhenBackgrounded() =>
      _service.releaseUsbWhenBackgrounded();

  /// Re-claims the USB device after a background release.
  Future<bool> reclaimUsbOnResume() => _service.reclaimUsbOnResume();

  /// Stops the service, detaches the channel and the settings listener.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _attachedHandler?.attachSystemBehaviorHooks(null);
    _attachedHandler = null;
    final VoidCallback? listener = _settingsListener;
    _settingsListener = null;
    if (listener != null) _settings.removeListener(listener);
    try {
      _channel.setMethodCallHandler(null);
    } catch (e, st) {
      ErrorLogger.log(
        'Detaching the system-behaviour channel failed',
        error: e,
        stackTrace: st,
        category: 'SystemBehavior',
      );
    }
    _service.dispose();
  }

  Future<Object?> _onPlatformCall(MethodCall call) async {
    if (_disposed) return null;
    if (call.method == taskRemovedMethod) {
      await _service.handleTaskRemoved();
      return true;
    }
    return null;
  }

  /// Mirrors `stopWhenTaskRemoved` so the native activity listener knows
  /// whether a removed task must stop playback.
  Future<void> _pushTaskPolicy() async {
    if (_disposed) return;
    try {
      await _channel.invokeMethod<bool>(
        setStopWhenTaskRemovedMethod,
        <String, Object>{'enabled': _settings.stopWhenTaskRemoved},
      );
    } on MissingPluginException {
      // Expected in tests and on desktop: no native handler to mirror to.
    } catch (e, st) {
      ErrorLogger.log(
        'Pushing the task-removal policy failed',
        error: e,
        stackTrace: st,
        category: 'SystemBehavior',
      );
    }
  }
}
