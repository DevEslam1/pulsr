// lib/core/bloc/base_cubit.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rxdart/rxdart.dart';

/// Transient one-off UI event (toast, banner, haptic, navigation command).
///
/// Effects are NEVER stored in persistent state: they are broadcast on a
/// separate stream, consumed exactly once by the UI, and cannot re-fire on
/// widget rebuilds. State fields like `errorMessage` remain for *persisted*
/// error surfaces (inline banners that must survive rebuilds).
sealed class UiEffect {
  const UiEffect();
}

/// Shows a dismissible snackbar/toast with [message].
class ShowToastEffect extends UiEffect {
  final String message;
  const ShowToastEffect(this.message);
}

/// Haptic feedback pulse for action confirmation.
class HapticEffect extends UiEffect {
  const HapticEffect();
}

/// Base cubit that prevents emit-after-close errors and guarantees
/// automatic disposal of stream subscriptions and timers on close.
abstract class PulsrCubit<S> extends Cubit<S> {
  PulsrCubit(super.initialState);

  final CompositeSubscription _subs = CompositeSubscription();
  final List<Timer> _timers = [];
  final StreamController<UiEffect> _effectController =
      StreamController<UiEffect>.broadcast();
  bool _closed = false;

  /// Visible for testing to verify subscription count. Reports 0 once the
  /// cubit has closed — every registered subscription was provably cancelled.
  int get activeSubscriptionCount => _closed ? 0 : _subs.length;

  /// Visible for testing: timers still pending cancellation.
  @visibleForTesting
  int get activeTimerCount => _timers.where((t) => t.isActive).length;

  /// Visible for testing: everything this cubit still holds open. A soak test
  /// asserts this reaches 0 after [close].
  @visibleForTesting
  int get activeResourceCount =>
      activeSubscriptionCount + activeTimerCount + (_effectController.isClosed ? 0 : 1);

  /// One-shot transient UI events. Consumed via a single subscription in the
  /// owning widget; closes with the cubit.
  Stream<UiEffect> get effects => _effectController.stream;

  /// Safe emit that strictly guards closed cubits.
  void safeEmit(S newState) {
    if (!isClosed) {
      emit(newState);
    }
  }

  /// Emits [effect] on the transient event stream. No-op after close.
  /// Never throws, never stores the effect in state.
  void emitEffect(UiEffect effect) {
    if (!isClosed && !_effectController.isClosed) {
      _effectController.add(effect);
    }
  }

  /// Registers a stream subscription that is automatically cancelled on [close].
  /// Unhandled stream errors are automatically reported to [addError]
  /// which routes to BlocObserver and Sentry.
  StreamSubscription<T> autoSub<T>(
    Stream<T> stream,
    void Function(T data) onData, {
    void Function(Object error, StackTrace stackTrace)? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final sub = stream.listen(
      (data) {
        if (!isClosed) {
          onData(data);
        }
      },
      onError: (Object e, StackTrace s) {
        if (onError != null) {
          onError(e, s);
        } else {
          addError(e, s);
        }
      },
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
    if (_closed) {
      // The cubit closed while an async constructor path was still in flight:
      // drop the late subscription instead of registering with a disposed
      // container (which would throw).
      sub.cancel();
      return sub;
    }
    _subs.add(sub);
    return sub;
  }

  /// Removes a (typically just-cancelled) subscription from the composite.
  /// Use this when a subscription is being REPLACED (refresh / re-subscribe
  /// pattern): a bare `sub.cancel()` leaves the cancelled subscription
  /// registered inside the [CompositeSubscription], so every re-subscribe
  /// would inflate [activeSubscriptionCount] forever. Pair with an explicit
  /// cancel before re-adding:
  ///
  ///     _albumsSub?.cancel();
  ///     removeFromComposite(_albumsSub);
  ///     _albumsSub = autoSub(...);
  void removeFromComposite(StreamSubscription<dynamic>? sub) {
    if (sub == null) return;
    _subs.remove(sub);
  }

  /// Reduces every [stream] event into a new state; the subscription is
  /// auto-cancelled on close. Errors route to [addError] (or [onError]).
  StreamSubscription<T> emitOnEach<T>(
    Stream<T> stream,
    S Function(S current, T data) reducer, {
    void Function(S current, Object error, StackTrace stackTrace)? onError,
  }) {
    return autoSub(
      stream,
      (data) {
        if (!isClosed) {
          emit(reducer(state, data));
        }
      },
      onError: onError != null ? (e, s) => onError(state, e, s) : null,
    );
  }

  /// Registers a [Timer] that is automatically cancelled on [close].
  /// Already-fired/cancelled timers are pruned so repeated debounce churn
  /// cannot grow the registry.
  Timer autoTimer(Timer timer) {
    _timers.removeWhere((t) => !t.isActive);
    _timers.add(timer);
    return timer;
  }

  @override
  Future<void> close() async {
    // Teardown is initiated synchronously but never awaited:
    //
    // Timer/subscription *cancellation* below is synchronous, so resources are
    // deterministically released; what we deliberately do NOT await are the
    // completion futures of the broadcast controllers (effects, bloc's internal
    // state stream) and of the composite disposal. Those futures only complete
    // once every attached listener has processed the `done` event, and
    // widget-tree-bound subscriptions (flutter_bloc builders/selectors) may
    // defer that delivery until the tree is torn down. Awaiting them from a
    // fake-async widget test therefore deadlocks `await cubit.close()` until
    // the test times out (observed: 10-minute TimeoutException in
    // downloads_tile_test). Closing must never block on the UI tree.
    _closed = true;
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
    unawaited(_effectController.close());
    unawaited(_subs.dispose());
    unawaited(super.close());
  }
}
