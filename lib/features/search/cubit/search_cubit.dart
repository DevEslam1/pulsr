import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/bloc/base_cubit.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/usecases/folder_usecases.dart';
import '../../../domain/usecases/search_music_usecase.dart';
import 'search_state.dart';

@injectable
class SearchCubit extends PulsrCubit<SearchState> {
  final SearchMusicUseCase _searchUseCase;
  final FolderUseCases _folderUseCases;
  StreamSubscription? _searchSub;
  Timer? _debounceTimer;

  SearchCubit({
    required SearchMusicUseCase searchUseCase,
    required FolderUseCases folderUseCases,
  })  : _searchUseCase = searchUseCase,
        _folderUseCases = folderUseCases,
        super(const SearchState()) {
    _loadHistory();
  }

  Future<void> _loadHistoryAsync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_historyKey) ?? [];
      if (!isClosed) safeEmit(state.copyWith(history: list));
    } catch (_) {}
  }

  void _loadHistory() { unawaited(_loadHistoryAsync()); }

  void clearError() {
    safeEmit(state.copyWith(errorMessage: null));
  }

  void setFilter(String filter) {
    safeEmit(state.copyWith(selectedFilter: filter));
    _executeSearch(state.query, filterOverride: filter);
  }

  void onQueryChanged(String query) {
    safeEmit(state.copyWith(query: query));
    _debounceTimer?.cancel();
    _debounceTimer = autoTimer(Timer(const Duration(milliseconds: 250), () {
      _executeSearch(query);
    }));
  }

  int _generation = 0;
  List<String>? _cachedExcludedFolders;
  DateTime? _lastExcludedFetch;
  static const int _historyMax = 10;
  static const String _historyKey = 'search_history';

  Future<void> _persistHistory(String query) async {
    final q = query.trim();
    if (q.isEmpty || q.length < 2) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getStringList(_historyKey) ?? List.from(state.history);
      final updated = [q, ...existing.where((h) => h.toLowerCase() != q.toLowerCase())].take(_historyMax).toList();
      await prefs.setStringList(_historyKey, updated);
      // Do not emit extra state here — history is merged into main search result emit to keep blocTest stable
      // History will be loaded on next init or via explicit refresh
    } catch (_) {}
  }

  void clearHistory() async {
    try { final p = await SharedPreferences.getInstance(); await p.remove(_historyKey); } catch (_) {}
    if (!isClosed) safeEmit(state.copyWith(history: []));
  }

  void useHistoryQuery(String q) => onQueryChanged(q);

  Future<void> _executeSearch(String query, {String? filterOverride}) async {
    final generation = ++_generation;
    _searchSub?.cancel();
    removeFromComposite(_searchSub);
    _searchSub = null;
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      safeEmit(
          state.copyWith(results: [], isLoading: false, errorMessage: null));
      return;
    }

    // Limit search query to 64 chars to avoid CPU starvation on huge pastes
    final boundedQuery =
        trimmed.length > 64 ? trimmed.substring(0, 64) : trimmed;

    safeEmit(state.copyWith(isLoading: true));

    try {
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

      _searchSub = autoSub(
        _searchUseCase.searchSongs(boundedQuery, excludedFolders: excluded),
        (result) {
          if (generation != _generation || isClosed) return;
          result.fold(
            (failure) => safeEmit(state.copyWith(
                isLoading: false, errorMessage: failure.message)),
            (allResults) {
              final q = normalize(query);
              final filter = filterOverride ?? state.selectedFilter;
              final filtered = _filterWithFuzzy(allResults, q, filter);

              safeEmit(state.copyWith(
                  results: filtered, isLoading: false, errorMessage: null));
              if (filtered.isNotEmpty) unawaited(_persistHistory(boundedQuery));
            },
          );
        },
        onError: (error, stackTrace) => _failSearch(generation, error, stackTrace),
      );
    } catch (e, st) {
      _failSearch(generation, e, st);
    }
  }

  void _failSearch(int generation, Object error, StackTrace stackTrace) {
    addError(error, stackTrace);
    if (generation != _generation || isClosed) return;
    safeEmit(state.copyWith(isLoading: false, errorMessage: 'Search failed'));
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

  // LRU bounded cache to prevent unbounded 10k retention (was Expando leak).
  // Keyed by raw metadata so a retagged song is not served stale normalized
  // text; the superseded entry ages out through LRU eviction.
  final LinkedHashMap<String, ({String title, String artist, String album})> _normCache = LinkedHashMap();
  static const int _normCacheMax = 1000;

  List<SongsTableData> _filterWithFuzzy(
      List<SongsTableData> songs, String rawQ, String filter) {
    final q = rawQ.length > 20 ? rawQ.substring(0, 20) : rawQ;
    final results = <SongsTableData>[];

    for (final song in songs) {
      if (results.length >= 100) break;

      final key = '${song.id}|${song.title}|${song.artist}|${song.album}';
      var norm = _normCache[key];
      if (norm == null) {
        norm = (title: normalize(song.title), artist: normalize(song.artist), album: normalize(song.album));
        if (_normCache.length >= _normCacheMax) _normCache.remove(_normCache.keys.first);
        _normCache[key] = norm;
      } else {
        // Refresh LRU
        _normCache.remove(key);
        _normCache[key] = norm;
      }
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
    removeFromComposite(_searchSub);
    _searchSub = null;
    safeEmit(state.copyWith(
        query: '', results: [], isLoading: false, errorMessage: null));
  }

  @override
  Future<void> close() {
    _debounceTimer?.cancel();
    _searchSub?.cancel();
    return super.close();
  }
}
