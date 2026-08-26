// test/ytm_rate_limiter_test.dart
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/utils/ytm_rate_limiter.dart';

void main() {
  group('YtmRateLimiter backoff', () {
    test('every concurrent caller waits out the full backoff window',
        () async {
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
          expect(d, greaterThan(const Duration(seconds: 2)));
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
}
