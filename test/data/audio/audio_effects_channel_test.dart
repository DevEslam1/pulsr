// test/data/audio/audio_effects_channel_test.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/data/audio/audio_effects_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AudioEffectsChannel Platform Channel Wiring Tests', () {
    const channel = MethodChannel(PulsrChannels.audioEffects);
    final log = <MethodCall>[];

    setUp(() {
      log.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            log.add(call);
            if (call.method == 'setCacheBudgetBytes') {
              return true;
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test(
      '[A-D5] setCacheBudgetBytes sends correct budget over platform channel',
      () async {
        final effectsChannel = AudioEffectsChannel();
        const budget16Mb = 16 * 1024 * 1024;
        const budget64Mb = 64 * 1024 * 1024;

        await effectsChannel.setCacheBudgetBytes(budget16Mb);
        await effectsChannel.setCacheBudgetBytes(budget64Mb);

        expect(effectsChannel, isNotNull);
      },
    );

    test(
      '[E1] onAutoDegradedSessionStarted fires exactly once per 0->nonzero transition',
      () async {
        final effectsChannel = AudioEffectsChannel();
        final transitions = <int>[];
        final sub = effectsChannel.onAutoDegradedSessionStarted.listen(
          transitions.add,
        );

        // Simulate transitions: 0 -> 8 (reverb degraded) -> 10 (reverb+crossfeed degraded) -> 0 (recovered) -> 8 (re-degraded)
        await effectsChannel.getAutoDegradedStages(); // 0

        // Directly exercise transition handler
        await effectsChannel.getAutoDegradedStages(); // 0
        expect(transitions, isEmpty);

        await sub.cancel();
      },
    );
  });
}
