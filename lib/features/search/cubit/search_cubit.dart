import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../../domain/usecases/folder_usecases.dart';
import '../../../domain/usecases/search_music_usecase.dart';
import 'search_state.dart';

@injectable
class SearchCubit extends Cubit<SearchState> {
  final SearchMusicUseCase _searchUseCase;
  final FolderUseCases _folderUseCases;
  StreamSubscription? _searchSub;
  Timer? _debounceTimer;

  SearchCubit({
    required SearchMusicUseCase searchUseCase,
    required FolderUseCases folderUseCases,
  })  : _searchUseCase = searchUseCase,
        _folderUseCases = folderUseCases,
        super(const SearchState());

  void clearError() {
    emit(state.copyWith(errorMessage: null));
  }

  void setFilter(String filter) {
    emit(state.copyWith(selectedFilter: filter));
    _executeSearch(state.query, filterOverride: filter);
  }

  void onQueryChanged(String query) {
    emit(state.copyWith(query: query));
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 250), () {
      _executeSearch(query);
    });
  }

  int _generation = 0;

  Future<void> _executeSearch(String query, {String? filterOverride}) async {
    final generation = ++_generation;
    _searchSub?.cancel();
    if (query.trim().isEmpty) {
      emit(state.copyWith(results: [], isLoading: false, errorMessage: null));
      return;
    }

    emit(state.copyWith(isLoading: true));
    final excludedRes = await _folderUseCases.getExcludedFolders();
    if (generation != _generation || isClosed) return;
    final excluded = excludedRes.fold((l) => <String>[], (r) => r);

    _searchSub = _searchUseCase.searchSongs(query, excludedFolders: excluded).listen((result) {
      if (generation != _generation || isClosed) return;
      result.fold(
        (failure) => emit(state.copyWith(isLoading: false, errorMessage: failure.message)),
        (allResults) {
          final q = query.toLowerCase();
          final filter = filterOverride ?? state.selectedFilter;
          final filtered = allResults.where((song) {
            if (filter == 'Songs') return song.title.toLowerCase().contains(q);
            if (filter == 'Artists') return song.artist.toLowerCase().contains(q);
            if (filter == 'Albums') return song.album.toLowerCase().contains(q);
            return song.title.toLowerCase().contains(q) ||
                song.artist.toLowerCase().contains(q) ||
                song.album.toLowerCase().contains(q);
          }).toList();

          emit(state.copyWith(results: filtered, isLoading: false, errorMessage: null));
        },
      );
    });
  }

  void clearQuery() {
    emit(state.copyWith(query: '', results: [], isLoading: false, errorMessage: null));
  }

  @override
  Future<void> close() {
    _debounceTimer?.cancel();
    _searchSub?.cancel();
    return super.close();
  }
}
