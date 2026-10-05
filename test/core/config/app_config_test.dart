import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/config/app_config.dart';

void main() {
  group('AppConfig Tests', () {
    test('Defaults to dev environment when no defines passed', () {
      expect(AppConfig.environment, AppEnvironment.dev);
      expect(AppConfig.isDev, isTrue);
      expect(AppConfig.isProd, isFalse);
      // B-08 single source: dev flavor native label is "Pulsr Plus"
      expect(AppConfig.appTitle, 'Pulsr Plus');
    });

    test('Reads environment fields', () {
      expect(AppConfig.envName, isNotNull);
      expect(AppConfig.flavor, isNotNull);
      expect(AppConfig.sentryDsn, isNotNull);
    });
  });
}
