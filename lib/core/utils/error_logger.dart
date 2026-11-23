import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../errors/app_error.dart';
import 'log_ring_buffer.dart';

class ErrorLogger {
  static void Function(dynamic error, StackTrace? stackTrace, String category)?
      onCrashReported;

  static final _emailRegex =
      RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}');
  static final _cookieAuthRegex = RegExp(
      r'\b(SAPISID|HSID|SSID|APISID|SID|SIDCC|LOGIN_INFO|__Secure-[^=;\s]+|__Host-[^=;\s]+|po_token|visitor_data)\s*=\s*([^;,\s]+)',
      caseSensitive: false);
  static final _secretKvRegex = RegExp(
      r'\b(token|api_?key|api_?sig|password|passwd|secret|access_?token|refresh_?token|id_?token|client_?secret|private_?key|session_?(?:id|key|token)|auth_?token)\s*=\s*([^;&,\s]+)',
      caseSensitive: false);
  static final _jsonCredentialRegex = RegExp(
      r'("(?:token|password|passwd|secret|api_?key|api_?sig|authorization|access_?token|refresh_?token|id_?token|client_?secret|private_?key|cookie)")\s*:\s*"[^"]*"',
      caseSensitive: false);
  static final _authHeaderRegex = RegExp(
      r'\b(Authorization|token|key):\s*(?:Bearer\s+)?([^\s,;]+)|\b(Bearer)\s+([A-Za-z0-9._~+/-]+=*)',
      caseSensitive: false);
  static final _jwtRegex = RegExp(
      r'\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}(?:\.[A-Za-z0-9_-]*)?');
  static final _userPathRegex = RegExp(
      r'(?:/Users/|/home/|[A-Za-z]:[/\\]Users[/\\])[^\s\n\r"\)\],;]+',
      caseSensitive: false);
  static final _deviceStoragePathRegex = RegExp(
      r'/(?:data/user/\d+|data/data|storage/emulated/\d+)(?:/[^\s\n\r"\)]*)?',
      caseSensitive: false);
  static final _userIdRegex = RegExp(
      r'\b(userId|user_id|memberId)\s*[:=]\s*["' ']?[A-Za-z0-9_-]+["' ']?',
      caseSensitive: false);

  /// Redacts PII including email addresses, auth tokens, JWTs, session
  /// cookies, filesystem paths, and user identifiers (P5-2 / BUG-027).
  static String redactPii(String input) {
    var sanitized = input;
    sanitized =
        sanitized.replaceAllMapped(_emailRegex, (m) => '[REDACTED_EMAIL]');
    sanitized = sanitized.replaceAllMapped(
        _cookieAuthRegex, (m) => '${m.group(1)}=[REDACTED_TOKEN]');
    sanitized = sanitized.replaceAllMapped(
        _secretKvRegex, (m) => '${m.group(1)}=[REDACTED_TOKEN]');
    sanitized = sanitized.replaceAllMapped(
        _jsonCredentialRegex, (m) => '${m.group(1)}: "[REDACTED_TOKEN]"');
    sanitized = sanitized.replaceAllMapped(
        _authHeaderRegex,
        (m) => m.group(1) != null
            ? '${m.group(1)}: [REDACTED_TOKEN]'
            : 'Bearer [REDACTED_TOKEN]');
    sanitized = sanitized.replaceAll(_jwtRegex, '[REDACTED_TOKEN]');
    sanitized = sanitized.replaceAllMapped(
        _userPathRegex, (m) => '[REDACTED_USER_PATH]');
    sanitized = sanitized.replaceAllMapped(
        _deviceStoragePathRegex, (m) => '[REDACTED_DEVICE_PATH]');
    sanitized = sanitized.replaceAllMapped(
        _userIdRegex, (m) => '${m.group(1)}: [REDACTED_ID]');
    return sanitized;
  }

  /// Wraps a logged error into a PII-scrubbed payload suitable for Sentry capture.
  @visibleForTesting
  static Object sanitizeErrorForReport(dynamic error) {
    if (error is String) {
      return redactPii(error);
    }
    final typeName = error.runtimeType.toString();
    final safeText = redactPii(error.toString());
    return _RedactedException(typeName, safeText);
  }

  /// Scrubs file paths/PII inside stack frames before forwarding to Sentry.
  @visibleForTesting
  static StackTrace? sanitizeStackTrace(StackTrace? stackTrace) {
    if (stackTrace == null) return null;
    final raw = stackTrace.toString();
    final clean = redactPii(raw);
    if (identical(clean, raw) || clean == raw) return stackTrace;
    return StackTrace.fromString(clean);
  }

  static void log(
    String message, {
    dynamic error,
    StackTrace? stackTrace,
    String category = 'App',
    Map<String, dynamic>? meta,
  }) {
    final sanitizedMessage = redactPii(message);
    // Diagnostics bundle (P1-10): keep the last 200 classified lines in a core
    // ring buffer so a support export can attach them without reading logcat.
    // The buffer stores only redacted text and never grows past its cap; living
    // in core keeps the logger free of feature imports.
    LogRingBuffer.add(
      sanitizedMessage,
      level: error != null ? 'ERROR' : 'INFO',
      category: category,
    );
    if (kDebugMode) {
      developer.log(
        sanitizedMessage,
        name: 'Pulsr.$category',
        error: error,
        stackTrace: stackTrace,
      );
    }
    final sanitizedMeta = meta == null ? null : redactMap(meta);
    if (Sentry.isEnabled) {
      Sentry.addBreadcrumb(
        Breadcrumb(
          message: sanitizedMessage,
          category: category,
          data: sanitizedMeta,
          level: error != null ? SentryLevel.error : SentryLevel.info,
          timestamp: DateTime.now(),
        ),
      );
    }
    if (error != null) {
      // ADR-002: every failure that reaches the logger is classified into the
      // sealed AppError taxonomy so crash reports carry a stable error type
      // instead of an opaque runtime type.
      final classified = resolveAppError(error, stackTrace);
      final errorType = classified.runtimeType.toString();
      debugPrint(
          '[Pulsr.Error][$category] $sanitizedMessage: ${redactPii(error.toString())}');
      onCrashReported?.call(error, stackTrace, category);
      if (Sentry.isEnabled) {
        final safeError = sanitizeErrorForReport(error);
        final safeStackTrace = sanitizeStackTrace(stackTrace);
        final safeUserMessage = redactPii(classified.userMessage);
        Sentry.captureException(
          safeError,
          stackTrace: safeStackTrace,
          withScope: (scope) {
            scope.setTag('category', category);
            scope.setTag('errorType', errorType);
            scope.setContexts('message', {'value': sanitizedMessage});
            scope.setContexts('classifiedError', {
              'type': errorType,
              'message': safeUserMessage,
            });
            if (sanitizedMeta != null) {
              scope.setContexts('meta', sanitizedMeta);
            }
          },
        );
      }
    }
  }

  static final _sensitiveKeyRegex = RegExp(
    r'(?:token|auth|authorization|cookie|secret|password|passwd|pwd|api_?key|api_?sig|sapisid|session|credential|private_?key|po_token|visitor_data|email)',
    caseSensitive: false,
  );

  /// Recursively redacts PII and credential fields inside arbitrary metadata maps.
  static Map<String, dynamic> redactMap(Map<dynamic, dynamic> input) {
    final result = <String, dynamic>{};
    for (final entry in input.entries) {
      final key = entry.key.toString();
      result[key] = redactValue(entry.value, keyName: key);
    }
    return result;
  }

  /// Recursively scrubs PII from strings, maps, and iterables.
  static dynamic redactValue(
    dynamic value, {
    String? keyName,
    int depth = 0,
  }) {
    if (value == null) return null;
    if (depth > 16) return '[REDACTED_DEPTH_LIMIT]';
    final isSensitiveKey =
        keyName != null && _sensitiveKeyRegex.hasMatch(keyName);
    if (value is Map) {
      final out = <String, dynamic>{};
      for (final entry in value.entries) {
        final k = entry.key.toString();
        out[k] = redactValue(entry.value, keyName: k, depth: depth + 1);
      }
      return out;
    }
    if (value is Iterable) {
      return value
          .map((item) => redactValue(item, keyName: keyName, depth: depth + 1))
          .toList(growable: false);
    }
    if (value is String) {
      if (isSensitiveKey) return '[REDACTED_TOKEN]';
      return redactPii(value).replaceAll(_jwtRegex, '[REDACTED_TOKEN]');
    }
    if (value is Uri) {
      if (isSensitiveKey) return '[REDACTED_TOKEN]';
      return redactPii(value.toString())
          .replaceAll(_jwtRegex, '[REDACTED_TOKEN]');
    }
    if (isSensitiveKey) return '[REDACTED_TOKEN]';
    return value;
  }

  static void addBreadcrumb(
    String message, {
    String category = 'event',
    Map<String, dynamic>? data,
  }) {
    final sanitizedMessage = redactPii(message);
    final sanitizedData = data == null ? null : redactMap(data);

    if (kDebugMode) {
      developer.log(
        'Breadcrumb: $sanitizedMessage ${sanitizedData != null ? sanitizedData.toString() : ""}',
        name: 'Pulsr.$category',
      );
    }
    if (Sentry.isEnabled) {
      Sentry.addBreadcrumb(
        Breadcrumb(
          message: sanitizedMessage,
          category: category,
          data: sanitizedData,
          timestamp: DateTime.now(),
        ),
      );
    }
  }

  static const int _maxSwallowedRateLimits = 256;
  static final Map<String, ({DateTime lastLog, int count})>
      _swallowedRateLimits = {};

  @visibleForTesting
  static int get swallowedRateLimitsCount => _swallowedRateLimits.length;

  @visibleForTesting
  static void clearSwallowedRateLimitsForTesting() =>
      _swallowedRateLimits.clear();

  /// Rate-limited logging for swallowed/caught errors (Phase 6).
  /// Logs at most once every 60 seconds per [where] site, accumulating suppressed counts.
  /// Bounded to 256 call-sites to prevent memory leaks from dynamic keys.
  static void logSwallowed(String where, Object error,
      [StackTrace? stackTrace]) {
    final now = DateTime.now();
    final entry = _swallowedRateLimits[where];
    if (entry == null ||
        now.difference(entry.lastLog) > const Duration(seconds: 60)) {
      final suppressed = entry?.count ?? 0;
      final msg = suppressed > 0
          ? 'Swallowed exception at $where ($suppressed repeats suppressed)'
          : 'Swallowed exception at $where';

      if (!_swallowedRateLimits.containsKey(where) &&
          _swallowedRateLimits.length >= _maxSwallowedRateLimits) {
        final oldestKey = _swallowedRateLimits.entries
            .reduce((a, b) => a.value.lastLog.isBefore(b.value.lastLog) ? a : b)
            .key;
        _swallowedRateLimits.remove(oldestKey);
      }

      _swallowedRateLimits[where] = (lastLog: now, count: 0);
      log(msg,
          error: error, stackTrace: stackTrace, category: 'SwallowedError');
    } else {
      _swallowedRateLimits[where] =
          (lastLog: entry.lastLog, count: entry.count + 1);
    }
  }

  static void initialize() {
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      // Surface the framework's "relevant error-causing widget" diagnostic so
      // render/layout failures can be traced to a concrete widget without
      // re-running the app with a debugger.
      final contextDescription = details.context?.toDescription();
      final library = details.library;
      final suffix = [
        if (contextDescription != null && contextDescription.isNotEmpty)
          contextDescription,
        if (library != null && library.isNotEmpty) library,
      ].join(' | ');
      log(
        'Unhandled Flutter Error: ${details.exceptionAsString()}'
        '${suffix.isEmpty ? '' : ' [$suffix]'}',
        error: details.exception,
        stackTrace: details.stack,
        category: 'FlutterError',
      );
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      log(
        'Unhandled Async Platform Error: $error',
        error: error,
        stackTrace: stack,
        category: 'PlatformError',
      );
      return true;
    };
  }
}

class _RedactedException implements Exception {
  final String originalType;
  final String redactedMessage;

  const _RedactedException(this.originalType, this.redactedMessage);

  @override
  String toString() =>
      redactedMessage.startsWith(originalType)
          ? redactedMessage
          : '$originalType: $redactedMessage';
}
