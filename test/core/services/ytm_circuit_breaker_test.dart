// test/core/services/ytm_circuit_breaker_test.dart
//
// F2 regression. `shouldAllow` closed a signal by dropping `_openUntil` but
// left `_consecutiveFailures` at its tripped value, so a single failure after
// the cooldown re-opened the window for its full length: one bad resolve per
// cooldown latched the signal shut for good. A half-open breaker has to start
// its failure budget over.
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/errors/ytm_error_classifier.dart';
import 'package:pulsr/core/services/ytm_circuit_breaker.dart';

void main() {
  group('YtmCircuitBreaker - half-open resets the budget (F2)', () {
    late DateTime now;
    late YtmCircuitBreaker breaker;

    setUp(() {
      now = DateTime(2026, 1, 1, 12);
      breaker = YtmCircuitBreaker(() => now);
    });

    test('the breaker opens after maxConsecutiveFailures', () {
      const signal = YtmBlockSignal.poTokenInvalid; // 30s cooldown
      for (var i = 0; i < YtmCircuitBreaker.maxConsecutiveFailures; i++) {
        expect(breaker.shouldAllow(signal), isTrue,
            reason: 'still under the threshold');
        breaker.recordFailure(signal);
      }
      expect(breaker.shouldAllow(signal), isFalse, reason: 'window is open');
    });

    test('after the cooldown one failure does NOT re-open the window', () {
      const signal = YtmBlockSignal.poTokenInvalid;
      for (var i = 0; i < YtmCircuitBreaker.maxConsecutiveFailures; i++) {
        breaker.recordFailure(signal);
      }
      expect(breaker.shouldAllow(signal), isFalse);

      // Walk past the cooldown: the breaker goes half-open and must restart its
      // failure budget.
      now = now.add(const Duration(seconds: 31));
      expect(breaker.shouldAllow(signal), isTrue, reason: 'half-open');

      breaker.recordFailure(signal);
      expect(breaker.shouldAllow(signal), isTrue,
          reason: 'one failure after a half-open transition must not latch it');

      // It takes the full budget again to shut it.
      breaker.recordFailure(signal);
      expect(breaker.shouldAllow(signal), isTrue);
      breaker.recordFailure(signal);
      expect(breaker.shouldAllow(signal), isFalse);
    });

    test('recordSuccess clears the failure budget', () {
      const signal = YtmBlockSignal.poTokenInvalid;
      breaker.recordFailure(signal);
      breaker.recordFailure(signal);
      breaker.recordSuccess();
      breaker.recordFailure(signal);
      expect(breaker.shouldAllow(signal), isTrue);
    });

    test('a zero-cooldown signal never opens a window', () {
      const signal = YtmBlockSignal.geoBlocked;
      for (var i = 0; i < 5; i++) {
        breaker.recordFailure(signal);
      }
      expect(breaker.shouldAllow(signal), isTrue);
    });

    test('a bot challenge cools down on the first hit', () {
      const signal = YtmBlockSignal.botChallenge;
      breaker.recordFailure(signal);
      expect(breaker.shouldAllow(signal), isFalse);
    });
  });
}