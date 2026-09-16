// lib/core/config/app_config.dart
import 'package:flutter/services.dart';
import '../utils/error_logger.dart';

enum AppEnvironment { dev, prod }

class AppConfig {
  static const String envName =
      String.fromEnvironment('ENV', defaultValue: 'dev');
  static const String sentryDsn =
      String.fromEnvironment('SENTRY_DSN', defaultValue: '');
  static const String flavor =
      String.fromEnvironment('FLAVOR', defaultValue: 'dev');
  static const String appVersion =
      String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');

  /// YouTube Music search/stream/download. Off by default so Play Store builds
  /// never expose it; enable with `--dart-define=ENABLE_YTM=true`.
  ///
  /// Being a `const false` lets Dart tree-shake the guarded branches, but the
  /// generated DI config still imports every service, so this is not a
  /// guarantee that no YouTube code reaches the binary.
  static const bool ytmEnabled =
      bool.fromEnvironment('ENABLE_YTM', defaultValue: false);

  static AppEnvironment get environment {
    final lowerFlavor = flavor.toLowerCase();
    if (lowerFlavor == 'prod') {
      return AppEnvironment.prod;
    }
    switch (envName.toLowerCase()) {
      case 'prod':
      case 'production':
        return AppEnvironment.prod;
      case 'dev':
      case 'development':
      default:
        return AppEnvironment.dev;
    }
  }

  static bool get isProd => environment == AppEnvironment.prod;
  static bool get isDev => environment == AppEnvironment.dev;

  /// Pulsr Pure: Play Store offline-only build. No INTERNET permission
  /// (see android/app/src/prod/AndroidManifest.xml), no YTM, no Firebase,
  /// no Sentry, no cloud sync — competes with Musicolet on manifest privacy.
  static bool get isPure => isProd && !ytmEnabled;

  /// Runtime Pure check: asks the platform whether the INTERNET permission
  /// is present in the merged manifest, so a bad manifest merge can't
  /// silently ship network access in a Pure build. Returns null off Android,
  /// when the native hook is absent, or on error (treat as "unknown").
  static Future<bool?> verifyPureNoInternet() async {
    if (!isPure) return false;
    try {
      const channel = MethodChannel('com.pulsr.music/purity');
      final bool? hasInternet =
          await channel.invokeMethod<bool>('hasInternetPermission');
      if (hasInternet == null) return null;
      return !hasInternet;
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Telemetry (Sentry/Firebase) is only allowed outside Pure builds and
  /// only when a DSN is actually configured (main.dart already gates on this).
  static bool get isTelemetryAllowed => !isPure && sentryDsn.isNotEmpty;

  /// Cloud sync / remote metadata fetch must be hard-off in Pure builds even
  /// if stale prefs say otherwise.
  static bool get isCloudSyncAllowed => !isPure;

  static String get appTitle {
    final lowerFlavor = flavor.toLowerCase();
    if (lowerFlavor == 'ytm' || ytmEnabled) {
      return 'Pulsr Music';
    }
    // B-08 single source of truth: dev flavor's native label is "Pulsr Plus" (app/build.gradle.kts)
    // Align Dart title so launcher + in-app branding match. Prod stays "Pulsr Music".
    if (lowerFlavor == 'dev') return 'Pulsr Plus';
    return isProd ? 'Pulsr Music' : 'Pulsr Plus';
  }

  /// Validates that build flavor and runtime environment configuration are aligned.
  static void validateConfiguration() {
    final lowerFlavor = flavor.toLowerCase();
    if (lowerFlavor == 'prod' && envName.toLowerCase() == 'dev') {
      throw StateError('CRITICAL: Production flavor cannot run with ENV=dev');
    }
    // Play Store compliance: the dedicated "prod" flavor MUST NOT have YouTube Music enabled
    if (lowerFlavor == 'prod' && ytmEnabled) {
      throw StateError(
        'CRITICAL: Production Play Store builds (flavor "prod") must not enable YouTube Music features (ENABLE_YTM=true). Use flavor "ytm" for YTM builds.',
      );
    }
    if ((lowerFlavor == 'dev' || lowerFlavor == 'ytm') && !ytmEnabled) {
      ErrorLogger.log(
        'Flavor is "$flavor" (native NewPipe bridge compiled) but Dart gate ENABLE_YTM is false. Run with --dart-define=ENABLE_YTM=true to activate YTM features.',
        category: 'AppConfig',
      );
    }
  }
}
