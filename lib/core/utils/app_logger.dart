// lib/core/utils/app_logger.dart
// Central debug/telemetry logger — single `avoid_print` exemption point.
//
// All diagnostic output MUST go through [AppLogger] instead of raw
// `debugPrint`/`print` so release builds stay silent and every message is
// routed consistently:
//  - debug/profile: `dart:developer log` (visible in DevTools, no release noise)
//  - errors: [ErrorLogger.log] (Sentry + redaction)
// ignore: avoid_print — this file is the sole sanctioned print/log site.
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import 'error_logger.dart';

/// Central application logger.
///
/// Replaces scattered `debugPrint` calls (100+ sites) with a single audited
/// gateway. `debug()` is a no-op in release; `info/warning/error` always
/// forward to [ErrorLogger] so diagnostics survive in crash reports.
class AppLogger {
  const AppLogger._();

  /// Debug-only diagnostic. No-op in release/profile-release.
  static void debug(String message, {String category = 'App'}) {
    if (kDebugMode) {
      developer.log(message, name: 'Pulsr.$category');
    }
  }

  /// Informational breadcrumb (kept in Sentry trail, debug-visible).
  static void info(String message, {String category = 'App'}) {
    ErrorLogger.addBreadcrumb(message, category: category);
    if (kDebugMode) {
      developer.log(message, name: 'Pulsr.$category');
    }
  }

  /// Non-fatal warning / recoverable failure.
  static void warning(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String category = 'App',
  }) {
    ErrorLogger.log(
      message,
      error: error,
      stackTrace: stackTrace,
      category: category,
    );
  }

  /// Fatal / user-visible failure path.
  static void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String category = 'App',
  }) {
    ErrorLogger.log(
      message,
      error: error,
      stackTrace: stackTrace,
      category: category,
    );
  }
}
