import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/audio_effects_channel.dart';
import 'package:pulsr/data/audio/audio_handler.dart';

class _PlaybackPreferencesHarness extends BaseAudioHandler
    with PulsrAudioStreaming {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.pulsr.music/audio_effects');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    AudioEffectsChannel().dispose();
  });

  test('startup skips unavailable playback quality and continues', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      throw PlatformException(code: 'DSP_UNSUPPORTED');
    });
    final handler = _PlaybackPreferencesHarness();
    var initialized = false;
    await handler.setSincResamplerQuality(3);
    initialized = true;

    expect(initialized, isTrue);
    expect(calls, isEmpty);
  });

  test('explicit native quality still reports unsupported rather than success',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'DSP_UNSUPPORTED');
    });
    await expectLater(AudioEffectsChannel().setSincResamplerQuality(3),
        throwsA(isA<PlatformException>()));
  });
}
