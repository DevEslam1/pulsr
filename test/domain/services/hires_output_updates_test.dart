import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/data/services/hires_audio_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(PulsrChannels.hiresDac);
  const events = MethodChannel(PulsrChannels.hiresDacEvents);
  test(
      'failure reasons and capability changes are observable without a rate change',
      () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var reply = <String, Object?>{
      'deviceName': 'Test DAC',
      'isUsbDac': true,
      'sampleRate': 48000,
      'bitDepth': 24,
      'isBitPerfectActive': false,
      'supportedSampleRates': [48000],
    };
    messenger.setMockMethodCallHandler(channel, (_) async => reply);
    messenger.setMockMethodCallHandler(events, (_) async => null);
    final service = HiResAudioService();
    final received = <AudioOutputInfo>[];
    final subscription = service.outputDeviceStream.listen(received.add);
    try {
      await service.getAudioOutputInfo();
      await pumpEventQueue();
      received.clear();
      reply = {
        ...reply,
        'bitPerfectFailureReason': 'target_format_unavailable'
      };
      await service.getAudioOutputInfo();
      await pumpEventQueue();
      expect(
          received.single.bitPerfectFailureReason, 'target_format_unavailable');
      received.clear();
      reply = {
        ...reply,
        'supportedSampleRates': [48000, 96000]
      };
      await service.getAudioOutputInfo();
      await pumpEventQueue();
      expect(received.single.supportedSampleRates, [48000, 96000]);
      await service.getAudioOutputInfo();
      await pumpEventQueue();
      expect(received, hasLength(1));
    } finally {
      await subscription.cancel();
      service.dispose();
      messenger.setMockMethodCallHandler(channel, null);
      messenger.setMockMethodCallHandler(events, null);
    }
  });
}
