// lib/features/ytm_search/cubit/ytm_search_cubit.dart
import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import '../../../core/services/ytm_service.dart';
import 'ytm_search_state.dart';

@injectable
class YtmSearchCubit extends Cubit<YtmSearchState> {
  final YtmService _service;
  Timer? _debounceTimer;

  /// A YouTube search is several network round trips, so a slow earlier request
  /// can land after a later one. Only the newest generation may emit.
  int _generation = 0;

  YtmSearchCubit({required YtmService service})
      : _service = service,
        super(const YtmSearchState());

  void onQueryChanged(String query) {
    emit(state.copyWith(query: query));
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 250), () {
      _executeSearch(query);
    });
  }

  void clearQuery() {
    _debounceTimer?.cancel();
    _generation++;
    emit(const YtmSearchState());
  }

  void clearError() {
    emit(state.copyWith(errorMessage: null));
  }

  Future<void> retry() => _executeSearch(state.query);

  Future<void> _executeSearch(String query) async {
    final generation = ++_generation;
    if (query.trim().isEmpty) {
      emit(state.copyWith(results: [], isLoading: false, errorMessage: null));
      return;
    }

    emit(state.copyWith(isLoading: true, errorMessage: null));
    try {
      final results = await _service.search(query);
      if (generation != _generation || isClosed) return;
      emit(state.copyWith(results: results, isLoading: false, errorMessage: null));
    } on YtmException catch (e) {
      if (generation != _generation || isClosed) return;
      emit(state.copyWith(isLoading: false, results: [], errorMessage: _messageFor(e)));
    }
  }

  String _messageFor(YtmException e) {
    if (e.isNetwork) return 'No connection. Check your network and try again.';
    if (e.isDisabled) return 'YouTube Music is not available in this build.';
    if (e.code == 'YTM_RECAPTCHA') {
      return 'YouTube is rate-limiting this device. Try again in a few minutes.';
    }
    return 'Search failed. Try again.';
  }

  @override
  Future<void> close() {
    _debounceTimer?.cancel();
    return super.close();
  }
}
