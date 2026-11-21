import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/utils/error_logger.dart';

void main() {
  group('ErrorLogger Tests', () {
    test('Logs message without error', () {
      expect(() => ErrorLogger.log('Informational message', category: 'Test'),
          returnsNormally);
    });

    test('Invokes onCrashReported callback when error is present', () {
      dynamic reportedError;
      StackTrace? reportedStackTrace;
      String? reportedCategory;

      ErrorLogger.onCrashReported = (error, stackTrace, category) {
        reportedError = error;
        reportedStackTrace = stackTrace;
        reportedCategory = category;
      };

      final error = Exception('Simulated test error');
      final stack = StackTrace.current;

      ErrorLogger.log('Test crash',
          error: error, stackTrace: stack, category: 'UnitTests');

      expect(reportedError, equals(error));
      expect(reportedStackTrace, equals(stack));
      expect(reportedCategory, equals('UnitTests'));

      ErrorLogger.onCrashReported = null;
    });

    test(
        'Records breadcrumb without crashing when Sentry is disabled or enabled',
        () {
      expect(
        () => ErrorLogger.addBreadcrumb('Playback started',
            category: 'player', data: {'songId': 42}),
        returnsNormally,
      );
    });

    test(
        'redactPii scrubs emails, auth tokens, po_token, and session cookies (BUG-027)',
        () {
      const emailFixture = 'User email is test.user@example.com logged in';
      final scrubbedEmail = ErrorLogger.redactPii(emailFixture);
      expect(scrubbedEmail, contains('[REDACTED_EMAIL]'));
      expect(scrubbedEmail, isNot(contains('test.user@example.com')));

      const cookieFixture =
          'SAPISID=123456789abcdef; __Secure-3PSID=secret_psid_val; po_token=potoken_secret_val; other=ok';
      final scrubbedCookie = ErrorLogger.redactPii(cookieFixture);
      expect(scrubbedCookie, contains('SAPISID=[REDACTED_TOKEN]'));
      expect(scrubbedCookie, contains('__Secure-3PSID=[REDACTED_TOKEN]'));
      expect(scrubbedCookie, contains('po_token=[REDACTED_TOKEN]'));
      expect(scrubbedCookie, isNot(contains('123456789abcdef')));
      expect(scrubbedCookie, isNot(contains('secret_psid_val')));
      expect(scrubbedCookie, isNot(contains('potoken_secret_val')));

      const authHeaderFixture =
          'Authorization: Bearer my_secret_jwt_token_here';
      final scrubbedAuth = ErrorLogger.redactPii(authHeaderFixture);
      expect(scrubbedAuth, contains('Authorization: [REDACTED_TOKEN]'));
      expect(scrubbedAuth, isNot(contains('my_secret_jwt_token_here')));

      const kvFixture =
          'https://api.example.com?token=myToken123&api_key=myApiKey456&password=myPassword789&secret=mySecretXYZ';
      final scrubbedKv = ErrorLogger.redactPii(kvFixture);
      expect(scrubbedKv, contains('token=[REDACTED_TOKEN]'));
      expect(scrubbedKv, contains('api_key=[REDACTED_TOKEN]'));
      expect(scrubbedKv, contains('password=[REDACTED_TOKEN]'));
      expect(scrubbedKv, contains('secret=[REDACTED_TOKEN]'));
      expect(scrubbedKv, isNot(contains('myToken123')));
      expect(scrubbedKv, isNot(contains('myApiKey456')));
      expect(scrubbedKv, isNot(contains('myPassword789')));
      expect(scrubbedKv, isNot(contains('mySecretXYZ')));

      const jsonFixture =
          '{"token": "secret_tok", "password": "secret_pwd", "secret": "secret_sec", "api_key": "secret_key", "authorization": "secret_auth"}';
      final scrubbedJson = ErrorLogger.redactPii(jsonFixture);
      expect(scrubbedJson, contains('"token": "[REDACTED_TOKEN]"'));
      expect(scrubbedJson, contains('"password": "[REDACTED_TOKEN]"'));
      expect(scrubbedJson, contains('"secret": "[REDACTED_TOKEN]"'));
      expect(scrubbedJson, contains('"api_key": "[REDACTED_TOKEN]"'));
      expect(scrubbedJson, contains('"authorization": "[REDACTED_TOKEN]"'));
      expect(scrubbedJson, isNot(contains('secret_tok')));
      expect(scrubbedJson, isNot(contains('secret_pwd')));
      expect(scrubbedJson, isNot(contains('secret_sec')));
      expect(scrubbedJson, isNot(contains('secret_key')));
      expect(scrubbedJson, isNot(contains('secret_auth')));
    });

    test('logSwallowed caps rate limits at 256 entries evicting oldest', () {
      ErrorLogger.clearSwallowedRateLimitsForTesting();
      for (var i = 0; i < 300; i++) {
        ErrorLogger.logSwallowed('call_site_$i', Exception('err_$i'));
      }
      expect(ErrorLogger.swallowedRateLimitsCount, equals(256));
    });

    test('reports each error to onCrashReported exactly once (single sink)',
        () {
      var calls = 0;
      ErrorLogger.onCrashReported = (_, __, ___) => calls++;

      ErrorLogger.log('Single sink',
          error: Exception('boom'), category: 'UnitTests');
      ErrorLogger.log('No error means no crash report', category: 'UnitTests');

      expect(calls, 1);
      ErrorLogger.onCrashReported = null;
    });

    test('main.dart does not capture Sentry a second time from onCrashReported',
        () {
      final source = File('lib/main.dart').readAsStringSync();
      final callbackStart = source.indexOf('ErrorLogger.onCrashReported =');
      expect(callbackStart, isNot(-1),
          reason: 'main() must install the crash-report hook');
      final callbackEnd = source.indexOf('};', callbackStart);
      expect(callbackEnd, greaterThan(callbackStart));

      final callbackBody = source.substring(callbackStart, callbackEnd);
      expect(callbackBody.contains('Sentry.captureException'), isFalse,
          reason: 'ErrorLogger.log already captures; capturing in the hook '
              'would report every crash to Sentry twice');
    });
  });
}
