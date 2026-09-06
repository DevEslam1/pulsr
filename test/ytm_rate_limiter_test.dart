// test/ytm_rate_limiter_test.dart
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/utils/ytm_rate_limiter.dart';

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
          expect(d, greaterThan(const Duration(seconds: 2)));
          // 2s base + up to 1s jitter + small token-wait margin.
          expect(d, lessThan(const Duration(seconds: 6)));
        }
      });
    });

    test('onSuccess does not cancel an active cooling window', () {
      fakeAsync((async) {
        YtmRateLimiter.debugReset();
        final limiter = YtmRateLimiter.shared;

        limiter.onRateLimited();
        // One success via an alternate route must not instantly re-hammer
        // the blocked route: the cooling window survives.
        limiter.onSuccess();

        Duration waited = Duration.zero;
        limiter
            .acquirePermit()
            .then((_) => waited = async.elapsed)
            .then((_) => async.flushTimers());

        async.flushMicrotasks();
        async.flushTimers();

        // ~4s base (2s x multiplier 2) + jitter: still cooling down.
        expect(waited, greaterThan(const Duration(seconds: 2)));
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

    test('an outsized Retry-After is capped, not honoured verbatim', () {
      fakeAsync((async) {
        YtmRateLimiter.debugReset();
        final limiter = YtmRateLimiter.shared;

        // The window is persisted, so honouring an hour-long hint from the
        // network froze every native request for an hour across restarts.
        limiter.onRateLimited(3600);

        expect(limiter.cooldownRemaining,
            lessThan(const Duration(seconds: 302)));
        expect(limiter.cooldownRemaining, greaterThan(const Duration(minutes: 4)));
        async.flushTimers();
      });
    });
  });

  group('YtmRateLimiter backend bucket', () {
    test('a backend 429 does not freeze the native YouTube path', () {
      fakeAsync((async) {
        YtmRateLimiter.debugReset();
        final limiter = YtmRateLimiter.shared;

        limiter.onBackendRateLimited(60);

        expect(limiter.isBackendCoolingDown, isTrue);
        // The backend is a different IP; its quota says nothing about how
        // YouTube sees this device. Freezing both made the fallback take the
        // primary down with it.
        expect(limiter.isCoolingDown, isFalse);
        async.flushTimers();
      });
    });

    test('onBackendSuccess does not cancel an active backend window', () {
      fakeAsync((async) {
        YtmRateLimiter.debugReset();
        final limiter = YtmRateLimiter.shared;

        limiter.onBackendRateLimited(60);
        // A request already in flight when the 429 landed completes after it,
        // and used to wipe the whole Retry-After window.
        limiter.onBackendSuccess();

        expect(limiter.isBackendCoolingDown, isTrue);
        expect(limiter.backendCooldownRemaining,
            greaterThan(const Duration(seconds: 30)));
        async.flushTimers();
      });
    });
  });
}
