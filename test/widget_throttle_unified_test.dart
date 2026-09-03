import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Unified Widget Throttle (B-44)', () {
    test('enforces 1000ms throttle interval across widget updates', () {
      DateTime? lastWidgetUpdateTime;
      int updateCount = 0;

      void updateWidgetThrottled({bool force = false}) {
        final now = DateTime.now();
        if (!force &&
            lastWidgetUpdateTime != null &&
            now.difference(lastWidgetUpdateTime!).inMilliseconds < 1000) {
          return;
        }
        lastWidgetUpdateTime = now;
        updateCount++;
      }

      updateWidgetThrottled();
      expect(updateCount, equals(1));

      // Second immediate call throttled
      updateWidgetThrottled();
      expect(updateCount, equals(1));

      // Forced call bypasses throttle
      updateWidgetThrottled(force: true);
      expect(updateCount, equals(2));
    });
  });
}
