import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

class ErrorLogger {
  static void Function(dynamic error, StackTrace? stackTrace, String category)? onCrashReported;

  static void log(
    String message, {
    dynamic error,
    StackTrace? stackTrace,
    String category = 'App',
  }) {
    if (kDebugMode) {
      developer.log(
        message,
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
            scope.setContexts('message', {'value': message});
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
    if (kDebugMode) {
      developer.log(
        'Breadcrumb: $message ${data != null ? data.toString() : ""}',
        name: 'Pulsr.$category',
      );
    }
    if (Sentry.isEnabled) {
      Sentry.addBreadcrumb(
        Breadcrumb(
          message: message,
          category: category,
          data: data,
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
