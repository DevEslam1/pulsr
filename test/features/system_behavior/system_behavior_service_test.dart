// test/features/system_behavior/system_behavior_service_test.dart
//
// Delivery behaviour: given a settings snapshot and one platform event, which
// port calls (and which USB release) must happen, and in which order. Audio
// focus bookkeeping stays in PlaybackInterruptionManager, so these tests assert
// that its "don't pause when nothing is playing" guard survives the wiring.

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/system_behavior/system_behavior_service.dart';
import 'package:pulsr/features/system_behavior/system_behavior_settings.dart';

import 'system_behavior_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('permanent focus loss pauses and keeps the USB claim by default',
      () async {
    final SystemBehaviorSettings settings = await loadSettings();
    final RecordingPlaybackPort port = RecordingPlaybackPort();
    final List<bool> usbCalls = <bool>[];
    final SystemBehaviorService service = buildService(
      settings: settings,
      port: port,
      usbRelease: (bool enabled) async {
        usbCalls.add(enabled);
        return true;
      },
    );

    await service.handleAudioFocusLoss(permanent: true);

    expect(port.calls, <String>['pause']);
    expect(usbCalls, isEmpty);
    service.dispose();
  });

  test('permanent focus loss releases the USB claim first when configured',
      () async {
    final SystemBehaviorSettings settings = await loadSettings(
      usbReleaseOnFocusLoss: UsbReleaseOnFocusLoss.permanent,
    );
    final RecordingPlaybackPort port = RecordingPlaybackPort();
    final List<String> order = <String>[];
    final SystemBehaviorService service = buildService(
      settings: settings,
      port: port,
      usbRelease: (bool enabled) async {
        order.add('usb:$enabled');
        return true;
      },
    );

    await service.handleAudioFocusLoss(permanent: true);

    expect(order, <String>['usb:false']);
    expect(port.calls, <String>['pause']);
    service.dispose();
  });

  test('transient focus loss only releases the claim for the transient policy',
      () async {
    final SystemBehaviorSettings transientPolicy = await loadSettings(
      usbReleaseOnFocusLoss: UsbReleaseOnFocusLoss.transient,
    );
    final RecordingPlaybackPort transientPort = RecordingPlaybackPort();
    final List<bool> transientUsb = <bool>[];
    final SystemBehaviorService transientService = buildService(
      settings: transientPolicy,
      port: transientPort,
      usbRelease: (bool enabled) async {
        transientUsb.add(enabled);
        return true;
      },
    );
    await transientService.handleAudioFocusLoss(permanent: false);
    expect(transientUsb, <bool>[false]);
    expect(transientPort.calls, <String>['pause']);
    transientService.dispose();

    final SystemBehaviorSettings permanentPolicy = await loadSettings(
      usbReleaseOnFocusLoss: UsbReleaseOnFocusLoss.permanent,
    );
    final RecordingPlaybackPort permanentPort = RecordingPlaybackPort();
    final List<bool> permanentUsb = <bool>[];
    final SystemBehaviorService permanentService = buildService(
      settings: permanentPolicy,
      port: permanentPort,
      usbRelease: (bool enabled) async {
        permanentUsb.add(enabled);
        return true;
      },
    );
    await permanentService.handleAudioFocusLoss(permanent: false);
    expect(permanentUsb, isEmpty);
    expect(permanentPort.calls, <String>['pause']);
    permanentService.dispose();
  });

  test('focus loss while paused does nothing', () async {
    final SystemBehaviorSettings settings = await loadSettings(
      usbReleaseOnFocusLoss: UsbReleaseOnFocusLoss.permanent,
    );
    final RecordingPlaybackPort port = RecordingPlaybackPort();
    final List<bool> usbCalls = <bool>[];
    final SystemBehaviorService service = buildService(
      settings: settings,
      port: port,
      playing: false,
      usbRelease: (bool enabled) async {
        usbCalls.add(enabled);
        return true;
      },
    );

    await service.handleAudioFocusLoss(permanent: true);
    await service.handleAudioFocusLoss(permanent: false);
    await service.handleHeadsetUnplug();

    expect(port.calls, isEmpty);
    expect(usbCalls, isEmpty);
    service.dispose();
  });

  test('focus gain resumes once when resumeAfterCall is on', () async {
    final SystemBehaviorSettings settings = await loadSettings();
    final RecordingPlaybackPort port = RecordingPlaybackPort();
    int resumes = 0;
    final SystemBehaviorService service = buildService(
      settings: settings,
      port: port,
      resumePlayback: () async => resumes += 1,
    );

    await service.handleAudioFocusLoss(permanent: true);
    await service.handleAudioFocusGain();

    expect(port.calls, <String>['pause']);
    expect(resumes, 1);
    service.dispose();
  });

  test('focus gain does not resume when resumeAfterCall is off', () async {
    final SystemBehaviorSettings settings =
        await loadSettings(resumeAfterCall: false);
    final RecordingPlaybackPort port = RecordingPlaybackPort();
    int resumes = 0;
    final SystemBehaviorService service = buildService(
      settings: settings,
      port: port,
      resumePlayback: () async => resumes += 1,
    );

    await service.handleAudioFocusLoss(permanent: true);
    await service.handleAudioFocusGain();

    expect(resumes, 0);
    service.dispose();
  });

  test('a faded pause restores the exact volume before resuming', () async {
    final SystemBehaviorSettings settings =
        await loadSettings(fadeOutOnPauseMs: 640);
    final RecordingPlaybackPort port = RecordingPlaybackPort(volume: 0.61);
    int resumes = 0;
    final SystemBehaviorService service = buildService(
      settings: settings,
      port: port,
      resumePlayback: () async => resumes += 1,
    );

    fakeAsync((FakeAsync async) {
      service.handleAudioFocusLoss(permanent: true);
      async.elapse(const Duration(milliseconds: 640));
      async.flushMicrotasks();
      expect(port.pauseCount, 1);
      expect(port.volumes.last, 0.0);

      service.handleAudioFocusGain();
      async.flushMicrotasks();
      expect(port.volumes.last, 0.61);
      expect(resumes, 1);
    });

    service.dispose();
  });

  test('task removal pauses by default and stops when configured', () async {
    final SystemBehaviorSettings pauseSettings = await loadSettings();
    final RecordingPlaybackPort pausePort = RecordingPlaybackPort();
    final SystemBehaviorService pauseService =
        buildService(settings: pauseSettings, port: pausePort);
    await pauseService.handleTaskRemoved();
    expect(pausePort.calls, <String>['pause']);
    pauseService.dispose();

    final SystemBehaviorSettings stopSettings =
        await loadSettings(stopWhenTaskRemoved: true);
    final RecordingPlaybackPort stopPort = RecordingPlaybackPort();
    final SystemBehaviorService stopService =
        buildService(settings: stopSettings, port: stopPort);
    await stopService.handleTaskRemoved();
    expect(stopPort.calls, <String>['stop']);
    stopService.dispose();
  });

  test('volume double press skips only when the switch is on', () async {
    final SystemBehaviorSettings offSettings = await loadSettings();
    final RecordingPlaybackPort offPort = RecordingPlaybackPort();
    final SystemBehaviorService offService =
        buildService(settings: offSettings, port: offPort);
    await offService.handleVolumeKeyDoublePress();
    expect(offPort.calls, isEmpty);
    offService.dispose();

    final SystemBehaviorSettings onSettings =
        await loadSettings(volumeRockerTrackSwitch: true);
    final RecordingPlaybackPort onPort = RecordingPlaybackPort();
    final SystemBehaviorService onService =
        buildService(settings: onSettings, port: onPort);
    await onService.handleVolumeKeyDoublePress();
    expect(onPort.calls, <String>['next']);
    onService.dispose();
  });

  test('a headset unplug pauses once and debounces the duplicate event',
      () async {
    final SystemBehaviorSettings settings = await loadSettings();
    final RecordingPlaybackPort port = RecordingPlaybackPort();
    final DateTime now = DateTime(2026, 11, 16, 12);
    final SystemBehaviorService service = buildService(
      settings: settings,
      port: port,
      clock: () => now,
    );

    await service.handleHeadsetUnplug();
    await service.handleHeadsetUnplug();

    expect(port.calls, <String>['pause']);
    service.dispose();
  });

  test('backgrounding releases the USB claim only when configured', () async {
    final SystemBehaviorSettings offSettings = await loadSettings();
    final List<bool> offCalls = <bool>[];
    final SystemBehaviorService offService = buildService(
      settings: offSettings,
      port: RecordingPlaybackPort(),
      usbRelease: (bool enabled) async {
        offCalls.add(enabled);
        return true;
      },
    );
    await offService.handleAppBackgrounded();
    expect(offCalls, isEmpty);
    offService.dispose();

    final SystemBehaviorSettings onSettings =
        await loadSettings(closeUsbWhenBackgrounded: true);
    final List<bool> onCalls = <bool>[];
    final SystemBehaviorService onService = buildService(
      settings: onSettings,
      port: RecordingPlaybackPort(),
      usbRelease: (bool enabled) async {
        onCalls.add(enabled);
        return true;
      },
    );
    await onService.handleAppBackgrounded();
    expect(onCalls, <bool>[false]);
    onService.dispose();
  });

  test('a notification-sound pause keeps the USB claim', () async {
    final SystemBehaviorSettings settings = await loadSettings(
      usbReleaseOnFocusLoss: UsbReleaseOnFocusLoss.transient,
    );
    final RecordingPlaybackPort port = RecordingPlaybackPort();
    final List<bool> usbCalls = <bool>[];
    final SystemBehaviorService service = buildService(
      settings: settings,
      port: port,
      usbRelease: (bool enabled) async {
        usbCalls.add(enabled);
        return true;
      },
    );

    await service.handleNotificationSound();

    expect(port.calls, <String>['pause']);
    expect(usbCalls, isEmpty);
    service.dispose();
  });

  test('ducking instead of pausing does nothing', () async {
    final SystemBehaviorSettings settings =
        await loadSettings(pauseOnNotificationSound: false);
    final RecordingPlaybackPort port = RecordingPlaybackPort();
    final SystemBehaviorService service =
        buildService(settings: settings, port: port);

    await service.handleNotificationSound();

    expect(port.calls, isEmpty);
    service.dispose();
  });

  test('a disposed service ignores further events', () async {
    final SystemBehaviorSettings settings = await loadSettings();
    final RecordingPlaybackPort port = RecordingPlaybackPort();
    final SystemBehaviorService service =
        buildService(settings: settings, port: port);

    service.dispose();
    await service.handleAudioFocusLoss(permanent: true);
    await service.handleTaskRemoved();
    await service.handleHeadsetUnplug();

    expect(port.calls, isEmpty);
    expect(service.isStarted, isFalse);
  });
}
