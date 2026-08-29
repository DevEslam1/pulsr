// lib/core/utils/ytm_rate_limiter.dart
import 'dart:async';
import 'dart:math';
import 'package:mutex/mutex.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Request priority classes for rate limiting.
enum YtmRequestPriority {
  interactive,
  background,
}

/// Dart-side adaptive token-bucket rate limiter for YouTube Music API requests.
///
/// Prevents rapid-fire HTTP requests from the Dart layer from triggering
/// YouTube's IP-level 429 rate limiting, and manages a separate bucket for the backend.
class YtmRateLimiter {
  YtmRateLimiter._();
  static final YtmRateLimiter shared = YtmRateLimiter._();

  static const String _keyTokens = 'ytm_rate_limiter_tokens';
  static const String _keyLastRefill = 'ytm_rate_limiter_last_refill';
  static const String _keyBackoffUntil = 'ytm_rate_limiter_backoff_until';

  static const String _keyBackendTokens = 'ytm_rate_limiter_backend_tokens';
  static const String _keyBackendLastRefill = 'ytm_rate_limiter_backend_last_refill';
  static const String _keyBackendBackoffUntil = 'ytm_rate_limiter_backend_backoff_until';

  /// TTFA: backoff restored from a previous session is clamped to this at
  /// launch so a prior session's 429 spiral cannot silently delay the first
  /// play. In-session adaptive AIMD backoff is unaffected.
  static const Duration launchBackoffClamp = Duration(seconds: 2);

  SharedPreferences? _prefs;

  // Native YTM pacing bucket
  static const int _maxTokens = 8;
  static const double _refillRate = 4.0; // tokens per second

  double _tokens = _maxTokens.toDouble();
  DateTime _lastRefill = DateTime.now();
  final _random = Random.secure();
  final _mutex = Mutex();

  DateTime _backoffUntil = DateTime.fromMillisecondsSinceEpoch(0);
  int _adaptiveMultiplier = 1;
  DateTime _lastSuccess = DateTime.now();

  // Dedicated Backend bucket (higher cap, 10/s refill, no client-side pacing floors)
  static const int _backendMaxTokens = 30;
  static const double _backendRefillRate = 10.0; // tokens per second

  double _backendTokens = _backendMaxTokens.toDouble();
  DateTime _backendLastRefill = DateTime.now();
  DateTime _backendBackoffUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _backendLastSuccess = DateTime.now();

  final Map<String, Future<dynamic>> _inFlightRequests = {};

  DateTime get lastBackendSuccess => _backendLastSuccess;

  Duration get cooldownRemaining {
    final now = DateTime.now();
    if (_backoffUntil.isAfter(now)) {
      return _backoffUntil.difference(now);
    }
    return Duration.zero;
  }

  bool get isCoolingDown => cooldownRemaining > Duration.zero;

