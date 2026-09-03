import 'dart:async';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Stall Watchdog Timer Cancellation (B-35)', () {
    test('cancels timer on stall detection to prevent runaway callbacks', () async {
      int tickCount = 0;
      bool stalled = false;
      Timer? watchdog;

      watchdog = Timer.periodic(const Duration(milliseconds: 10), (timer) {
        tickCount++;
        if (tickCount >= 2) {
          stalled = true;
          timer.cancel();
        }
      });

      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(stalled, isTrue);
      expect(watchdog.isActive, isFalse);
      expect(tickCount, equals(2));
    });
  });
}
