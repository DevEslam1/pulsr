// lib/core/config/app_config.dart

enum AppEnvironment { dev, prod }

class AppConfig {
  static const String envName = String.fromEnvironment('ENV', defaultValue: 'dev');
  static const String sentryDsn = String.fromEnvironment('SENTRY_DSN', defaultValue: '');
  static const String flavor = String.fromEnvironment('FLAVOR', defaultValue: 'dev');

  static AppEnvironment get environment {
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

  static String get appTitle => isProd ? 'Pulsr Music' : 'Pulsr Dev';
}
