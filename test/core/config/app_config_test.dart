import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/config/app_config.dart';

void main() {
  group('AppConfig Tests', () {
    test('Defaults to dev environment when no defines passed', () {
      expect(AppConfig.environment, AppEnvironment.dev);
      expect(AppConfig.isDev, isTrue);
      expect(AppConfig.isProd, isFalse);
      // YTM builds intentionally brand as "Pulsr Music"; the default dev
      // flavor is "Pulsr Plus" (B-08 single source).
      expect(AppConfig.appTitle,
          AppConfig.ytmEnabled ? 'Pulsr Music' : 'Pulsr Plus');
    });

    test('Reads environment fields', () {
      expect(AppConfig.envName, isNotNull);
      expect(AppConfig.flavor, isNotNull);
      expect(AppConfig.sentryDsn, isNotNull);
    });

    test('ytmEnabled remains a compile-time const', () {
      const compiledConst = AppConfig.ytmEnabled;
      expect(compiledConst, AppConfig.ytmEnabled);
    });

    test('parseYtmEnabled golden table matches every supported alias', () {
      const goldenCases = <({String flag, String flavor, bool expected})>[
        (flag: 'true', flavor: '', expected: true),
        (flag: '1', flavor: '', expected: true),
        (flag: 'enabled', flavor: '', expected: true),
        (flag: 'enebeld', flavor: '', expected: true),
        (flag: '', flavor: 'ytm', expected: true),
        (flag: 'false', flavor: 'ytm', expected: false),
        (flag: '0', flavor: '', expected: false),
        (flag: 'disabled', flavor: '', expected: false),
        (flag: '', flavor: 'prod', expected: false),
        (flag: '', flavor: '', expected: false),
      ];

      for (final tc in goldenCases) {
        expect(
          AppConfig.parseYtmEnabled(tc.flag, flavorValue: tc.flavor),
          tc.expected,
          reason: 'flag="${tc.flag}", flavor="${tc.flavor}"',
        );
      }
    });
  });
}
