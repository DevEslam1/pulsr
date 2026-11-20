// test/data/audio/equalizer_channel_layout_test.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/data/audio/equalizer_manager.dart';
import 'package:pulsr/domain/models/audio_channel_layout.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(PulsrChannels.audioEffects),
      (call) async => true,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(PulsrChannels.audioEffects),
      null,
    );
  });

  test('channel layout is atomic and refuses unsupported counts', () async {
    final manager = EqualizerManager();
    await manager.setChannelLayout(AudioChannelLayout.fiveOne);
    expect(manager.channelManagerChannelCount, 6);
    expect(manager.lfeChannelIndex, 3);
    expect(manager.channelLayout, AudioChannelLayout.fiveOne);

    await manager.setChannelLayout(AudioChannelLayout.quad);
    expect(manager.channelManagerChannelCount, 4);
    expect(manager.isLfeCrossoverEnabled, isFalse);
    expect(manager.lfeChannelIndex, 0);
    expect(manager.channelLayout, AudioChannelLayout.quad);

    await manager.setChannelLayout(AudioChannelLayout.sevenOne);
    expect(manager.channelManagerChannelCount, 8);
    expect(manager.lfeChannelIndex, 3);
    expect(manager.channelLayout, AudioChannelLayout.sevenOne);

    await expectLater(
      manager.setChannelLayout(AudioChannelLayout.stereo),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('enabling LFE on a no-LFE layout stays off', () async {
    final manager = EqualizerManager();
    await manager.setChannelLayout(AudioChannelLayout.quad);
    await manager.setLfeCrossover(true);
    expect(manager.isLfeCrossoverEnabled, isFalse);
    expect(manager.lfeChannelIndex, 0);

    await manager.setChannelLayout(AudioChannelLayout.fiveOne);
    await manager.setLfeCrossover(true);
    expect(manager.isLfeCrossoverEnabled, isTrue);
    expect(manager.lfeChannelIndex, 3);
  });
}
