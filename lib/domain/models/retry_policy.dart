// lib/domain/models/retry_policy.dart
// Domain Maximization (10/10): Value object for retry math, exponential backoff with jitter,
// and retryable error classification.

import 'dart:math';

class RetryPolicy {
  final int maxAttempts;
  final Duration initialDelay;
  final Duration maxDelay;
  final double backoffMultiplier;
  final double jitterFactor;

  const RetryPolicy({
    this.maxAttempts = 3,
    this.initialDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
    this.backoffMultiplier = 2.0,
    this.jitterFactor = 0.25,
  });

  /// Calculates backoff delay for a given attempt (1-based index) with randomized jitter.
  Duration delayForAttempt(int attempt, [Random? customRandom]) {
    if (attempt <= 1) return initialDelay;

    final exponentialMillis = initialDelay.inMilliseconds *
        pow(backoffMultiplier, attempt - 1);
    final clampedMillis = min(exponentialMillis.toDouble(), maxDelay.inMilliseconds.toDouble());

    // Apply full/decorrelated jitter: ± (clampedMillis * jitterFactor)
    final rng = customRandom ?? Random();
    final jitterRange = clampedMillis * jitterFactor;
    final jitter = (rng.nextDouble() * 2 - 1) * jitterRange;
    final finalMillis = (clampedMillis + jitter).clamp(100.0, maxDelay.inMilliseconds.toDouble());

    return Duration(milliseconds: finalMillis.round());
  }

  /// Determines if an error message/code represents a retryable condition.
  static bool isRetryableError(String? error) {
    if (error == null || error.isEmpty) return false;
    final lower = error.toLowerCase();

    // Non-retryable terminal errors
    if (lower.contains('insufficient storage') ||
        lower.contains('storage full') ||
        lower.contains('unavailable in this build') ||
        lower.contains('bot blocked') ||
        lower.contains('track not found') ||
        lower.contains('invalid video id')) {
      return false;
    }

    // Retryable transient network/server/rate-limit conditions
    if (lower.contains('socket') ||
        lower.contains('connection') ||
        lower.contains('timeout') ||
        lower.contains('429') ||
        lower.contains('503') ||
        lower.contains('500') ||
        lower.contains('network') ||
        lower.contains('handshake') ||
        lower.contains('stream expiring') ||
        lower.contains('http 403')) {
      return true;
    }

    return true; // Default fallback to allowing manual retry
  }
}