  Duration get backendCooldownRemaining {
    final now = DateTime.now();
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
        final clamp = DateTime.now().add(launchBackoffClamp);
        if (deadline.isAfter(DateTime.now())) {
          // Clamp at launch: never restore more than launchBackoffClamp.
          _backoffUntil = deadline.isBefore(clamp) ? deadline : clamp;
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
        final clamp = DateTime.now().add(launchBackoffClamp);
        if (deadline.isAfter(DateTime.now())) {
          // Clamp at launch: never restore more than launchBackoffClamp.
          _backendBackoffUntil = deadline.isBefore(clamp) ? deadline : clamp;
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
      unawaited(_inFlightRequests.remove(key));
    }
  }

  /// Test-only: restores pristine bucket/backoff state.
  static void debugReset() {
    shared._tokens = _maxTokens.toDouble();
    shared._lastRefill = DateTime.now();
    shared._backoffUntil = DateTime.fromMillisecondsSinceEpoch(0);
    shared._adaptiveMultiplier = 1;

    shared._backendTokens = _backendMaxTokens.toDouble();
    shared._backendLastRefill = DateTime.now();
    shared._backendBackoffUntil = DateTime.fromMillisecondsSinceEpoch(0);

    shared._inFlightRequests.clear();
  }

  /// Acquires a permit before making a native YTM request.
  /// [priority] ensures interactive requests (user taps) take precedence over background bursts
  /// (pre-resolving, queue restore, metadata fetch) and never get starved.
  Future<void> acquirePermit({YtmRequestPriority priority = YtmRequestPriority.interactive}) async {
    await _mutex.protect(() async {
      final now = DateTime.now();
      if (now.isBefore(_backoffUntil)) {
        // Interactive requests during backoff still wait out the minimum backoff,
        // but background requests are strictly queued
        await Future<void>.delayed(_backoffUntil.difference(now));
      }

      _refill();

      // Background requests must leave a minimum reserve of 2.0 tokens for interactive requests
      if (priority == YtmRequestPriority.background && _tokens < 2.0) {
        final waitMs = ((2.0 - _tokens) / _refillRate * 1000).ceil().clamp(50, 1000);
        await Future<void>.delayed(Duration(milliseconds: waitMs));
        _refill();
      }

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
    });
  }

  /// Acquires a permit before making a backend microservice request.
  Future<void> acquireBackendPermit({YtmRequestPriority priority = YtmRequestPriority.interactive}) async {
    await _mutex.protect(() async {
      final now = DateTime.now();
      if (now.isBefore(_backendBackoffUntil)) {
        await Future<void>.delayed(_backendBackoffUntil.difference(now));
      }

      _refillBackend();

      // Background requests leave a reserve of 5.0 tokens for backend interactive requests
      if (priority == YtmRequestPriority.background && _backendTokens < 5.0) {
        final waitMs = ((5.0 - _backendTokens) / _backendRefillRate * 1000).ceil().clamp(50, 1000);
        await Future<void>.delayed(Duration(milliseconds: waitMs));
        _refillBackend();
      }

      if (_backendTokens >= 1.0) {
        _backendTokens -= 1.0;
        _persist();
        return;
      }

      final waitMs = ((1.0 - _backendTokens) / _backendRefillRate * 1000).ceil();
      await Future<void>.delayed(Duration(milliseconds: waitMs));
      _refillBackend();
      _backendTokens = (_backendTokens - 1.0).clamp(0.0, _backendMaxTokens.toDouble());
      _persist();
    });
  }

  /// Called when a 429 rate-limit response is received from native YouTube.
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

  /// Called when a 429 response is received from backend (honoring Retry-After).
  void onBackendRateLimited([int? retryAfterSeconds]) {
    final now = DateTime.now();
    final seconds = (retryAfterSeconds != null && retryAfterSeconds > 0)
        ? retryAfterSeconds
        : 60;
    _backendBackoffUntil = now.add(Duration(seconds: seconds));
    _persist();
  }

  /// Called on a successful native request to reset backoff state.
  void onSuccess() {
    final now = DateTime.now();
    if (now.difference(_lastSuccess).inMinutes > 10) {
      _adaptiveMultiplier = 1;
    }
    _lastSuccess = now;
    _backoffUntil = DateTime.fromMillisecondsSinceEpoch(0);
    _persist();
  }

  /// Called on a successful backend request to reset backoff state.
  void onBackendSuccess() {
    _backendLastSuccess = DateTime.now();
    _backendBackoffUntil = DateTime.fromMillisecondsSinceEpoch(0);
    _persist();
  }

  void _refill() {
    final now = DateTime.now();
    final elapsed = now.difference(_lastRefill).inMilliseconds / 1000.0;
    _tokens =
        (_tokens + elapsed * _refillRate).clamp(0.0, _maxTokens.toDouble());
    _lastRefill = now;
  }

  void _refillBackend() {
    final now = DateTime.now();
    final elapsed = now.difference(_backendLastRefill).inMilliseconds / 1000.0;
    _backendTokens =
        (_backendTokens + elapsed * _backendRefillRate).clamp(0.0, _backendMaxTokens.toDouble());
    _backendLastRefill = now;
  }
}
