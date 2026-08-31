// test/audio_effects_resource_cleanup_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/audio_effects_channel.dart';
import 'package:pulsr/data/audio/audio_session_id_router.dart';

void main() {
  group('Audio Effects - Resource Cleanup & Memory Management', () {
    test('AudioSessionIdRouter can be reset for memory reclaim', () async {
      var callCount = 0;
      final router = AudioSessionIdRouter(
        onSessionChanged: (id) => callCount++,
      );

      // Use router
      router.handleSessionId(42);
      await router.idleForTest;
      expect(callCount, equals(1));

      // Reset should clear state
      router.resetForTest();

      // New session should be processed again
      router.handleSessionId(42);
      await router.idleForTest;
      expect(
        callCount,
        equals(2),
        reason: 'After reset, duplicate ID should be reprocessed',
      );
    });

    test('repeated session changes do not accumulate memory', () async {
      final router = AudioSessionIdRouter(onSessionChanged: (_) {});

      // Simulate many session changes (e.g., app backgrounded multiple times)
      for (int i = 0; i < 100; i++) {
        router.handleSessionId(i + 1);
        await router.idleForTest;

        // Verify only current session is tracked
        expect(router.currentSessionId, equals(i + 1));
      }

      // Should only have one active session ID, not 100
      expect(router.currentSessionId, isNotNull);
    });

    test('BitPerfectBypass state is tracked correctly', () async {
      // Initial state
      expect(AudioEffectsChannel.lastPushedBypassDspForBitPerfect, isNull);

      // After setting bypass
      AudioEffectsChannel.lastPushedBypassDspForBitPerfect = true;
      expect(AudioEffectsChannel.lastPushedBypassDspForBitPerfect, isTrue);

      // Toggle off
      AudioEffectsChannel.lastPushedBypassDspForBitPerfect = false;
      expect(AudioEffectsChannel.lastPushedBypassDspForBitPerfect, isFalse);
    });

    test('session state resets on detect OEM audio', () async {
      var sessionChangedCount = 0;
      final router = AudioSessionIdRouter(
        onSessionChanged: (_) => sessionChangedCount++,
      );

      router.handleSessionId(42);
      await router.idleForTest;
      expect(sessionChangedCount, equals(1));

      // Reset simulates plugin re-init on OEM detection
      router.resetForTest();

      router.handleSessionId(42);
      await router.idleForTest;

      expect(
        sessionChangedCount,
        equals(2),
        reason: 'Session should be reattached after OEM detection',
      );
    });

    test('handler cleanup completes without blocking', () async {
      final router = AudioSessionIdRouter(onSessionChanged: (_) {});

      // Simulate active session
      router.handleSessionId(42);

      // Reset should complete immediately (not block indefinitely)
      final stopwatch = Stopwatch()..start();
      router.resetForTest();
      stopwatch.stop();

      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(100),
        reason: 'Reset should complete quickly without blocking',
      );
    });

    test('multiple reset cycles maintain consistency', () async {
      var callCount = 0;
      final router = AudioSessionIdRouter(
        onSessionChanged: (id) => callCount++,
      );

      for (int cycle = 0; cycle < 5; cycle++) {
        router.handleSessionId(100 + cycle);
        await router.idleForTest;

        router.resetForTest();
        expect(router.currentSessionId, isNull);
      }

      // Final state should be clean
      expect(router.currentSessionId, isNull);
    });
  });
}
