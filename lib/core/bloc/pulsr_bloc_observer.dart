// lib/core/bloc/pulsr_bloc_observer.dart
import 'package:flutter_bloc/flutter_bloc.dart';

/// Debug and testing BlocObserver tracking state transitions and change counts per Cubit/Bloc type.
class PulsrBlocObserver extends BlocObserver {
  static final PulsrBlocObserver instance = PulsrBlocObserver._();
  PulsrBlocObserver._();

  final Map<Type, int> _changeCounts = {};
  int _totalTransitions = 0;

  int get totalTransitions => _totalTransitions;
  int countFor(Type blocType) => _changeCounts[blocType] ?? 0;

  void reset() {
    _changeCounts.clear();
    _totalTransitions = 0;
  }

  @override
  void onChange(BlocBase bloc, Change change) {
    super.onChange(bloc, change);
    _totalTransitions++;
    _changeCounts[bloc.runtimeType] =
        (_changeCounts[bloc.runtimeType] ?? 0) + 1;
  }
}
