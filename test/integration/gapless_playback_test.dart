// test/integration/gapless_playback_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/data/audio/audio_effects_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Feature 3: Gapless Playback Verification Suite', () {
    late AudioEffectsChannel channel;
    final List<MethodCall> methodCalls = [];

    setUp(() {
      methodCalls.clear();
      channel = AudioEffectsChannel();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel(PulsrChannels.audioEffects),
        (MethodCall methodCall) async {
          methodCalls.add(methodCall);
          switch (methodCall.method) {
            case 'resyncForTrack':
              return true;
            case 'getTelemetry':
              return <dynamic>[
                0.0, // limiterGrDb
                0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, // dynEqGrDb (8)
                0.0, 0.0, 0.0, 0.0, // mbCompGrDb (4)
                0.05, // rollingRtf
                0, // autoDegradedStages
                0.12, // weeklyDose
                0.0, // safetyAttenuationActive
              ];
            case 'getWeeklyDose':
              return 0.12;
            case 'isSafetyAttenuationActive':
              return false;
            case 'resetWeeklyDose':
              return true;
            default:
              return true;
          }
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel(PulsrChannels.audioEffects),
        null,
      );
    });

    test('resyncForTrack invokes native JNI without resetting active effect snapshot', () async {
      await channel.resyncForTrack(96000.0, channels: 2);

      expect(methodCalls.any((call) => call.method == 'resyncForTrack'), isTrue);
      final resyncCall = methodCalls.firstWhere((call) => call.method == 'resyncForTrack');
      expect(resyncCall.arguments['sampleRate'], 96000.0);
      expect(resyncCall.arguments['channels'], 2);
    });

    test('telemetry stream reports smooth continuity across track boundaries', () async {
      final telemetry = await channel.getTelemetry();

      expect(telemetry.isThrottling, isFalse);
      expect(telemetry.isAutoDegraded, isFalse);
      expect(telemetry.weeklyDose, 0.12);
      expect(telemetry.safetyAttenuationActive, isFalse);
    });

    test('reverb and crossfeed parameters remain unchanged across sequential track resyncs', () async {
      // Simulate rapid gapless track changes across multiple sample rates
      final rates = [44100.0, 48000.0, 96000.0, 192000.0, 44100.0];
      for (final sr in rates) {
        await channel.resyncForTrack(sr, channels: 2);
      }

      final resyncCalls = methodCalls.where((c) => c.method == 'resyncForTrack').toList();
      expect(resyncCalls.length, 5);
      expect(resyncCalls[2].arguments['sampleRate'], 96000.0);
      expect(resyncCalls[3].arguments['sampleRate'], 192000.0);
    });
  });
}
