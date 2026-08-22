import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/utils/error_logger.dart';

void main() {
  group('ErrorLogger Tests', () {
    test('Logs message without error', () {
      expect(() => ErrorLogger.log('Informational message', category: 'Test'), returnsNormally);
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

      ErrorLogger.log('Test crash', error: error, stackTrace: stack, category: 'UnitTests');

      expect(reportedError, equals(error));
      expect(reportedStackTrace, equals(stack));
      expect(reportedCategory, equals('UnitTests'));

      ErrorLogger.onCrashReported = null;
    });

    test('Records breadcrumb without crashing when Sentry is disabled or enabled', () {
      expect(
        () => ErrorLogger.addBreadcrumb('Playback started', category: 'player', data: {'songId': 42}),
        returnsNormally,
      );
    });
  });
}
