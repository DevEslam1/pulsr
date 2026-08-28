// test/core/bloc/pulsr_cubit_test.dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/bloc/base_cubit.dart';

class TestPulsrCubit extends PulsrCubit<int> {
  TestPulsrCubit([super.initialState = 0]);

  void increment() => safeEmit(state + 1);

  void listenToStream(Stream<int> stream) {
    autoSub(stream, (val) => safeEmit(val));
  }
}

void main() {
  group('PulsrCubit (Base Cubit)', () {
    test('safeEmit updates state when open', () {
      final cubit = TestPulsrCubit();
      expect(cubit.state, 0);

      cubit.increment();
      expect(cubit.state, 1);

      cubit.close();
    });

    test('safeEmit silently drops emissions after close() without throwing', () async {
      final cubit = TestPulsrCubit();
      await cubit.close();

      expect(() => cubit.increment(), returnsNormally);
      expect(cubit.state, 0);
    });

    test('autoSub manages stream subscriptions and auto-disposes on close()', () async {
      final controller = StreamController<int>.broadcast();
      final cubit = TestPulsrCubit();

      cubit.listenToStream(controller.stream);
      expect(cubit.activeSubscriptionCount, 1);

      controller.add(42);
      await Future.delayed(const Duration(milliseconds: 10));
      expect(cubit.state, 42);

      await cubit.close();
      expect(cubit.activeSubscriptionCount, 0);

      // Sending to closed cubit must not throw
      expect(() => controller.add(99), returnsNormally);
      await controller.close();
    });

    test('autoSub routes unhandled stream errors to addError', () async {
      final controller = StreamController<int>.broadcast();
      final cubit = TestPulsrCubit();

      cubit.listenToStream(controller.stream);

      final error = Exception('Stream failure');
      controller.addError(error);

      await Future.delayed(const Duration(milliseconds: 10));
      await cubit.close();
      await controller.close();
    });
  });
}
