// test/core/bloc/base_cubit_test.dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/bloc/base_cubit.dart';

class _TestCubit extends PulsrCubit<int> {
  _TestCubit([super.initialState = 0]);

  final List<Object> errors = [];

  @override
  void onError(Object error, StackTrace stackTrace) {
    errors.add(error);
    super.onError(error, stackTrace);
  }
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  group('UiEffect', () {
    test('ShowToastEffect carries its message and HapticEffect is a UiEffect',
        () {
      const toast = ShowToastEffect('hello');
      expect(toast.message, 'hello');
      expect(toast, isA<UiEffect>());
      expect(const HapticEffect(), isA<UiEffect>());
    });
  });

  group('PulsrCubit.safeEmit', () {
    test('emits while open and is inert after close', () async {
      final cubit = _TestCubit();
      expect(cubit.state, 0);
      cubit.safeEmit(1);
      expect(cubit.state, 1);
      await cubit.close();
      cubit.safeEmit(2);
      expect(cubit.state, 1, reason: 'closed cubits must not emit');
    });
  });

  group('PulsrCubit.emitEffect', () {
    test('broadcasts effects while open and stops after close', () async {
      final cubit = _TestCubit();
      final received = <UiEffect>[];
      final sub = cubit.effects.listen(received.add);
      addTearDown(sub.cancel);

      cubit.emitEffect(const ShowToastEffect('a'));
      cubit.emitEffect(const HapticEffect());
      await _flush();
      expect(received, hasLength(2));
      expect(received.first, isA<ShowToastEffect>());

      await cubit.close();
      cubit.emitEffect(const HapticEffect());
      await _flush();
      expect(received, hasLength(2));
    });
  });

  group('PulsrCubit.autoSub', () {
    test('delivers data and is cancelled on close', () async {
      final cubit = _TestCubit();
      final received = <int>[];
      cubit.autoSub<int>(Stream.fromIterable([1, 2, 3]), received.add);
      await _flush();
      expect(received, [1, 2, 3]);
      expect(cubit.activeSubscriptionCount, 1);
      await cubit.close();
      expect(cubit.activeSubscriptionCount, 0);
    });

    test('routes unhandled stream errors to addError', () async {
      final cubit = _TestCubit();
      final sub = cubit.stream.listen((_) {}, onError: (_) {});
      addTearDown(sub.cancel);
      cubit.autoSub<int>(Stream<int>.error(StateError('boom')), (_) {});
      await _flush();
      expect(cubit.errors, hasLength(1));
      expect(cubit.errors.single, isA<StateError>());
      await cubit.close();
    });

    test('prefers an explicit onError over addError', () async {
      final cubit = _TestCubit();
      Object? captured;
      cubit.autoSub<int>(
        Stream<int>.error(StateError('x')),
        (_) {},
        onError: (e, s) => captured = e,
      );
      await _flush();
      expect(captured, isA<StateError>());
      expect(cubit.errors, isEmpty);
      await cubit.close();
    });

    test('returns an inert no-op subscription once closed', () async {
      final cubit = _TestCubit();
      await cubit.close();

      final sub = cubit.autoSub<int>(const Stream<int>.empty(), (_) {});
      expect(sub.isPaused, isFalse);
      sub.onData((_) {});
      sub.onError((_) {});
      sub.onDone(() {});
      sub.pause();
      sub.resume();
      await sub.cancel();

      await expectLater(sub.asFuture<void>(), throwsStateError);
      expect(await sub.asFuture<int>(7), 7);
    });
  });

  group('PulsrCubit.removeFromComposite', () {
    test('drops a replaced subscription from the tracked count', () async {
      final cubit = _TestCubit();
      final sub = cubit.autoSub<int>(
        Stream<int>.periodic(const Duration(hours: 1), (i) => i),
        (_) {},
      );
      expect(cubit.activeSubscriptionCount, 1);
      cubit.removeFromComposite(sub);
      expect(cubit.activeSubscriptionCount, 0);
      cubit.removeFromComposite(null);
      await sub.cancel();
      await cubit.close();
    });
  });

  group('PulsrCubit.emitOnEach', () {
    test('reduces every event into new state', () async {
      final cubit = _TestCubit();
      final controller = StreamController<int>();
      addTearDown(controller.close);
      cubit.emitOnEach<int>(controller.stream, (current, data) => current + data);
      controller.add(2);
      controller.add(3);
      await _flush();
      expect(cubit.state, 5);
      await cubit.close();
    });

    test('supports a custom error reducer', () async {
      final cubit = _TestCubit();
      final controller = StreamController<int>();
      addTearDown(controller.close);
      Object? captured;
      cubit.emitOnEach<int>(
        controller.stream,
        (current, data) => current + data,
        onError: (current, error, stackTrace) => captured = error,
      );
      controller.addError(StateError('bad'));
      await _flush();
      expect(captured, isA<StateError>());
      expect(cubit.errors, isEmpty);
      await cubit.close();
    });
  });

  group('PulsrCubit.autoTimer', () {
    test('tracks pending timers and cancels them on close', () async {
      final cubit = _TestCubit();
      final timer = cubit.autoTimer(Timer(const Duration(hours: 1), () {}));
      expect(cubit.activeTimerCount, 1);
      await cubit.close();
      expect(cubit.activeTimerCount, 0);
      expect(timer.isActive, isFalse);
    });

    test('prunes already-fired timers on the next registration', () async {
      final cubit = _TestCubit();
      final fired = cubit.autoTimer(Timer(const Duration(milliseconds: 1), () {}));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(fired.isActive, isFalse);
      cubit.autoTimer(Timer(const Duration(hours: 1), () {}));
      expect(cubit.activeTimerCount, 1);
      await cubit.close();
    });

    test('immediately cancels a timer registered after close', () async {
      final cubit = _TestCubit();
      await cubit.close();
      final timer = cubit.autoTimer(Timer(const Duration(hours: 1), () {}));
      expect(timer.isActive, isFalse);
    });
  });

  group('PulsrCubit resource accounting', () {
    test('activeResourceCount reaches zero after close', () async {
      final cubit = _TestCubit();
      cubit.autoSub<int>(
        Stream<int>.periodic(const Duration(hours: 1), (i) => i),
        (_) {},
      );
      cubit.autoTimer(Timer(const Duration(hours: 1), () {}));
      expect(cubit.activeResourceCount, 3,
          reason: 'one subscription, one timer, one open effect controller');
      await cubit.close();
      expect(cubit.activeResourceCount, 0);
    });
  });
}
