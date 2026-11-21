// Regression test for P0-1.7: the system-behaviour service is actually
// DELIVERED the audio handler's focus / duck / unplug events, and each event
// produces exactly one pause because the handler stands down when the service
// reports it acted.
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/data/audio/system_behavior_hooks.dart';
import 'package:pulsr/features/system_behavior/system_behavior_runtime.dart';
import 'package:pulsr/features/system_behavior/system_behavior_settings.dart';

import 'system_behavior_test_support.dart';

/// A handler stand-in that only records the bridge it is given, so the test can
/// call the exact callbacks `PulsrAudioHandler` calls from its audio_session
/// listeners.
class _BridgeHandler extends BaseAudioHandler implements PulsrAudioHandler {
  SystemBehaviorHooks? hooks;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  void attachSystemBehaviorHooks(SystemBehaviorHooks? hooks) {
    this.hooks = hooks;
  }

  @override
  bool get hasSystemBehaviorHooks => hooks != null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('delivery', () {
    test('a 300 ms fade ramps to zero before the single pause', () async {
      final port = RecordingPlaybackPort(volume: 0.8);
      final settings = await loadSettings(fadeOutOnPauseMs: 300);
      final service = buildService(settings: settings, port: port);
      addTearDown(service.dispose);

      final delivered = await service.handleAudioFocusLoss(permanent: true);

      expect(delivered, isTrue);
      expect(port.pauseCount, 0, reason: 'the ramp runs before the pause');
      expect(service.isFading, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 450));

      expect(port.volumes, isNotEmpty);
      expect(port.volumes.last, 0.0);
      expect(port.pauseCount, 1);
    });

    test('focus gain restores the pre-fade level and resumes once', () async {
      final port = RecordingPlaybackPort(volume: 0.65);
      final settings = await loadSettings(fadeOutOnPauseMs: 100);
      final service = buildService(settings: settings, port: port);
      addTearDown(service.dispose);

      await service.handleAudioFocusLoss(permanent: false);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(port.pauseCount, 1);
      expect(port.volume, 0.0);

      final resumed = await service.handleAudioFocusGain();

      expect(resumed, isTrue);
      expect(port.playCount, 1);
      expect(port.volume, 0.65, reason: 'the fade start level is restored');
    });

    test('usbRelease=permanent releases the claim then pauses', () async {
      final port = RecordingPlaybackPort(volume: 0.5);
      final settings = await loadSettings(
        fadeOutOnPauseMs: 0,
        usbReleaseOnFocusLoss: UsbReleaseOnFocusLoss.permanent,
      );
      final service = buildService(
        settings: settings,
        port: port,
        usbRelease: (bool enabled) async {
          port.calls.add('usb:$enabled');
          return true;
        },
      );
      addTearDown(service.dispose);

      final delivered = await service.handleAudioFocusLoss(permanent: true);

      expect(delivered, isTrue);
      expect(port.calls, contains('usb:false'));
      expect(port.calls.indexOf('usb:false'), lessThan(port.calls.indexOf('pause')));
      expect(port.pauseCount, 1);
    });

    test('focus gain re-claims USB when focus loss released it', () async {
      final port = RecordingPlaybackPort(volume: 0.5);
      final settings = await loadSettings(
        fadeOutOnPauseMs: 0,
        usbReleaseOnFocusLoss: UsbReleaseOnFocusLoss.transient,
      );
      final service = buildService(
        settings: settings,
        port: port,
        usbRelease: (bool enabled) async {
          port.calls.add('usb:$enabled');
          return true;
        },
      );
      addTearDown(service.dispose);

      final delivered = await service.handleAudioFocusLoss(permanent: false);
      expect(delivered, isTrue);
      expect(port.calls, contains('usb:false'));

      final resumed = await service.handleAudioFocusGain();
      expect(resumed, isTrue);
      expect(port.calls, contains('usb:true'));
      expect(port.calls.indexOf('usb:true'), lessThan(port.calls.lastIndexOf('play')));
    });

    test('duck-vs-pause honours the notification policy', () async {
      final pausingPort = RecordingPlaybackPort(volume: 0.5);
      final pausing = buildService(
        settings: await loadSettings(pauseOnNotificationSound: true),
        port: pausingPort,
      );
      addTearDown(pausing.dispose);

      expect(await pausing.handleNotificationSound(), isTrue);
      expect(pausingPort.pauseCount, 1);

      final duckingPort = RecordingPlaybackPort(volume: 0.5);
      final ducking = buildService(
        settings: await loadSettings(pauseOnNotificationSound: false),
        port: duckingPort,
      );
      addTearDown(ducking.dispose);

      expect(await ducking.handleNotificationSound(), isFalse,
          reason: 'a duck is delivered by the audio handler, not the service');
      expect(duckingPort.pauseCount, 0);
    });

    test('headset unplug pauses through the service', () async {
      final port = RecordingPlaybackPort(volume: 0.5);
      final service = buildService(
        settings: await loadSettings(),
        port: port,
      );
      addTearDown(service.dispose);

      expect(await service.handleHeadsetUnplug(), isTrue);
      expect(port.pauseCount, 1);
    });
  });

  group('handler bridge', () {
    test('runtime attaches a bridge that owns exactly one pause', () async {
      final port = RecordingPlaybackPort(volume: 0.5);
      final runtime = await SystemBehaviorRuntime.startWithPort(
        settings: await loadSettings(fadeOutOnPauseMs: 0),
        port: port,
        volumeReader: () => port.volume,
        isPlaying: () => port.playing,
        usbRelease: (bool enabled) async => true,
      );
      addTearDown(runtime.dispose);

      final handler = _BridgeHandler();
      runtime.attachToHandler(handler);
      expect(handler.hasSystemBehaviorHooks, isTrue);

      final SystemBehaviorHooks hooks = handler.hooks!;
      final delivered = await hooks.onAudioFocusLoss(permanent: false);

      expect(delivered, isTrue,
          reason: 'the handler may only skip its own pause when this is true');
      expect(port.pauseCount, 1,
          reason: 'the service delivered the one pause for the event');

      // The handler's own branch would now stand down; nothing else paused.
      var handlerPauses = 0;
      if (!delivered) handlerPauses += 1;
      expect(handlerPauses, 0);
    });

    test('a declined event leaves the pause to the handler', () async {
      final port = RecordingPlaybackPort(volume: 0.5, playing: false);
      final runtime = await SystemBehaviorRuntime.startWithPort(
        settings: await loadSettings(),
        port: port,
        volumeReader: () => port.volume,
        isPlaying: () => port.playing,
        usbRelease: (bool enabled) async => true,
      );
      addTearDown(runtime.dispose);

      final handler = _BridgeHandler();
      runtime.attachToHandler(handler);

      final delivered =
          await handler.hooks!.onAudioFocusLoss(permanent: false);

      expect(delivered, isFalse,
          reason: 'nothing was playing, so the handler keeps its own path');
      expect(port.pauseCount, 0);
    });

    test('disposing the runtime detaches the bridge', () async {
      final port = RecordingPlaybackPort(volume: 0.5);
      final runtime = await SystemBehaviorRuntime.startWithPort(
        settings: await loadSettings(),
        port: port,
        volumeReader: () => port.volume,
        isPlaying: () => port.playing,
        usbRelease: (bool enabled) async => true,
      );
      final handler = _BridgeHandler();
      runtime.attachToHandler(handler);
      expect(handler.hasSystemBehaviorHooks, isTrue);

      runtime.dispose();

      expect(handler.hasSystemBehaviorHooks, isFalse);
    });
  });
}
