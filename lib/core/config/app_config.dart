// lib/core/config/app_config.dart
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

  static String get appTitle {
    final lowerFlavor = flavor.toLowerCase();
    if (lowerFlavor == 'ytm' || ytmEnabled) {
      return 'Pulsr Music';
    }
    return isProd ? 'Pulsr Music' : 'Pulsr Dev';
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
