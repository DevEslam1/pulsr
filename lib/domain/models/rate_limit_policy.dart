// lib/domain/models/rate_limit_policy.dart
// Phase 1.A: Centralized Rate-Limiting Policy definition.

import 'dart:math';

/// Unified definition of rate limiting parameters and backoff calculation.
class RateLimitPolicy {
  final int maxTokens;
  final double refillRate; // tokens per second
  final int initialBackoffSeconds;
  final int maxBackoffSeconds;
  final double backoffMultiplier;
  final Duration jitterRange;
  final int circuitInfraFailureThreshold;
  final Duration circuitRecoveryDuration;

  const RateLimitPolicy({
    this.maxTokens = 8,
    this.refillRate = 4.0,
    this.initialBackoffSeconds = 2,
    this.maxBackoffSeconds = 60,
    this.backoffMultiplier = 2.0,
    this.jitterRange = const Duration(milliseconds: 1000),
    this.circuitInfraFailureThreshold = 3,
    this.circuitRecoveryDuration = const Duration(minutes: 15),
  });

  static const RateLimitPolicy nativePacing = RateLimitPolicy(
    maxTokens: 8,
    refillRate: 4.0,
    initialBackoffSeconds: 2,
    maxBackoffSeconds: 30,
    backoffMultiplier: 2.0,
    jitterRange: Duration(milliseconds: 1000),
  );

  static const RateLimitPolicy backendPacing = RateLimitPolicy(
    maxTokens: 30,
    refillRate: 10.0,
    initialBackoffSeconds: 5,
    maxBackoffSeconds: 60,
    backoffMultiplier: 2.0,
    jitterRange: Duration(milliseconds: 1500),
    circuitInfraFailureThreshold: 3,
    circuitRecoveryDuration: Duration(minutes: 15),
  );

  /// Calculates backoff duration for a given attempt or rate-limit occurrence.
  Duration calculateBackoff({
    required int consecutiveFailures,
    int? retryAfterSeconds,
    Random? random,
  }) {
    if (retryAfterSeconds != null && retryAfterSeconds > 0) {
      return Duration(seconds: min(retryAfterSeconds, maxBackoffSeconds));
    }

    final rand = random ?? Random();
    final jitterMs = jitterRange.inMilliseconds > 0
        ? rand.nextInt(jitterRange.inMilliseconds)
        : 0;

    final multiplier = pow(backoffMultiplier, max(0, consecutiveFailures - 1));
    final calculatedSeconds = (initialBackoffSeconds * multiplier).toInt();
    final clampedSeconds = min(calculatedSeconds, maxBackoffSeconds);

    return Duration(seconds: clampedSeconds) + Duration(milliseconds: jitterMs);
  }
}
