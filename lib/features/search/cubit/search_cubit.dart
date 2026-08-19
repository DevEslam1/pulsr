// lib/features/search/cubit/search_cubit.dart
import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/usecases/search_music_usecase.dart';
import 'search_state.dart';

class SearchCubit extends Cubit<SearchState> {
  final SearchMusicUseCase _searchUseCase;
  StreamSubscription? _searchSub;
  Timer? _debounceTimer;

  SearchCubit({required SearchMusicUseCase searchUseCase})
      : _searchUseCase = searchUseCase,
        super(const SearchState());

  void setFilter(String filter) {
    emit(state.copyWith(selectedFilter: filter));
    _executeSearch(state.query);
  }

  void onQueryChanged(String query) {
    emit(state.copyWith(query: query));
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 250), () {
      _executeSearch(query);
    });
  }

  void _executeSearch(String query) {
    _searchSub?.cancel();
    if (query.trim().isEmpty) {
      emit(state.copyWith(results: [], isLoading: false));
      return;
    }

    emit(state.copyWith(isLoading: true));
    _searchSub = _searchUseCase.searchSongs(query).listen((allResults) {
      final q = query.toLowerCase();
      final filtered = allResults.where((song) {
        if (state.selectedFilter == 'Songs') return song.title.toLowerCase().contains(q);
        if (state.selectedFilter == 'Artists') return song.artist.toLowerCase().contains(q);
        if (state.selectedFilter == 'Albums') return song.album.toLowerCase().contains(q);
        return song.title.toLowerCase().contains(q) ||
            song.artist.toLowerCase().contains(q) ||
            song.album.toLowerCase().contains(q);
      }).toList();

      emit(state.copyWith(results: filtered, isLoading: false));
    });
  }

  void clearQuery() {
    emit(state.copyWith(query: '', results: [], isLoading: false));
  }

  @override
  Future<void> close() {
    _debounceTimer?.cancel();
    _searchSub?.cancel();
    return super.close();
  }
}
