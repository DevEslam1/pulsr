// test/features/system_behavior/system_behavior_runtime_test.dart
//
// Runtime wiring: the composition root must actually construct the service,
// mirror the task-removal policy to the native side, execute a native
// `taskRemoved` signal through the playback port, keep the USB claim while
// playback runs, and detach everything on dispose. A recording port stands in
// for the real audio handler, which cannot be constructed without the app's
// repositories.
import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/system_behavior/system_behavior_runtime.dart';
import 'package:pulsr/features/system_behavior/system_behavior_service.dart';
import 'package:pulsr/features/system_behavior/system_behavior_settings.dart';

import 'system_behavior_test_support.dart';

/// A fake audio handler: records transport calls and publishes playback state.
class _FakeAudioHandler extends BaseAudioHandler {
  final List<String> actions = <String>[];
  double? writtenVolume;

  void _setPlaying(bool playing) {
    playbackState.add(playbackState.value.copyWith(playing: playing));
  }

  @override
  Future<void> play() async {
    actions.add('play');
    _setPlaying(true);
  }

  @override
  Future<void> pause() async {
    actions.add('pause');
    _setPlaying(false);
  }

  @override
  Future<void> stop() async {
    actions.add('stop');
    _setPlaying(false);
  }

  @override
  Future<void> skipToNext() async {
    actions.add('next');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('test/system_behavior');
  late List<MethodCall> outbound;
  late List<bool> usbCalls;

  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    outbound = <MethodCall>[];
    usbCalls = <bool>[];
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      outbound.add(call);
      return true;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  /// Delivers an inbound platform message, the way the Kotlin plugin would.
  Future<void> deliver(MethodCall call) async {
    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(call),
      (ByteData? data) {},
    );
  }

  Future<SystemBehaviorRuntime> build(
    SystemBehaviorSettings settings,
    RecordingPlaybackPort port,
  ) {
    return SystemBehaviorRuntime.startWithPort(
      settings: settings,
      port: port,
      volumeReader: () => port.volume,
      isPlaying: () => port.playing,
      resumePlayback: port.play,
      usbRelease: (bool enabled) async {
        usbCalls.add(enabled);
        return true;
      },
      channel: channel,
    );
  }

  test('start constructs the service and mirrors the task policy', () async {
    final SystemBehaviorSettings settings =
        await loadSettings(stopWhenTaskRemoved: true);
    final RecordingPlaybackPort port = RecordingPlaybackPort();

    final SystemBehaviorRuntime runtime = await build(settings, port);
    await pumpEventQueue();

    expect(runtime.isStarted, isTrue);
    final List<MethodCall> policies = outbound
        .where((MethodCall call) =>
            call.method == SystemBehaviorRuntime.setStopWhenTaskRemovedMethod)
        .toList();
    expect(policies, hasLength(1));
    expect((policies.single.arguments as Map<Object?, Object?>)['enabled'],
        isTrue);
    runtime.dispose();
  });

  test('a native taskRemoved stops playback when configured', () async {
    final SystemBehaviorSettings settings =
        await loadSettings(stopWhenTaskRemoved: true);
    final RecordingPlaybackPort port = RecordingPlaybackPort();
    final SystemBehaviorRuntime runtime = await build(settings, port);

    await deliver(const MethodCall(SystemBehaviorRuntime.taskRemovedMethod));
    await pumpEventQueue();

    expect(port.stopCount, 1);
    expect(port.pauseCount, 0);
    runtime.dispose();
  });

  test('a native taskRemoved pauses when the setting is off', () async {
    final SystemBehaviorSettings settings = await loadSettings();
    final RecordingPlaybackPort port = RecordingPlaybackPort();
    final SystemBehaviorRuntime runtime = await build(settings, port);

    await deliver(const MethodCall(SystemBehaviorRuntime.taskRemovedMethod));
    await pumpEventQueue();

    expect(port.stopCount, 0);
    expect(port.pauseCount, 1);
    runtime.dispose();
  });

  test('a settings change re-mirrors the task policy', () async {
    final SystemBehaviorSettings settings = await loadSettings();
    final RecordingPlaybackPort port = RecordingPlaybackPort();
    final SystemBehaviorRuntime runtime = await build(settings, port);
    await pumpEventQueue();
    outbound.clear();

    await settings.setStopWhenTaskRemoved(true);
    await pumpEventQueue();

    final List<MethodCall> policies = outbound
        .where((MethodCall call) =>
            call.method == SystemBehaviorRuntime.setStopWhenTaskRemovedMethod)
        .toList();
    expect(policies, isNotEmpty);
    final MethodCall last = policies.last;
    expect((last.arguments as Map<Object?, Object?>)['enabled'], isTrue);
    runtime.dispose();
  });

  test('background release keeps the claim while playback is running',
      () async {
    final SystemBehaviorSettings settings =
        await loadSettings(closeUsbWhenBackgrounded: true);
    final RecordingPlaybackPort port = RecordingPlaybackPort(playing: true);
    final SystemBehaviorRuntime runtime = await build(settings, port);

    expect(await runtime.releaseUsbWhenBackgrounded(), isFalse);
    expect(usbCalls, isEmpty);

    port.playing = false;
    expect(await runtime.releaseUsbWhenBackgrounded(), isTrue);
    expect(usbCalls, <bool>[false]);
    expect(await runtime.reclaimUsbOnResume(), isTrue);
    expect(usbCalls, <bool>[false, true]);
    runtime.dispose();
  });

  test('dispose detaches the channel and the service', () async {
    final SystemBehaviorSettings settings =
        await loadSettings(stopWhenTaskRemoved: true);
    final RecordingPlaybackPort port = RecordingPlaybackPort();
    final SystemBehaviorRuntime runtime = await build(settings, port);
    await pumpEventQueue();

    runtime.dispose();
    await deliver(const MethodCall(SystemBehaviorRuntime.taskRemovedMethod));
    await pumpEventQueue();

    expect(port.calls, isEmpty);
    expect(runtime.isStarted, isFalse);
  });

  test('the real port drives the handler transport and volume', () async {
    final _FakeAudioHandler handler = _FakeAudioHandler();
    final AudioHandlerSystemPlaybackPort port = AudioHandlerSystemPlaybackPort(
      handler,
      volume: AudioHandlerVolumeControls(
        read: () => handler.writtenVolume ?? 0.4,
        write: (double volume) async => handler.writtenVolume = volume,
      ),
    );

    expect(port.isPlaying, isFalse);
    expect(port.playbackState.playing, isFalse);

    await port.play();
    expect(handler.actions, <String>['play']);
    expect(port.isPlaying, isTrue);

    await port.pause();
    expect(port.isPlaying, isFalse);

    await port.next();
    await port.setVolume(0.25);
    await port.stop();

    expect(handler.actions, <String>['play', 'pause', 'next', 'stop']);
    expect(port.currentVolume, 0.25);
  });

  test('start wires the adapter over a real AudioHandler', () async {
    final SystemBehaviorSettings settings =
        await loadSettings(stopWhenTaskRemoved: true);
    final _FakeAudioHandler handler = _FakeAudioHandler();
    final SystemBehaviorRuntime runtime = await SystemBehaviorRuntime.start(
      settings: settings,
      handler: handler,
      readVolume: () => 0.5,
      writeVolume: (double volume) async => handler.writtenVolume = volume,
      channel: channel,
    );
    await pumpEventQueue();

    expect(runtime.isStarted, isTrue);
    await deliver(const MethodCall(SystemBehaviorRuntime.taskRemovedMethod));
    await pumpEventQueue();
    expect(handler.actions, <String>['stop']);

    runtime.dispose();
  });
}
