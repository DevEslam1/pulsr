// lib/core/utils/ytm_rate_limiter.dart
import 'dart:async';
import 'dart:math';

/// Dart-side token-bucket rate limiter for YouTube Music API requests.
///
/// Prevents rapid-fire HTTP requests from the Dart layer (which bypass the
/// native [RateLimiter]) from triggering YouTube's IP-level 429 rate limiting.
///
/// Configured with 4 requests/second sustained, burst of 8.
class YtmRateLimiter {
  YtmRateLimiter._();
  static final YtmRateLimiter shared = YtmRateLimiter._();

  static const int _maxTokens = 8;
  static const double _refillRate = 4.0; // tokens per second

  double _tokens = _maxTokens.toDouble();
  DateTime _lastRefill = DateTime.now();
  final _random = Random();

  /// How long to back off after a 429 response.
  Duration _backoffDuration = Duration.zero;

  /// Acquires a permit before making a request. If the bucket is empty,
  /// waits until a token is available.
  Future<void> acquirePermit() async {
    // If we're in a backoff period, wait it out
    if (_backoffDuration > Duration.zero) {
      await Future<void>.delayed(_backoffDuration);
      _backoffDuration = Duration.zero;
    }

    _refill();
    if (_tokens >= 1.0) {
      _tokens -= 1.0;
      return;
    }

    // Wait for the next token to become available
    final waitMs = ((1.0 - _tokens) / _refillRate * 1000).ceil();
    await Future<void>.delayed(Duration(milliseconds: waitMs));
    _refill();
    _tokens = (_tokens - 1.0).clamp(0.0, _maxTokens.toDouble());
  }

  /// Called when a 429 rate-limit response is received. Triggers exponential
  /// backoff with jitter for subsequent requests.
  void onRateLimited() {
    final base = _backoffDuration == Duration.zero
        ? const Duration(seconds: 2)
        : _backoffDuration * 2;
    final jitter = Duration(milliseconds: _random.nextInt(1000));
    _backoffDuration = base + jitter;
    // Cap at 30 seconds
    if (_backoffDuration.inSeconds > 30) {
      _backoffDuration = Duration(seconds: 30) + jitter;
    }
  }

  /// Called on a successful request to reset backoff state.
  void onSuccess() {
    _backoffDuration = Duration.zero;
  }

  void _refill() {
    final now = DateTime.now();
    final elapsed = now.difference(_lastRefill).inMilliseconds / 1000.0;
    _tokens = (_tokens + elapsed * _refillRate).clamp(0.0, _maxTokens.toDouble());
    _lastRefill = now;
  }
}
