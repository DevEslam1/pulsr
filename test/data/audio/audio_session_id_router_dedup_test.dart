// test/audio_session_id_router_dedup_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/audio_session_id_router.dart';

void main() {
  group('AudioSessionIdRouter - Deduplication & Serialization', () {
    test('ignores null session IDs', () {
      var callCount = 0;
      final router = AudioSessionIdRouter(onSessionChanged: (_) => callCount++);

      router.handleSessionId(null);
      expect(callCount, equals(0), reason: 'Null session should be ignored');
    });

    test('ignores zero and negative session IDs', () {
      var callCount = 0;
      final router = AudioSessionIdRouter(onSessionChanged: (_) => callCount++);

      router.handleSessionId(0);
      router.handleSessionId(-1);
      router.handleSessionId(-100);

      expect(
        callCount,
        equals(0),
        reason: 'Zero and negative IDs should be ignored',
      );
    });

    test('accepts first valid session ID', () async {
      int? receivedId;
      final router = AudioSessionIdRouter(
        onSessionChanged: (id) => receivedId = id,
      );

      router.handleSessionId(42);
      await router.idleForTest;

      expect(receivedId, equals(42));
      expect(router.currentSessionId, equals(42));
    });

    test('dedupes identical same-id re-emissions', () async {
      var callCount = 0;
      final router = AudioSessionIdRouter(onSessionChanged: (_) => callCount++);

      router.handleSessionId(42);
      await router.idleForTest;
      expect(callCount, equals(1));

      // Same ID again (simulating BehaviorSubject replay)
      router.handleSessionId(42);
      await router.idleForTest;

      expect(
        callCount,
        equals(1),
        reason: 'Duplicate same-id emission should not trigger callback',
      );
    });

    test('handles different session IDs in sequence', () async {
      final receivedIds = <int>[];
      final router = AudioSessionIdRouter(
        onSessionChanged: (id) => receivedIds.add(id),
      );

      router.handleSessionId(42);
      await router.idleForTest;

      router.handleSessionId(100);
      await router.idleForTest;

      router.handleSessionId(200);
      await router.idleForTest;

      expect(receivedIds, equals([42, 100, 200]));
      expect(router.currentSessionId, equals(200));
    });

    test('collapses out-of-order updates to most recent', () async {
      final receivedIds = <int>[];
      final router = AudioSessionIdRouter(
        onSessionChanged: (id) => receivedIds.add(id),
      );

      // Simulate rapid rapid-fire session changes
      // (while first reattach is in flight)
      router.handleSessionId(42);
      router.handleSessionId(100); // Will be queued
      router.handleSessionId(200); // Will replace 100 in queue
      router.handleSessionId(300); // Will replace 200 in queue

      await router.idleForTest;

      // Only 42 and 300 should be processed; 100 and 200 collapsed
      expect(
        receivedIds.length,
        lessThanOrEqualTo(2),
        reason: 'Out-of-order updates should be collapsed',
      );
      expect(
        receivedIds.last,
        equals(300),
        reason: 'Most recent ID should be applied',
      );
    });

    test('route changed callback fires independently', () async {
      int? sessionId;
      var routeChangedCount = 0;

      final router = AudioSessionIdRouter(
        onSessionChanged: (id) => sessionId = id,
        onRouteChanged: () => routeChangedCount++,
      );

      router.handleSessionId(42);
      await router.idleForTest;
      expect(sessionId, equals(42));

      router.handleRouteChanged();
      await router.idleForTest;

      expect(routeChangedCount, equals(1));
      expect(
        sessionId,
        equals(42),
        reason: 'Route change should not modify session ID',
      );
    });

    test('dedupes concurrent route change events', () async {
      var routeChangedCount = 0;
      final router = AudioSessionIdRouter(
        onSessionChanged: (_) {},
        onRouteChanged: () => routeChangedCount++,
      );

      router.handleRouteChanged();
      router.handleRouteChanged();
      router.handleRouteChanged();

      await router.idleForTest;

      expect(
        routeChangedCount,
        equals(1),
        reason: 'Concurrent route changes should be deduplicated',
      );
    });

    test('reset clears state for test cleanup', () async {
      final router = AudioSessionIdRouter(onSessionChanged: (_) {});

      router.handleSessionId(42);
      await router.idleForTest;
      expect(router.currentSessionId, equals(42));

      router.resetForTest();
      expect(router.currentSessionId, isNull);
    });
  });
}
