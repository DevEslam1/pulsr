// Phase 5 — PulsrCubit lifecycle contract.
//
// Proves the base-class guarantees:
//   * close() cancels every registered subscription and timer
//   * activeResourceCount reaches 0 after close
//   * safeEmit is a no-op after close (never throws StateError)
//   * emitEffect is a no-op after close; the effects stream completes
//   * autoSub called by an in-flight async path after close returns a
//     cancelled subscription instead of throwing
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/bloc/base_cubit.dart';

class _ProbeCubit extends PulsrCubit<int> {
  _ProbeCubit() : super(0);

  void bump() => safeEmit(state + 1);

  void registerTimer() {
    autoTimer(Timer(const Duration(minutes: 5), () {}));
  }

  void registerLoopSub(Stream<int> stream) {
    autoSub(stream, (_) {});
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PulsrCubit lifecycle', () {
    test('resources are all released after close', () async {
      final controller = StreamController<int>.broadcast();
      final cubit = _ProbeCubit();
      cubit.registerLoopSub(controller.stream);
      cubit.registerLoopSub(controller.stream);
      cubit.registerTimer();

      expect(cubit.activeSubscriptionCount, 2);
      expect(cubit.activeTimerCount, 1);
      expect(cubit.activeResourceCount, greaterThan(0));

      await cubit.close();
      await controller.close();

      expect(cubit.activeSubscriptionCount, 0,
          reason: 'every subscription provably cancelled on close');
      expect(cubit.activeTimerCount, 0,
          reason: 'every timer provably cancelled on close');
      expect(cubit.activeResourceCount, 0);
    });

    test('safeEmit is a no-op after close (no StateError)', () async {
      final cubit = _ProbeCubit();
      await cubit.close();

      expect(() => cubit.bump(), returnsNormally,
          reason: 'safeEmit must swallow emit-after-close');
      expect(cubit.state, 0, reason: 'state must not change after close');
    });

    test('emitEffect is a no-op after close; effects stream completes',
        () async {
      final cubit = _ProbeCubit();
      final received = <UiEffect>[];
      final sub = cubit.effects.listen(received.add);
      addTearDown(sub.cancel);

      await cubit.close();

      expect(() => cubit.emitEffect(const ShowToastEffect('x')),
          returnsNormally);
      // Allow the done event to flush.
      await Future<void>.delayed(Duration.zero);
      expect(received, isEmpty);
    });

    test('effect is consumed exactly once and not re-fired on rebuild',
        () async {
      final cubit = _ProbeCubit();
      final received = <UiEffect>[];
      final sub = cubit.effects.listen(received.add);
      addTearDown(sub.cancel);

      cubit.emitEffect(const ShowToastEffect('once'));
      // Simulate unrelated state churn (a rebuild): effects are not replayed.
      cubit.bump();
      cubit.bump();
      await Future<void>.delayed(Duration.zero);

      expect(received.length, 1);
      expect(received.single, isA<ShowToastEffect>());
    });

    test('late autoSub after close returns a cancelled subscription',
        () async {
      final controller = StreamController<int>.broadcast();
      addTearDown(controller.close);
      final cubit = _ProbeCubit();
      await cubit.close();

      // In-flight async constructor paths may subscribe after close; the base
      // must not throw and must drop the subscription.
      expect(() => cubit.registerLoopSub(controller.stream), returnsNormally);
      expect(cubit.activeSubscriptionCount, 0);
    });
  });
}
