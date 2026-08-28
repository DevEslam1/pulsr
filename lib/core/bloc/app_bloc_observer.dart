// lib/core/bloc/app_bloc_observer.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../utils/error_logger.dart';

class AppBlocObserver extends BlocObserver {
  @override
  void onChange(BlocBase bloc, Change change) {
    super.onChange(bloc, change);
    if (kDebugMode) {
      final runtimeStr = bloc.runtimeType.toString();
      if (!runtimeStr.contains('PlayerCubit') || kProfileMode) {
        debugPrint('[Bloc Change] ${bloc.runtimeType}: ${change.currentState.runtimeType} -> ${change.nextState.runtimeType}');
      }
    }
  }

  @override
  void onError(BlocBase bloc, Object error, StackTrace stackTrace) {
    super.onError(bloc, error, stackTrace);
    ErrorLogger.log(
      'Bloc error in ${bloc.runtimeType}',
      error: error,
      stackTrace: stackTrace,
      category: bloc.runtimeType.toString(),
    );
  }
}
