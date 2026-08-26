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

  /// Test-only: restores pristine bucket/backoff state (the limiter is a
  /// process-wide singleton, so tests need a way to isolate runs).
  static void debugReset() {
    shared._tokens = _maxTokens.toDouble();
    shared._lastRefill = DateTime.now();
    shared._backoffUntil = DateTime.fromMillisecondsSinceEpoch(0);
  }

  static const int _maxTokens = 8;
  static const double _refillRate = 4.0; // tokens per second

  double _tokens = _maxTokens.toDouble();
  DateTime _lastRefill = DateTime.now();
  final _random = Random();

  /// Wall-clock deadline every caller must respect before sending; using an
  /// absolute instant (instead of a one-shot duration) means every concurrent
  /// caller waits out the full backoff, not just the first one.
  DateTime _backoffUntil = DateTime.fromMillisecondsSinceEpoch(0);

  /// Acquires a permit before making a request. If the bucket is empty,
  /// waits until a token is available.
  Future<void> acquirePermit() async {
    final now = DateTime.now();
    if (now.isBefore(_backoffUntil)) {
      await Future<void>.delayed(_backoffUntil.difference(now));
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
    final now = DateTime.now();
    final remaining = _backoffUntil.isAfter(now)
        ? _backoffUntil.difference(now)
        : Duration.zero;
    var base = remaining == Duration.zero
        ? const Duration(seconds: 2)
        : remaining * 2;
    final jitter = Duration(milliseconds: _random.nextInt(1000));
    if (base.inSeconds > 30) base = const Duration(seconds: 30);
    _backoffUntil = now.add(base + jitter);
  }

  /// Called on a successful request to reset backoff state.
  void onSuccess() {
    _backoffUntil = DateTime.fromMillisecondsSinceEpoch(0);
  }

  void _refill() {
    final now = DateTime.now();
    final elapsed = now.difference(_lastRefill).inMilliseconds / 1000.0;
    _tokens = (_tokens + elapsed * _refillRate).clamp(0.0, _maxTokens.toDouble());
    _lastRefill = now;
  }
}
