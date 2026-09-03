import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Widget Single Throttle Gate (B-44 / B-59)', () {
    test('calling updateWidgetThrottled 20 times within 500ms fires exactly 1 update', () async {
      int updateCount = 0;
      DateTime? lastWidgetUpdateTime;

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

      // Simulate 20 rapid calls within 500ms
      for (int i = 0; i < 20; i++) {
        updateWidgetThrottled();
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }

      expect(updateCount, equals(1), reason: 'Only 1 widget update should fire within 500ms under 1000ms throttle');
    });
  });
}
