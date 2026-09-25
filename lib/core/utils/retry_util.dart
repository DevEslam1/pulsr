// lib/core/utils/retry_util.dart
import 'dart:async';
import 'dart:math' as math;
import 'error_logger.dart';

/// Utility providing robust exponential backoff retry execution for async operations (I2).
class RetryUtil {
  const RetryUtil._();

  /// Executes [action] with exponential backoff retry.
  ///
  /// - [maxAttempts]: Maximum number of total attempts (including initial call).
  /// - [initialDelay]: Delay before first retry.
  /// - [maxDelay]: Cap on the exponential delay.
  /// - [multiplier]: Multiplier applied to delay after each failure.
  /// - [jitter]: Randomization factor between 0.0 and 1.0 to prevent thundering herd.
  /// - [shouldRetry]: Optional filter to decide whether a particular error is retryable.
  static Future<T> withExponentialBackoff<T>(
    FutureOr<T> Function() action, {
    int maxAttempts = 3,
    Duration initialDelay = const Duration(milliseconds: 500),
    Duration maxDelay = const Duration(seconds: 8),
    double multiplier = 2.0,
    double jitter = 0.2,
    bool Function(Object error)? shouldRetry,
    String? category,
  }) async {
    assert(maxAttempts >= 1, 'maxAttempts must be at least 1');
    int attempt = 0;
    Duration currentDelay = initialDelay;
    final random = math.Random();

    while (true) {
      attempt++;
      try {
        return await action();
      } catch (error, stackTrace) {
        final canRetry = attempt < maxAttempts && (shouldRetry?.call(error) ?? true);
        if (!canRetry) {
          rethrow;
        }

        ErrorLogger.log(
          'Operation failed on attempt $attempt/$maxAttempts, retrying after ${currentDelay.inMilliseconds}ms',
          error: error,
          stackTrace: stackTrace,
          category: category ?? 'RetryUtil',
        );

        final jitterOffset = jitter > 0
            ? (currentDelay.inMilliseconds * jitter * (random.nextDouble() * 2 - 1)).round()
            : 0;
        final actualDelayMs = math.max(0, currentDelay.inMilliseconds + jitterOffset);
        await Future<void>.delayed(Duration(milliseconds: actualDelayMs));

        final nextMs = (currentDelay.inMilliseconds * multiplier).round();
        currentDelay = Duration(milliseconds: math.min(nextMs, maxDelay.inMilliseconds));
      }
    }
  }
}
