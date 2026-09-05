// lib/core/utils/ytm_rate_limiter.dart
import 'dart:async';
import 'dart:math';
import 'package:clock/clock.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Simple asynchronous mutex to serialize token acquisitions.
class AsyncMutex {
  Future<void> _last = Future.value();

  Future<T> run<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _last = _last.then((_) async {
      try {
        final res = await action();
        completer.complete(res);
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }
}

/// Dart-side adaptive token-bucket rate limiter for YouTube Music API requests.
///
/// Prevents rapid-fire HTTP requests from the Dart layer from triggering
/// YouTube's IP-level 429 rate limiting, and manages a separate bucket for the backend.
class YtmRateLimiter {
  YtmRateLimiter._();
  static final YtmRateLimiter shared = YtmRateLimiter._();

  AsyncMutex _nativeMutex = AsyncMutex();
  AsyncMutex _backendMutex = AsyncMutex();

  static const String _keyTokens = 'ytm_rate_limiter_tokens';
  static const String _keyLastRefill = 'ytm_rate_limiter_last_refill';
  static const String _keyBackoffUntil = 'ytm_rate_limiter_backoff_until';

  static const String _keyBackendTokens = 'ytm_rate_limiter_backend_tokens';
  static const String _keyBackendLastRefill = 'ytm_rate_limiter_backend_last_refill';
  static const String _keyBackendBackoffUntil = 'ytm_rate_limiter_backend_backoff_until';

  SharedPreferences? _prefs;

  // Native YTM pacing bucket
  static const int _maxTokens = 8;
  static const double _refillRate = 4.0; // tokens per second

  double _tokens = _maxTokens.toDouble();
  DateTime _lastRefill = clock.now();
  final _random = Random();

  DateTime _backoffUntil = DateTime.fromMillisecondsSinceEpoch(0);
  int _adaptiveMultiplier = 1;
  DateTime _lastSuccess = clock.now();

  // Dedicated Backend bucket (higher cap, 10/s refill, no client-side pacing floors)
  static const int _backendMaxTokens = 30;
  static const double _backendRefillRate = 10.0; // tokens per second

  double _backendTokens = _backendMaxTokens.toDouble();
  DateTime _backendLastRefill = clock.now();
  DateTime _backendBackoffUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _backendLastSuccess = clock.now();

  final Map<String, Future<dynamic>> _inFlightRequests = {};

  DateTime get lastBackendSuccess => _backendLastSuccess;

  Duration get cooldownRemaining {
    final now = clock.now();
    if (_backoffUntil.isAfter(now)) {
      return _backoffUntil.difference(now);
    }
    return Duration.zero;
  }

  bool get isCoolingDown => cooldownRemaining > Duration.zero;

  Duration get backendCooldownRemaining {
    final now = clock.now();
    if (_backendBackoffUntil.isAfter(now)) {
      return _backendBackoffUntil.difference(now);
    }
    return Duration.zero;
  }

  bool get isBackendCoolingDown => backendCooldownRemaining > Duration.zero;

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
        if (deadline.isAfter(clock.now())) {
          _backoffUntil = deadline;
        }
      }

      final savedBTokens = _prefs?.getDouble(_keyBackendTokens);
      final savedBLastRefill = _prefs?.getInt(_keyBackendLastRefill);
      final savedBBackoff = _prefs?.getInt(_keyBackendBackoffUntil);

      if (savedBTokens != null && savedBLastRefill != null) {
        _backendTokens = savedBTokens.clamp(0.0, _backendMaxTokens.toDouble());
        _backendLastRefill = DateTime.fromMillisecondsSinceEpoch(savedBLastRefill);
        _refillBackend();
      }
      if (savedBBackoff != null) {
        final deadline = DateTime.fromMillisecondsSinceEpoch(savedBBackoff);
        if (deadline.isAfter(clock.now())) {
          _backendBackoffUntil = deadline;
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
      _prefs!.setDouble(_keyBackendTokens, _backendTokens).catchError((_) => false);
      _prefs!
          .setInt(_keyBackendLastRefill, _backendLastRefill.millisecondsSinceEpoch)
          .catchError((_) => false);
      _prefs!
          .setInt(_keyBackendBackoffUntil, _backendBackoffUntil.millisecondsSinceEpoch)
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
        p.setDouble(_keyBackendTokens, _backendTokens).catchError((_) => false);
        p
            .setInt(_keyBackendLastRefill, _backendLastRefill.millisecondsSinceEpoch)
            .catchError((_) => false);
        p
            .setInt(_keyBackendBackoffUntil, _backendBackoffUntil.millisecondsSinceEpoch)
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
    // The mutexes must be replaced too: their queue tail is a future owned by
    // whatever zone last used it, so a permit acquired under a torn-down
    // `fakeAsync` zone would leave every later caller chained to a future that
    // can no longer be delivered.
    shared._nativeMutex = AsyncMutex();
    shared._backendMutex = AsyncMutex();

    shared._tokens = _maxTokens.toDouble();
    shared._lastRefill = clock.now();
    shared._backoffUntil = DateTime.fromMillisecondsSinceEpoch(0);
    shared._adaptiveMultiplier = 1;

    shared._backendTokens = _backendMaxTokens.toDouble();
    shared._backendLastRefill = clock.now();
    shared._backendBackoffUntil = DateTime.fromMillisecondsSinceEpoch(0);

    shared._inFlightRequests.clear();
  }

  /// Acquires a permit before making a native YTM request.
  Future<void> acquirePermit() => _nativeMutex.run(() async {
    while (true) {
      final now = clock.now();
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
      final waitMs = ((1.0 - _tokens) / _refillRate * 1000).ceil().clamp(10, 5000);
      await Future<void>.delayed(Duration(milliseconds: waitMs));
    }
  });

  /// Acquires a permit before making a backend microservice request.
  Future<void> acquireBackendPermit() => _backendMutex.run(() async {
    while (true) {
      final now = clock.now();
      if (now.isBefore(_backendBackoffUntil)) {
        await Future<void>.delayed(_backendBackoffUntil.difference(now));
      }

      _refillBackend();
      if (_backendTokens >= 1.0) {
        _backendTokens -= 1.0;
        _persist();
        return;
      }

      final waitMs = ((1.0 - _backendTokens) / _backendRefillRate * 1000).ceil().clamp(10, 5000);
      await Future<void>.delayed(Duration(milliseconds: waitMs));
    }
  });

  /// Called when a 429 rate-limit response is received from native YouTube.
  /// [_adaptiveMultiplier] actually scales the backoff (previously it was
  /// incremented but never read), so repeated blocks cool down longer.
  void onRateLimited([int? retryAfterSeconds]) {
    final now = clock.now();
    _adaptiveMultiplier = (_adaptiveMultiplier * 2).clamp(1, 16);

    if (retryAfterSeconds != null && retryAfterSeconds > 0) {
      final jitter = Duration(milliseconds: _random.nextInt(1000));
      _backoffUntil = now.add(Duration(seconds: retryAfterSeconds) + jitter);
    } else {
      final remaining = _backoffUntil.isAfter(now)
          ? _backoffUntil.difference(now)
          : Duration.zero;
      // Fresh block scales with the adaptive multiplier (repeated 429s cool
      // down longer); an in-progress window extends by doubling, capped.
      var base = remaining == Duration.zero
          ? Duration(seconds: 2 * _adaptiveMultiplier)
          : remaining * 2;
      final jitter = Duration(milliseconds: _random.nextInt(1000));
      if (base.inSeconds > 30) base = const Duration(seconds: 30);
      _backoffUntil = now.add(base + jitter);
    }
    _persist();
  }

  /// Called when a 429 response is received from backend (honoring Retry-After).
  void onBackendRateLimited([int? retryAfterSeconds]) {
    final now = clock.now();
    final seconds = (retryAfterSeconds != null && retryAfterSeconds > 0)
        ? retryAfterSeconds
        : 60;
    final jitter = Duration(milliseconds: _random.nextInt(1000));
    _backendBackoffUntil = now.add(Duration(seconds: seconds) + jitter);
    _persist();
  }

  /// Called on a successful native request.
  /// Never clears an active cooling window: one success through an alternate
  /// route must not instantly hammer the blocked route again. The window
  /// expires naturally; success only decays the adaptive multiplier after
  /// 10 minutes of clean traffic.
  void onSuccess() {
    final now = clock.now();
    if (now.difference(_lastSuccess).inMinutes > 10) {
      _adaptiveMultiplier = 1;
    }
    _lastSuccess = now;
    _persist();
  }

  /// Called on a successful backend request to reset backoff state.
  void onBackendSuccess() {
    _backendLastSuccess = clock.now();
    _backendBackoffUntil = DateTime.fromMillisecondsSinceEpoch(0);
    _persist();
  }

  void _refill() {
    final now = clock.now();
    final elapsed = now.difference(_lastRefill).inMilliseconds / 1000.0;
    _tokens =
        (_tokens + elapsed * _refillRate).clamp(0.0, _maxTokens.toDouble());
    _lastRefill = now;
  }

  void _refillBackend() {
    final now = clock.now();
    final elapsed = now.difference(_backendLastRefill).inMilliseconds / 1000.0;
    _backendTokens =
        (_backendTokens + elapsed * _backendRefillRate).clamp(0.0, _backendMaxTokens.toDouble());
    _backendLastRefill = now;
  }
}
