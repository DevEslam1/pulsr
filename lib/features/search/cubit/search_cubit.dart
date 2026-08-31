import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:injectable/injectable.dart';
import '../../../core/bloc/base_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/errors/failures.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/usecases/folder_usecases.dart';
import '../../../domain/usecases/search_music_usecase.dart';
import 'search_state.dart';

@injectable
class SearchCubit extends PulsrCubit<SearchState> {
  final SearchMusicUseCase _searchUseCase;
  final FolderUseCases _folderUseCases;
  StreamSubscription<void>? _searchSub;
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
      if (!isClosed) emit(state.copyWith(history: list));
    } catch (_) {}
  }

  void _loadHistory() { unawaited(_loadHistoryAsync()); }

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
    _debounceTimer = autoTimer(Timer(const Duration(milliseconds: 300), () {
      _executeSearch(query);
    }));
  }

  static String _sanitizeQuery(String query) {
    return query.replaceAll(RegExp(r'[\x00-\x1F\x7F%_\\]'), '').trim();
  }

  int _generation = 0;
  List<String>? _cachedExcludedFolders;
  DateTime? _lastExcludedFetch;
  static const int _historyMax = 10;
  static const String _historyKey = 'search_history';

  Future<void> _persistHistory(String query) async {
    final q = _sanitizeQuery(query);
    if (q.isEmpty || q.length < 2) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getStringList(_historyKey) ?? List.from(state.history);
      final updated = [q, ...existing.where((h) => h.toLowerCase() != q.toLowerCase())].take(_historyMax).toList();
      await prefs.setStringList(_historyKey, updated);
    } catch (_) {}
  }

  void clearHistory() async {
    try { final p = await SharedPreferences.getInstance(); await p.remove(_historyKey); } catch (_) {}
    if (!isClosed) emit(state.copyWith(history: []));
  }

  void useHistoryQuery(String q) => onQueryChanged(q);

  Future<void> _executeSearch(String query, {String? filterOverride}) async {
    final generation = ++_generation;
    unawaited(_searchSub?.cancel());
    _searchSub = null;
    final sanitized = _sanitizeQuery(query);
    if (sanitized.isEmpty) {
      emit(state.copyWith(results: [], isLoading: false, errorMessage: null));
      return;
    }

    // Limit search query to 64 chars to avoid CPU starvation on huge pastes
    final boundedQuery =
        sanitized.length > 64 ? sanitized.substring(0, 64) : sanitized;

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

    _searchSub = autoSub<Result<List<SongsTableData>>>(_searchUseCase
        .searchSongs(boundedQuery, excludedFolders: excluded), (result) {
      if (generation != _generation || isClosed) return;
      result.fold(
        (failure) => emit(
            state.copyWith(isLoading: false, errorMessage: failure.message)),
        (allResults) => unawaited(_applyResults(
            allResults, query, filterOverride, boundedQuery, generation)),
      );
    });
  }

  /// Applies the raw search results: runs the fuzzy filter (on a background
  /// isolate for large libraries, F-15) and emits the final state.
  Future<void> _applyResults(List<SongsTableData> allResults, String query,
      String? filterOverride, String boundedQuery, int generation) async {
    final q = normalize(query);
    final filter = filterOverride ?? state.selectedFilter;
    List<SongsTableData> filtered;
    if (allResults.length > _isolateSongThreshold) {
      try {
        filtered = await _filterWithFuzzyIsolated(allResults, q, filter);
      } catch (_) {
        // Defensive fallback: never leave the search spinner stuck if the
        // background isolate could not run.
        filtered = _filterWithFuzzy(allResults, q, filter);
      }
    } else {
      filtered = _filterWithFuzzy(allResults, q, filter);
    }
    // A newer search (or close) may have superseded this one while the
    // background filter was running.
    if (generation != _generation || isClosed) return;

    emit(state.copyWith(
        results: filtered, isLoading: false, errorMessage: null));
    if (filtered.isNotEmpty) unawaited(_persistHistory(boundedQuery));
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

  // LRU bounded cache to prevent unbounded 10k retention (was Expando leak)
  // Instance field (not static) to avoid cross-instance leak and ensure proper dispose per Cubit
  final LinkedHashMap<int, ({String title, String artist, String album})> _normCache = LinkedHashMap();
  static const int _normCacheMax = 1000;

  /// Libraries larger than this run the fuzzy filter on a background isolate
  /// (F-15) instead of the UI isolate. Small libraries keep the synchronous
  /// path to avoid the isolate spawn overhead.
  static const int _isolateSongThreshold = 500;

  /// Fuzzy filter executed on a background isolate (F-15) for libraries above
  /// [_isolateSongThreshold]. Only plain data crosses the isolate boundary:
  /// songs are mapped to positional records and matched indices are mapped
  /// back to the original [songs] list, preserving order. Newly computed
  /// normalizations are merged back into [_normCache] (same eviction rule as
  /// the synchronous path) so the LRU cache keeps working across keystrokes.
  Future<List<SongsTableData>> _filterWithFuzzyIsolated(
      List<SongsTableData> songs, String rawQ, String filter) async {
    final cachedNorms =
        Map<int, ({String title, String artist, String album})>.from(_normCache);
    final payload = <(int, int, String, String, String)>[
      for (var i = 0; i < songs.length; i++)
        (i, songs[i].id, songs[i].title, songs[i].artist, songs[i].album),
    ];
    final out = await Isolate.run(
        () => _fuzzyFilterWorker(payload, cachedNorms, rawQ, filter));

    out.newNorms.forEach((id, norm) {
      if (_normCache.length >= _normCacheMax) {
        _normCache.remove(_normCache.keys.first);
      }
      _normCache[id] = norm;
    });
    return [for (final i in out.matchedIndices) songs[i]];
  }

  /// Pure worker for [_filterWithFuzzyIsolated]. Static and touch-only
  /// sendable plain data. Matching logic, 100-result cap and result ordering
  /// are identical to [_filterWithFuzzy].
  static ({
    List<int> matchedIndices,
    Map<int, ({String title, String artist, String album})> newNorms,
  }) _fuzzyFilterWorker(
    List<(int, int, String, String, String)> songs,
    Map<int, ({String title, String artist, String album})> cachedNorms,
    String rawQ,
    String filter,
  ) {
    final q = rawQ.length > 20 ? rawQ.substring(0, 20) : rawQ;
    final matchedIndices = <int>[];
    final newNorms = <int, ({String title, String artist, String album})>{};

    for (final (index, id, rawTitle, rawArtist, rawAlbum) in songs) {
      if (matchedIndices.length >= 100) break;

      var norm = cachedNorms[id];
      if (norm == null) {
        norm = (
          title: normalize(rawTitle),
          artist: normalize(rawArtist),
          album: normalize(rawAlbum),
        );
        newNorms[id] = norm;
      }
      final title = norm.title;
      final artist = norm.artist;
      final album = norm.album;

      bool matchesField(String text) {
        final cleanText = text.replaceAll(RegExp(r"[^\w\s]"), "");
        final cleanQ = q.replaceAll(RegExp(r"[^\w\s]"), "");
        if (cleanText.contains(cleanQ)) return true;
        // Skip Levenshtein distance check for queries < 3 chars
        if (cleanQ.length < 3) return false;
        if (_levenshtein(cleanText, cleanQ) <= 2) return true;
        // Word-level fuzzy match (punctuation stripped before split)
        for (final word in cleanText.split(RegExp(r'\s+'))) {
          if (word.length >= 3 && _levenshtein(word, cleanQ) <= 2) return true;
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
        matchedIndices.add(index);
      }
    }
    return (matchedIndices: matchedIndices, newNorms: newNorms);
  }

  List<SongsTableData> _filterWithFuzzy(
      List<SongsTableData> songs, String rawQ, String filter) {
    final q = rawQ.length > 20 ? rawQ.substring(0, 20) : rawQ;
    final results = <SongsTableData>[];

    for (final song in songs) {
      if (results.length >= 100) break;

      var norm = _normCache[song.id];
      if (norm == null) {
        norm = (title: normalize(song.title), artist: normalize(song.artist), album: normalize(song.album));
        if (_normCache.length >= _normCacheMax) _normCache.remove(_normCache.keys.first);
        _normCache[song.id] = norm;
      } else {
        // Refresh LRU
        _normCache.remove(song.id);
        _normCache[song.id] = norm;
      }
      final title = norm.title;
      final artist = norm.artist;
      final album = norm.album;

      bool matchesField(String text) {
        final cleanText = text.replaceAll(RegExp(r"[^\w\s]"), "");
        final cleanQ = q.replaceAll(RegExp(r"[^\w\s]"), "");
        if (cleanText.contains(cleanQ)) return true;
        // Skip Levenshtein distance check for queries < 3 chars
        if (cleanQ.length < 3) return false;
        if (_levenshtein(cleanText, cleanQ) <= 2) return true;
        // Word-level fuzzy match (punctuation stripped before split)
        for (final word in cleanText.split(RegExp(r'\s+'))) {
          if (word.length >= 3 && _levenshtein(word, cleanQ) <= 2) return true;
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
    a = a.replaceAll(RegExp(r"[^\w\s]"), "");
    b = b.replaceAll(RegExp(r"[^\w\s]"), "");
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

  // Debounce timer + search subscription are registered with PulsrCubit and
  // cancelled automatically in close().
}
