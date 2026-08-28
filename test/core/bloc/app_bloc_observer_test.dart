// test/core/bloc/app_bloc_observer_test.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/bloc/app_bloc_observer.dart';
import 'package:pulsr/core/utils/error_logger.dart';

class _DummyCubit extends Cubit<int> {
  _DummyCubit() : super(0);

  void triggerError(Object error, StackTrace stack) {
    onError(error, stack);
  }
}

void main() {
  group('AppBlocObserver Observability Tests', () {
    late AppBlocObserver observer;
    dynamic capturedError;
    StackTrace? capturedStack;
    String? capturedCategory;

    setUp(() {
      observer = AppBlocObserver();
      capturedError = null;
      capturedStack = null;
      capturedCategory = null;

      ErrorLogger.onCrashReported = (error, stack, category) {
        capturedError = error;
        capturedStack = stack;
        capturedCategory = category;
      };
    });

    tearDown(() {
      ErrorLogger.onCrashReported = null;
    });

    test('onError routes cubit exceptions to ErrorLogger with category and stackTrace', () {
      final cubit = _DummyCubit();
      final exception = Exception('Simulated bloc failure');
      final stack = StackTrace.current;

      observer.onError(cubit, exception, stack);

      expect(capturedError, equals(exception));
      expect(capturedStack, equals(stack));
      expect(capturedCategory, equals('_DummyCubit'));
    });

    test('onChange logs without throwing', () {
      final cubit = _DummyCubit();
      expect(() => observer.onChange(cubit, const Change(currentState: 0, nextState: 1)), returnsNormally);
    });
  });
}
