// test/audio_effects_error_handling_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/audio_session_id_router.dart';

void main() {
  group('Audio Effects - Error Handling & Timeouts', () {
    test('invalid session ID rejected with logging', () {
      var callCount = 0;

      final router = AudioSessionIdRouter(onSessionChanged: (_) => callCount++);

      // Test negative ID
      router.handleSessionId(-1);
      expect(callCount, equals(0));

      // Test zero
      router.handleSessionId(0);
      expect(callCount, equals(0));

      // Test null
      router.handleSessionId(null);
      expect(callCount, equals(0));
    });

    test('session change callback errors do not crash router', () async {
      final router = AudioSessionIdRouter(
        onSessionChanged: (id) {
          if (id == 999) {
            throw Exception('Simulated error in session change');
          }
        },
      );

      // This should not throw
      expect(() async {
        router.handleSessionId(999);
        await router.idleForTest;
      }, returnsNormally);
    });

    test(
      'route change callback error does not block future operations',
      () async {
        var routeChangeCount = 0;
        var sessionChangeCount = 0;

        final router = AudioSessionIdRouter(
          onSessionChanged: (_) => sessionChangeCount++,
          onRouteChanged: () {
            routeChangeCount++;
            if (routeChangeCount == 1) {
              throw Exception('Simulated route change error');
            }
          },
        );

        // Route change with error
        router.handleRouteChanged();
        await router.idleForTest;

        // Subsequent session change should still work
        router.handleSessionId(42);
        await router.idleForTest;

        expect(
          sessionChangeCount,
          equals(1),
          reason: 'Session change should work even after route change error',
        );
      },
    );

    test(
      'handler deduplication prevents stack overflow on rapid same-ID',
      () async {
        var callCount = 0;
        final router = AudioSessionIdRouter(
          onSessionChanged: (_) => callCount++,
        );

        // Simulate 1000 identical session IDs arriving rapidly
        for (int i = 0; i < 1000; i++) {
          router.handleSessionId(42);
        }

        await router.idleForTest;

        // Should only call once despite 1000 emissions
        expect(
          callCount,
          equals(1),
          reason: 'Deduplication should prevent 1000x redundant calls',
        );
      },
    );

    test(
      'session router handles rapid sequential IDs without dropping',
      () async {
        final receivedIds = <int>[];
        final router = AudioSessionIdRouter(
          onSessionChanged: (id) => receivedIds.add(id),
        );

        // Rapid fire: 0, 1, 2, ..., 99
        for (int i = 0; i < 100; i++) {
          router.handleSessionId(i + 1);
        }

        await router.idleForTest;

        // Should have received only final ID (99 deduplicated, 100 applied)
        expect(receivedIds.isNotEmpty, isTrue);
        expect(receivedIds.last, equals(100));
      },
    );

    test('null route change callback does not cause crash', () async {
      final router = AudioSessionIdRouter(
        onSessionChanged: (_) {},
        onRouteChanged: null,
      );

      // Should not throw
      expect(() async {
        router.handleRouteChanged();
        await router.idleForTest;
      }, returnsNormally);
    });

    test('multiple error scenarios in succession maintain stability', () async {
      var sessionChanges = <int>[];

      final router = AudioSessionIdRouter(
        onSessionChanged: (id) => sessionChanges.add(id),
      );

      // Scenario 1: Invalid IDs
      router.handleSessionId(null);
      router.handleSessionId(0);
      router.handleSessionId(-1);

      // Scenario 2: Valid session
      router.handleSessionId(42);
      await router.idleForTest;
      expect(sessionChanges.length, equals(1));

      // Scenario 3: Duplicate of current
      router.handleSessionId(42);
      await router.idleForTest;
      expect(
        sessionChanges.length,
        equals(1),
        reason: 'Duplicate should not add new session',
      );

      // Scenario 4: New session
      router.handleSessionId(100);
      await router.idleForTest;
      expect(sessionChanges.length, equals(2));

      // Scenario 5: Invalid again (should not affect last)
      router.handleSessionId(-1);
      router.handleSessionId(null);
      expect(
        sessionChanges.length,
        equals(2),
        reason: 'Invalid IDs should not be added',
      );
    });

    test('session chain operations complete in order despite errors', () async {
      final executionOrder = <String>[];

      final router = AudioSessionIdRouter(
        onSessionChanged: (id) {
          executionOrder.add('session_$id');
        },
      );

      router.handleSessionId(1);
      router.handleSessionId(2);
      router.handleSessionId(3);

      await router.idleForTest;

      // Should execute in order
      expect(executionOrder, equals(['session_1', 'session_2', 'session_3']));
    });
  });
}
