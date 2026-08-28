// lib/core/bloc/base_cubit.dart
import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rxdart/rxdart.dart';

/// Base cubit that prevents emit-after-close errors and guarantees
/// automatic disposal of stream subscriptions on close.
abstract class PulsrCubit<S> extends Cubit<S> {
  PulsrCubit(super.initialState);

  final CompositeSubscription _subs = CompositeSubscription();

  /// Visible for testing to verify subscription count.
  int get activeSubscriptionCount => _subs.length;

  /// Safe emit that strictly guards closed cubits.
  void safeEmit(S newState) {
    if (!isClosed) {
      emit(newState);
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
    _subs.add(sub);
    return sub;
  }

  @override
  Future<void> close() async {
    await _subs.dispose();
    return super.close();
  }
}
