import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../../data/db/app_database.dart';
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
    _searchSub = null;
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
          final q = normalize(query);
          final filter = filterOverride ?? state.selectedFilter;
          final filtered = _filterWithFuzzy(allResults, q, filter);

          emit(state.copyWith(results: filtered, isLoading: false, errorMessage: null));
        },
      );
    });
  }

  /// Normalizes Unicode, Arabic diacritics / letter variants, and Latin accents for fuzzy search
  static String normalize(String s) {
    var str = s.toLowerCase();
    // 1. Strip Arabic Tashkeel / Harakat
    str = str.replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '');
    // 2. Normalize Arabic Alef variants & letters
    str = str
        .replaceAll(RegExp(r'[أإآ]'), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll('ؤ', 'و')
        .replaceAll('ئ', 'ي');
    // 3. Normalize common Latin accents
    str = str
        .replaceAll(RegExp(r'[àáâãäå]'), 'a')
        .replaceAll(RegExp(r'[èéêë]'), 'e')
        .replaceAll(RegExp(r'[ìíîï]'), 'i')
        .replaceAll(RegExp(r'[òóôõö]'), 'o')
        .replaceAll(RegExp(r'[ùúûü]'), 'u')
        .replaceAll(RegExp(r'[ýÿ]'), 'y')
        .replaceAll('ñ', 'n')
        .replaceAll('ç', 'c');
    return str.trim();
  }

  List<SongsTableData> _filterWithFuzzy(List<SongsTableData> songs, String rawQ, String filter) {
    final q = rawQ.length > 20 ? rawQ.substring(0, 20) : rawQ;
    final results = <SongsTableData>[];

    for (final song in songs) {
      if (results.length >= 100) break;

      final title = normalize(song.title);
      final artist = normalize(song.artist);
      final album = normalize(song.album);

      bool matchesField(String text) {
        if (text.contains(q)) return true;
        // Skip Levenshtein distance check for queries < 3 chars
        if (q.length < 3) return false;
        if (_levenshtein(text, q) <= 2) return true;
        // Word-level fuzzy match
        for (final word in text.split(RegExp(r'\s+'))) {
          if (word.length >= 3 && _levenshtein(word, q) <= 2) return true;
        }
        return false;
      }

      final matches = switch (filter) {
        'Songs' => matchesField(title),
        'Artists' => matchesField(artist),
        'Albums' => matchesField(album),
        _ => matchesField(title) || matchesField(artist) || matchesField(album),
      };

      if (matches) {
        results.add(song);
      }
    }
    return results;
  }

  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    if (a.length > 50 || b.length > 50) return 999;

    final matrix = List.generate(a.length + 1, (i) => List.filled(b.length + 1, 0));
    for (var i = 0; i <= a.length; i++) {
      matrix[i][0] = i;
    }
    for (var j = 0; j <= b.length; j++) {
      matrix[0][j] = j;
    }

    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        matrix[i][j] = math.min(
          matrix[i - 1][j] + 1,
          math.min(
            matrix[i][j - 1] + 1,
            matrix[i - 1][j - 1] + cost,
          ),
        );
      }
    }
    return matrix[a.length][b.length];
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
