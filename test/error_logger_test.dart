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

    test('redactPii scrubs emails, auth tokens, po_token, and session cookies (BUG-027)', () {
      const emailFixture = 'User email is test.user@example.com logged in';
      final scrubbedEmail = ErrorLogger.redactPii(emailFixture);
      expect(scrubbedEmail, contains('[REDACTED_EMAIL]'));
      expect(scrubbedEmail, isNot(contains('test.user@example.com')));

      const cookieFixture = 'SAPISID=123456789abcdef; __Secure-3PSID=secret_psid_val; po_token=potoken_secret_val; other=ok';
      final scrubbedCookie = ErrorLogger.redactPii(cookieFixture);
      expect(scrubbedCookie, contains('SAPISID=[REDACTED_TOKEN]'));
      expect(scrubbedCookie, contains('__Secure-3PSID=[REDACTED_TOKEN]'));
      expect(scrubbedCookie, contains('po_token=[REDACTED_TOKEN]'));
      expect(scrubbedCookie, isNot(contains('123456789abcdef')));
      expect(scrubbedCookie, isNot(contains('secret_psid_val')));
      expect(scrubbedCookie, isNot(contains('potoken_secret_val')));

      const authHeaderFixture = 'Authorization: Bearer my_secret_jwt_token_here';
      final scrubbedAuth = ErrorLogger.redactPii(authHeaderFixture);
      expect(scrubbedAuth, contains('Authorization: [REDACTED_TOKEN]'));
      expect(scrubbedAuth, isNot(contains('my_secret_jwt_token_here')));
    });
  });
}
