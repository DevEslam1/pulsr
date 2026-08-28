// lib/core/utils/ytm_rate_limiter.dart
import 'dart:async';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

/// Dart-side adaptive token-bucket rate limiter for YouTube Music API requests.
///
/// Prevents rapid-fire HTTP requests from the Dart layer from triggering
/// YouTube's IP-level 429 rate limiting.
class YtmRateLimiter {
  YtmRateLimiter._();
  static final YtmRateLimiter shared = YtmRateLimiter._();

  static const String _keyTokens = 'ytm_rate_limiter_tokens';
  static const String _keyLastRefill = 'ytm_rate_limiter_last_refill';
  static const String _keyBackoffUntil = 'ytm_rate_limiter_backoff_until';

  SharedPreferences? _prefs;

  static const int _maxTokens = 8;
  static const double _refillRate = 4.0; // tokens per second

  double _tokens = _maxTokens.toDouble();
  DateTime _lastRefill = DateTime.now();
  final _random = Random();

  DateTime _backoffUntil = DateTime.fromMillisecondsSinceEpoch(0);
  int _adaptiveMultiplier = 1;
  DateTime _lastSuccess = DateTime.now();

  final Map<String, Future<dynamic>> _inFlightRequests = {};

  Duration get cooldownRemaining {
    final now = DateTime.now();
    if (_backoffUntil.isAfter(now)) {
      return _backoffUntil.difference(now);
    }
    return Duration.zero;
  }

  bool get isCoolingDown => cooldownRemaining > Duration.zero;

  Future<void> restore() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      final savedTokens = _prefs?.getDouble(_keyTokens);
      final savedLastRefill = _prefs?.getInt(_keyLastRefill);
      final savedBackoff = _prefs?.getInt(_keyBackoffUntil);

      if (savedTokens != null && savedLastRefill != null) {
        _tokens = savedTokens.clamp(0.0, _maxTokens.toDouble());
        _lastRefill = DateTime.fromMillisecondsSinceEpoch(savedLastRefill);
        _refill();
      }
      if (savedBackoff != null) {
        final deadline = DateTime.fromMillisecondsSinceEpoch(savedBackoff);
        if (deadline.isAfter(DateTime.now())) {
          _backoffUntil = deadline;
        }
      }
    } catch (_) {}
  }

  void _persist() {
    if (_prefs != null) {
      _prefs!.setDouble(_keyTokens, _tokens).catchError((_) => false);
      _prefs!
          .setInt(_keyLastRefill, _lastRefill.millisecondsSinceEpoch)
          .catchError((_) => false);
      _prefs!
          .setInt(_keyBackoffUntil, _backoffUntil.millisecondsSinceEpoch)
          .catchError((_) => false);
    } else {
      SharedPreferences.getInstance().then((p) {
        _prefs = p;
        p.setDouble(_keyTokens, _tokens).catchError((_) => false);
        p
            .setInt(_keyLastRefill, _lastRefill.millisecondsSinceEpoch)
            .catchError((_) => false);
        p
            .setInt(_keyBackoffUntil, _backoffUntil.millisecondsSinceEpoch)
            .catchError((_) => false);
      }).catchError((_) {});
    }
  }

  /// In-flight request deduplication: identical requests share a single future
  Future<T> runDeduplicated<T>(String key, Future<T> Function() task) async {
    if (_inFlightRequests.containsKey(key)) {
      return await (_inFlightRequests[key] as Future<T>);
    }

    final future = task();
    _inFlightRequests[key] = future;
    try {
      final result = await future;
      return result;
    } finally {
      _inFlightRequests.remove(key);
    }
  }

  /// Test-only: restores pristine bucket/backoff state.
  static void debugReset() {
    shared._tokens = _maxTokens.toDouble();
    shared._lastRefill = DateTime.now();
    shared._backoffUntil = DateTime.fromMillisecondsSinceEpoch(0);
    shared._adaptiveMultiplier = 1;
    shared._inFlightRequests.clear();
  }

  /// Acquires a permit before making a request.
  Future<void> acquirePermit() async {
    final now = DateTime.now();
    if (now.isBefore(_backoffUntil)) {
      await Future<void>.delayed(_backoffUntil.difference(now));
    }

    _refill();
    if (_tokens >= 1.0) {
      _tokens -= 1.0;
      _persist();
      return;
    }

    // Wait for the next token to become available
    final waitMs = ((1.0 - _tokens) / _refillRate * 1000).ceil();
    await Future<void>.delayed(Duration(milliseconds: waitMs));
    _refill();
    _tokens = (_tokens - 1.0).clamp(0.0, _maxTokens.toDouble());
    _persist();
  }

  /// Called when a 429 rate-limit response is received.
  void onRateLimited([int? retryAfterSeconds]) {
    final now = DateTime.now();
    _adaptiveMultiplier = (_adaptiveMultiplier * 2).clamp(1, 16);

    if (retryAfterSeconds != null && retryAfterSeconds > 0) {
      _backoffUntil = now.add(Duration(seconds: retryAfterSeconds));
    } else {
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
    _persist();
  }

  /// Called on a successful request to reset backoff state.
  void onSuccess() {
    final now = DateTime.now();
    if (now.difference(_lastSuccess).inMinutes > 10) {
      _adaptiveMultiplier = 1;
    }
    _lastSuccess = now;
    _backoffUntil = DateTime.fromMillisecondsSinceEpoch(0);
    _persist();
  }

  void _refill() {
    final now = DateTime.now();
    final elapsed = now.difference(_lastRefill).inMilliseconds / 1000.0;
    _tokens =
        (_tokens + elapsed * _refillRate).clamp(0.0, _maxTokens.toDouble());
    _lastRefill = now;
  }
}
