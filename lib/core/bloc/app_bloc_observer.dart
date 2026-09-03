// lib/core/bloc/app_bloc_observer.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import '../utils/app_logger.dart';
import '../utils/error_logger.dart';

class AppBlocObserver extends BlocObserver {
  @override
  // flutter_bloc's BlocObserver API declares raw BlocBase/Change parameters;
  // the override must match the SDK signature exactly.
  // ignore: strict_raw_type
  void onChange(BlocBase bloc, Change change) {
    super.onChange(bloc, change);
    if (kDebugMode || kProfileMode) {
      final runtimeStr = bloc.runtimeType.toString();
      if (!runtimeStr.contains('PlayerCubit') || kProfileMode) {
        AppLogger.debug(
            '[Bloc Change] ${bloc.runtimeType}: ${change.currentState.runtimeType} -> ${change.nextState.runtimeType}',
            category: 'Bloc');
      }
    }
  }

  @override
  // ignore: strict_raw_type
  void onError(BlocBase bloc, Object error, StackTrace stackTrace) {
    super.onError(bloc, error, stackTrace);
    ErrorLogger.log(
      'Bloc error in ${bloc.runtimeType}',
      error: error,
      stackTrace: stackTrace,
      category: bloc.runtimeType.toString(),
    );
    // Forward to Sentry with bloc context: an exception reaching a bloc/cubit
    // error stream means a UI-visible feature failed, so it must be tracked.
    // Sentry SDK is a no-op when the DSN is empty; guarded against reentrancy.
    try {
      Sentry.addBreadcrumb(Breadcrumb(
        message: 'Bloc error in ${bloc.runtimeType}',
        category: 'bloc',
        level: SentryLevel.error,
      ));
      Sentry.captureException(error, stackTrace: stackTrace);
    } catch (e) {
      // Never let telemetry failures mask the original error.
      AppLogger.debug('onError failed (non-fatal): $e', category: 'AppBlocObserver');
    }
  }
}
