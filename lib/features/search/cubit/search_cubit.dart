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
  List<String>? _cachedExcludedFolders;
  DateTime? _lastExcludedFetch;

  Future<void> _executeSearch(String query, {String? filterOverride}) async {
    final generation = ++_generation;
    _searchSub?.cancel();
    _searchSub = null;
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      emit(state.copyWith(results: [], isLoading: false, errorMessage: null));
      return;
    }

    // Limit search query to 64 chars to avoid CPU starvation on huge pastes
    final boundedQuery =
        trimmed.length > 64 ? trimmed.substring(0, 64) : trimmed;

    emit(state.copyWith(isLoading: true));

    // Cache excluded folders for 5 seconds to reduce DB round-trips while typing
    final now = DateTime.now();
    if (_cachedExcludedFolders == null ||
        _lastExcludedFetch == null ||
        now.difference(_lastExcludedFetch!).inSeconds > 5) {
      final excludedRes = await _folderUseCases.getExcludedFolders();
      if (generation != _generation || isClosed) return;
      _cachedExcludedFolders = excludedRes.fold((l) => <String>[], (r) => r);
      _lastExcludedFetch = now;
    }

    final excluded = _cachedExcludedFolders ?? const <String>[];

    _searchSub = _searchUseCase
        .searchSongs(boundedQuery, excludedFolders: excluded)
        .listen((result) {
      if (generation != _generation || isClosed) return;
      result.fold(
        (failure) => emit(
            state.copyWith(isLoading: false, errorMessage: failure.message)),
        (allResults) {
          final q = normalize(query);
          final filter = filterOverride ?? state.selectedFilter;
          final filtered = _filterWithFuzzy(allResults, q, filter);

          emit(state.copyWith(
              results: filtered, isLoading: false, errorMessage: null));
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
        .replaceAll(RegExp(r'[أإآٱ]'), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll('ؤ', 'و')
        .replaceAll('ئ', 'ي')
        .replaceAll('ـ', ''); // Strip Tatweel
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

  static final Expando<({String title, String artist, String album})>
      _normCache = Expando();

  List<SongsTableData> _filterWithFuzzy(
      List<SongsTableData> songs, String rawQ, String filter) {
    final q = rawQ.length > 20 ? rawQ.substring(0, 20) : rawQ;
    final results = <SongsTableData>[];

    for (final song in songs) {
      if (results.length >= 100) break;

      final norm = _normCache[song] ??= (
        title: normalize(song.title),
        artist: normalize(song.artist),
        album: normalize(song.album),
      );
      final title = norm.title;
      final artist = norm.artist;
      final album = norm.album;

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
    if (a.length > 200 || b.length > 200) return 999;
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final lenDiff = (a.length - b.length).abs();
    if (lenDiff > 2) return lenDiff;

    // Use 2-row buffer O(min(N, M)) memory instead of full (N+1)*(M+1) matrix
    var s1 = a;
    var s2 = b;
    if (s1.length < s2.length) {
      final temp = s1;
      s1 = s2;
      s2 = temp;
    }

    var prevRow = List<int>.generate(s2.length + 1, (i) => i);
    var currRow = List<int>.filled(s2.length + 1, 0);

    for (var i = 1; i <= s1.length; i++) {
      currRow[0] = i;
      for (var j = 1; j <= s2.length; j++) {
        final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
        currRow[j] = math.min(
          prevRow[j] + 1,
          math.min(
            currRow[j - 1] + 1,
            prevRow[j - 1] + cost,
          ),
        );
      }
      final temp = prevRow;
      prevRow = currRow;
      currRow = temp;
    }
    return prevRow[s2.length];
  }

  void clearQuery() {
    _generation++;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _searchSub?.cancel();
    _searchSub = null;
    emit(state.copyWith(
        query: '', results: [], isLoading: false, errorMessage: null));
  }

  @override
  Future<void> close() {
    _debounceTimer?.cancel();
    _searchSub?.cancel();
    return super.close();
  }
}
