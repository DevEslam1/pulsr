import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/utils/ytm_rate_limiter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('YtmRateLimiter Adaptive Multiplier Cap (B-40)', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      YtmRateLimiter.shared.onSuccess();
    });

    test('caps adaptive multiplier at 8 even with multiple rate limit events', () {
      expect(YtmRateLimiter.shared.adaptiveMultiplier, equals(1));

      // Trigger multiple 429 events
      for (int i = 0; i < 20; i++) {
        YtmRateLimiter.shared.onRateLimited(1);
      }

      expect(YtmRateLimiter.shared.adaptiveMultiplier, equals(8));
      expect(YtmRateLimiter.maxAdaptiveMultiplier, equals(8));
    });

    test('resets adaptive multiplier to 1 on success', () {
      for (int i = 0; i < 5; i++) {
        YtmRateLimiter.shared.onRateLimited(1);
      }
      expect(YtmRateLimiter.shared.adaptiveMultiplier, greaterThan(1));

      YtmRateLimiter.shared.onSuccess();
      expect(YtmRateLimiter.shared.adaptiveMultiplier, equals(1));
    });
  });
}
