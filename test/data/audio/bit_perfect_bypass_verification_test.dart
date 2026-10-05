import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/data/audio/audio_effects_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(PulsrChannels.audioEffects);
  final calls = <MethodCall>[];
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls.clear();
    AudioEffectsChannel.lastPushedBypassDspForBitPerfect = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test('ON/OFF/ON reaches native with DoP state and records acknowledgments',
      () async {
    final effects = AudioEffectsChannel();
    await effects.setBypassDspForBitPerfect(true, isDop: true);
    expect(AudioEffectsChannel.lastPushedBypassDspForBitPerfect, true);
    await effects.setBypassDspForBitPerfect(false, isDop: false);
    expect(AudioEffectsChannel.lastPushedBypassDspForBitPerfect, false);
    await effects.setBypassDspForBitPerfect(true, isDop: false);
    expect(
        calls.map((c) => c.method), everyElement('setBypassDspForBitPerfect'));
    expect(calls.map((c) => c.arguments).toList(), [
      {'bypass': true, 'isDop': true},
      {'bypass': false, 'isDop': false},
      {'bypass': true, 'isDop': false},
    ]);
  });
  test('native exception does not record an unapplied bypass state', () async {
    await AudioEffectsChannel().setBypassDspForBitPerfect(true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'DSP_FAILURE');
    });
    await expectLater(AudioEffectsChannel().setBypassDspForBitPerfect(false),
        throwsA(isA<PlatformException>()));
    expect(AudioEffectsChannel.lastPushedBypassDspForBitPerfect, true);
  });
  for (final rejection in [
    false,
    {'applied': false}
  ]) {
    test('native rejection $rejection is propagated', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => rejection);
      await expectLater(AudioEffectsChannel().setBypassDspForBitPerfect(true),
          throwsStateError);
      expect(AudioEffectsChannel.lastPushedBypassDspForBitPerfect, isNull);
    });
  }
  test('unsupported platforms do not claim a native bypass change', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await AudioEffectsChannel().setBypassDspForBitPerfect(true);
    expect(calls, isEmpty);
    expect(AudioEffectsChannel.lastPushedBypassDspForBitPerfect, isNull);
  });
}
