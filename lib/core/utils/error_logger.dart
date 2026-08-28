import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

class ErrorLogger {
  static void Function(dynamic error, StackTrace? stackTrace, String category)?
      onCrashReported;

  static final _emailRegex =
      RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}');
  static final _cookieAuthRegex = RegExp(
      r'\b(SAPISID|HSID|SSID|APISID|SID|__Secure-[^=;\s]+|po_token|visitor_data)\s*=\s*([^;,\s]+)',
      caseSensitive: false);
  static final _authHeaderRegex = RegExp(
      r'\b(Authorization|token|key):\s*(?:Bearer\s+)?([^\s,;]+)|\b(Bearer)\s+([A-Za-z0-9._~+/-]+=*)',
      caseSensitive: false);

  /// Redacts PII including email addresses, auth tokens, and session cookies (BUG-027).
  static String redactPii(String input) {
    var sanitized = input;
    sanitized = sanitized.replaceAllMapped(_emailRegex, (m) => '[REDACTED_EMAIL]');
    sanitized = sanitized.replaceAllMapped(
        _cookieAuthRegex, (m) => '${m.group(1)}=[REDACTED_TOKEN]');
    sanitized = sanitized.replaceAllMapped(
        _authHeaderRegex,
        (m) => m.group(1) != null
            ? '${m.group(1)}: [REDACTED_TOKEN]'
            : 'Bearer [REDACTED_TOKEN]');
    return sanitized;
  }

  static void log(
    String message, {
    dynamic error,
    StackTrace? stackTrace,
    String category = 'App',
  }) {
    final sanitizedMessage = redactPii(message);
    if (kDebugMode) {
      developer.log(
        sanitizedMessage,
        name: 'Pulsr.$category',
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (error != null) {
      onCrashReported?.call(error, stackTrace, category);
      if (Sentry.isEnabled) {
        Sentry.captureException(
          error,
          stackTrace: stackTrace,
          withScope: (scope) {
            scope.setTag('category', category);
            scope.setContexts('message', {'value': sanitizedMessage});
          },
        );
      }
    }
  }

  static void addBreadcrumb(
    String message, {
    String category = 'event',
    Map<String, dynamic>? data,
  }) {
    final sanitizedMessage = redactPii(message);
    final sanitizedData = data?.map((k, v) => MapEntry(
          k,
          v is String ? redactPii(v) : v,
        ));

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

  static void initialize() {
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      log(
        'Unhandled Flutter Error: ${details.exceptionAsString()}',
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
