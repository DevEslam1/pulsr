// test/ytm_rate_limiter_test.dart
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/utils/ytm_rate_limiter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('YtmRateLimiter backoff', () {
    test('every concurrent caller waits out the full backoff window', () async {
      fakeAsync((async) {
        YtmRateLimiter.debugReset();
        final limiter = YtmRateLimiter.shared;

        limiter.onRateLimited(); // schedules ~2s (+<1s jitter) of backoff

        final elapsedAtDone = <Duration>[];
        final f1 = limiter.acquirePermit().then((_) => async.elapsed);
        final f2 = limiter.acquirePermit().then((_) => async.elapsed);
        f1.then(elapsedAtDone.add);
        f2.then(elapsedAtDone.add);

        async.flushMicrotasks();
        async.flushTimers();

        // Both callers must have waited the whole window. The old one-shot
        // duration let the second caller through almost immediately.
        expect(elapsedAtDone.length, 2);
        for (final d in elapsedAtDone) {
          expect(d, greaterThanOrEqualTo(const Duration(milliseconds: 1950)));
          // 2s base + up to 1s jitter + small token-wait margin.
          expect(d, lessThan(const Duration(seconds: 6)));
        }
      });
    });

    test('onSuccess clears the backoff deadline', () {
      fakeAsync((async) {
        YtmRateLimiter.debugReset();
        final limiter = YtmRateLimiter.shared;

        limiter.onRateLimited();
        limiter.onSuccess();

        Duration waited = Duration.zero;
        limiter
            .acquirePermit()
            .then((_) => waited = async.elapsed)
            .then((_) => async.flushTimers());

        async.flushMicrotasks();
        async.flushTimers();

        // Bucket starts full: no meaningful wait after backoff was cleared.
        expect(waited, lessThan(const Duration(milliseconds: 50)));
      });
    });

    test('repeated 429s extend the backoff instead of restarting it', () {
      fakeAsync((async) {
        YtmRateLimiter.debugReset();
        final limiter = YtmRateLimiter.shared;

        limiter.onRateLimited();
        // Second 429 arrives while still backing off -> window doubles.
        limiter.onRateLimited();
        limiter.onRateLimited();
        limiter.onRateLimited(); // capped at 30s

        Duration waited = Duration.zero;
        limiter
            .acquirePermit()
            .then((_) => waited = async.elapsed)
            .then((_) => async.flushTimers());

        async.flushMicrotasks();
        async.flushTimers();

        expect(waited, lessThan(const Duration(seconds: 32)),
            reason: 'backoff must stay capped near 30s');
        expect(waited, greaterThan(const Duration(seconds: 8)));
      });
    });
  });

  group('YtmRateLimiter launch backoff clamp', () {
    test('a persisted 429 spiral is clamped to <=2s at restore', () async {
      YtmRateLimiter.debugReset();
      SharedPreferences.setMockInitialValues({
        'ytm_rate_limiter_backoff_until':
            DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
        'ytm_rate_limiter_backend_backoff_until':
            DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch,
      });

      await YtmRateLimiter.shared.restore();

      // The prior session had ~1h/1d left; restore must cap both buckets at
      // the 2s clamp (plus small slack for the time restore() itself takes).
      expect(YtmRateLimiter.shared.isCoolingDown, isTrue);
      expect(
        YtmRateLimiter.shared.cooldownRemaining,
        lessThanOrEqualTo(const Duration(milliseconds: 2500)),
      );
      expect(YtmRateLimiter.shared.isBackendCoolingDown, isTrue);
      expect(
        YtmRateLimiter.shared.backendCooldownRemaining,
        lessThanOrEqualTo(const Duration(milliseconds: 2500)),
      );
    });

    test('a small persisted backoff under the clamp is kept as-is', () async {
      YtmRateLimiter.debugReset();
      // The legacy SharedPreferences instance (and its value cache) is cached
      // process-wide, so rather than re-seeding mock initial values, write
      // the short backoff through the live instance before restoring.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        'ytm_rate_limiter_backoff_until',
        DateTime.now()
            .add(const Duration(milliseconds: 500))
            .millisecondsSinceEpoch,
      );

      await YtmRateLimiter.shared.restore();

      expect(YtmRateLimiter.shared.isCoolingDown, isTrue);
      expect(
        YtmRateLimiter.shared.cooldownRemaining,
        lessThanOrEqualTo(const Duration(milliseconds: 500)),
        reason: 'short backoffs must not be extended up to the clamp',
      );
    });
  });
}
