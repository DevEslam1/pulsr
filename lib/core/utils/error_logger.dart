// lib/core/utils/error_logger.dart
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

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
    } else {
      // In release mode, route to crash reporting hook if configured
      if (error != null) {
        onCrashReported?.call(error, stackTrace, category);
      }
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
