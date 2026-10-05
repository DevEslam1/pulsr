import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/bloc/base_cubit.dart';
import '../../../core/errors/failures.dart';
import '../../../core/utils/error_logger.dart';
import '../../../core/utils/search_algorithm_utils.dart';
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
    historyReady = _loadHistoryAsync();
    _loadFilter();
    savedSearchesReady = _loadSavedSearches();
  }

  late final Future<void> historyReady;
  bool _historyLoaded = false;
  @visibleForTesting
  bool get isHistoryLoaded => _historyLoaded;

  // ── Constants ───────────────────────────────────────────────────────
  @visibleForTesting
  static const int historyMax = 10;

  /// Single bound applied to the query at every stage of the pipeline
  /// (FTS query, fuzzy post-filter and suggestions).
  static const int maxQueryLength = 64;

  /// NOTE: currently not applied anywhere. The FTS window is [_searchLimit].
  static const int maxResultCount = 200;

  /// Explicit limit so a one-letter query can't load the whole library.
  static const int _searchLimit = 500;

  static const Duration _debounce = Duration(milliseconds: 300);
  static const String _historyKey = 'search_history';
  static const String _filterKey = 'search_selected_filter';
  static const List<String> filterOptions = [
    'All',
    'Songs',
    'Artists',
    'Albums',
    'FLAC',
    'MP3',
    'Lossless',
  ];
  static const String _savedSearchesKey = 'saved_searches';
  static const int savedSearchMax = 10;
  static const int suggestionMax = 5;

  /// Reactive list of saved searches (query + filter), kept outside the
  /// freezed state so no code generation is required.
  final ValueNotifier<List<String>> savedSearches =
      ValueNotifier<List<String>>(const []);
  late final Future<void> savedSearchesReady;

  // ── Pipeline bookkeeping ────────────────────────────────────────────
  /// Bumped for every new query/filter/clear. Invalidates in-flight work.
  int _generation = 0;

  /// Bumped for every emission of the DB stream. A slow emission (fuzzy
  /// fallback awaits a second query) must not overwrite a newer one.
  int _emission = 0;

  List<String>? _cachedExcludedFolders;
  DateTime? _lastExcludedFetch;

  bool _isStale(int generation) => generation != _generation || isClosed;

  void _cancelSearch() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _searchSub?.cancel();
    removeFromComposite(_searchSub);
    _searchSub = null;
  }

  // ── Loading / persistence ───────────────────────────────────────────
  Future<void> _loadHistoryAsync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_historyKey) ?? [];
      if (!isClosed) {
        _historyLoaded = true;
        final merged = <String>[...state.history];
        for (final item in list) {
          if (!merged.any((m) => m.toLowerCase() == item.toLowerCase())) {
            merged.add(item);
          }
        }
        safeEmit(state.copyWith(history: merged.take(historyMax).toList()));
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to load search history',
          error: e, stackTrace: st, category: 'SearchCubit');
    }
  }

  Future<void> _loadFilter() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_filterKey);
      if (stored != null && filterOptions.contains(stored) && !isClosed) {
        safeEmit(state.copyWith(selectedFilter: stored));
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to load search filter',
          error: e, stackTrace: st, category: 'SearchCubit');
    }
  }

  Future<void> _persistFilter(String filter) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_filterKey, filter);
    } catch (e, st) {
      ErrorLogger.log('Failed to persist search filter',
          error: e, stackTrace: st, category: 'SearchCubit');
    }
  }

  Future<void> _loadSavedSearches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_savedSearchesKey) ?? const <String>[];
      if (!isClosed) savedSearches.value = List.unmodifiable(list);
    } catch (e, st) {
      ErrorLogger.log('Failed to load saved searches',
          error: e, stackTrace: st, category: 'SearchCubit');
    }
  }

  // ── Public API: query / filter ──────────────────────────────────────
  void clearError() {
    safeEmit(state.copyWith(errorMessage: null));
  }

  void setFilter(String filter) {
    if (filter == state.selectedFilter) return;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    safeEmit(state.copyWith(selectedFilter: filter));
    unawaited(_persistFilter(filter));
    _executeSearch(state.query, filterOverride: filter);
  }

  /// [immediate] skips the debounce (chip taps, suggestions, deep links).
  /// An empty query always clears at once instead of waiting for the debounce
  /// (previously stale results lingered for 300 ms after deleting the text).
  void onQueryChanged(String query, {bool immediate = false}) {
    _generation++;
    _cancelSearch();
    safeEmit(state.copyWith(query: query));
    if (immediate || query.trim().isEmpty) {
      _executeSearch(query);
      return;
    }
    _debounceTimer = autoTimer(Timer(_debounce, () => _executeSearch(query)));
  }

  /// Applies a saved search atomically: filter and query are set together, so
  /// the old query is never searched with the new filter.
  void applySavedSearch(String query, String filter) {
    final f = filterOptions.contains(filter) ? filter : 'All';
    if (f != state.selectedFilter) {
      safeEmit(state.copyWith(selectedFilter: f));
      unawaited(_persistFilter(f));
    }
    onQueryChanged(query, immediate: true);
  }

  void useHistoryQuery(String q) => onQueryChanged(q, immediate: true);

  /// Re-runs the current query right away (retry buttons).
  void retry() => _executeSearch(state.query);

  /// Pull-to-refresh: re-runs the query and completes when it has settled, so
  /// the RefreshIndicator spinner reflects real work.
  Future<void> refresh() async {
    if (state.query.trim().isEmpty) return;
    unawaited(_executeSearch(state.query));
    try {
      await stream
          .firstWhere((s) => !s.isLoading)
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Timeout / closed: the indicator just stops.
    }
  }

  void clearQuery() {
    _generation++;
    _cancelSearch();
    safeEmit(state.copyWith(
        query: '', results: [], isLoading: false, errorMessage: null));
  }

  // ── Saved searches ──────────────────────────────────────────────────
  bool isSaved(String query, String filter) =>
      savedSearches.value.contains(encodeSavedSearch(query.trim(), filter));

  /// Saves the current query + filter (deduped, capped at [savedSearchMax]).
  Future<void> saveCurrentSearch() async {
    await savedSearchesReady;
    if (isClosed) return;
    final query = state.query.trim();
    if (query.isEmpty) return;
    final entry = encodeSavedSearch(query, state.selectedFilter);
    final updated = <String>[
      entry,
      ...savedSearches.value.where((e) => e != entry),
    ].take(savedSearchMax).toList();
    savedSearches.value = List.unmodifiable(updated);
    await _persistSavedSearches(updated);
  }

  Future<void> removeSavedSearch(String entry) async {
    await savedSearchesReady;
    if (isClosed) return;
    final updated =
        savedSearches.value.where((e) => e != entry).toList(growable: false);
    savedSearches.value = List.unmodifiable(updated);
    await _persistSavedSearches(updated);
  }

  Future<void> _persistSavedSearches(List<String> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_savedSearchesKey, list);
    } catch (e, st) {
      ErrorLogger.log('Failed to persist saved searches',
          error: e, stackTrace: st, category: 'SearchCubit');
    }
  }

  /// Encodes a saved search as JSON so queries containing separators round-trip.
  static String encodeSavedSearch(String query, String filter) =>
      jsonEncode({'q': query, 'f': filter});

  /// Decodes a saved search entry. Malformed entries degrade to a plain query.
  static ({String query, String filter}) decodeSavedSearch(String entry) {
    try {
      final decoded = jsonDecode(entry);
      if (decoded is Map) {
        final q = (decoded['q'] as String?)?.trim() ?? '';
        final f = (decoded['f'] as String?) ?? 'All';
        if (q.isNotEmpty) {
          return (query: q, filter: filterOptions.contains(f) ? f : 'All');
        }
      }
    } catch (_) {
      // Legacy/plain-text entry.
    }
    return (query: entry, filter: 'All');
  }

  // ── Autocomplete ────────────────────────────────────────────────────
  /// Up to [suggestionMax] suggestions from history and library title/artist
  /// prefixes. Respects excluded folders and the shared query bound.
  Future<List<String>> suggestionsFor(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final bounded = trimmed.length > maxQueryLength
        ? trimmed.substring(0, maxQueryLength)
        : trimmed;
    final q = normalize(bounded);
    final seen = <String>{};
    final out = <String>[];

    void add(String value) {
      final v = value.trim();
      if (v.isEmpty || out.length >= suggestionMax) return;
      if (seen.add(v.toLowerCase())) out.add(v);
    }

    for (final h in state.history) {
      if (out.length >= suggestionMax) break;
      if (normalize(h).startsWith(q)) add(h);
    }

    if (out.length < suggestionMax) {
      try {
        // BUG FIX: suggestions used to ignore excluded folders and could leak
        // songs the user had hidden.
        final excluded = await _excludedFolders();
        final res = await _searchUseCase
            .searchSongs(bounded, excludedFolders: excluded, limit: 20)
            .first
            .timeout(const Duration(seconds: 2));
        final songs = res.fold((_) => <SongsTableData>[], (r) => r);
        for (final s in songs) {
          if (out.length >= suggestionMax) break;
          if (normalize(s.title).startsWith(q)) add(s.title);
        }
        for (final s in songs) {
          if (out.length >= suggestionMax) break;
          if (normalize(s.artist).startsWith(q)) add(s.artist);
        }
      } catch (e, st) {
        ErrorLogger.log('Search suggestions failed',
            error: e, stackTrace: st, category: 'SearchCubit');
      }
    }
    return out;
  }

  // ── History ─────────────────────────────────────────────────────────
  /// Records a search the user actually committed to (submit, tapped result,
  /// tapped suggestion/recent). BUG FIX: history used to be written
  /// automatically after any pause while typing, so it filled up with
  /// fragments like "bea", "beat", "beatl".
  Future<void> commitQuery([String? query]) async {
    final raw = (query ?? state.query).trim();
    if (raw.length < 2) return;
    final q =
        raw.length > maxQueryLength ? raw.substring(0, maxQueryLength) : raw;
    await historyReady;
    if (isClosed) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (isClosed) return;
      final existing =
          prefs.getStringList(_historyKey) ?? List<String>.from(state.history);
      final updated = [
        q,
        ...existing.where((h) => h.toLowerCase() != q.toLowerCase())
      ].take(historyMax).toList();
      await prefs.setStringList(_historyKey, updated);
      if (!isClosed) safeEmit(state.copyWith(history: updated));
    } catch (e, st) {
      ErrorLogger.log('Failed to persist search history',
          error: e, stackTrace: st, category: 'SearchCubit');
    }
  }

  Future<void> clearHistory() async {
    await historyReady;
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_historyKey);
    } catch (e, st) {
      ErrorLogger.log('Failed to clear search history',
          error: e, stackTrace: st, category: 'SearchCubit');
    }
    if (!isClosed) safeEmit(state.copyWith(history: []));
  }

  /// Removes a single recent-search entry (case-insensitive).
  Future<void> removeHistoryQuery(String query) async {
    await historyReady;
    final updated = state.history
        .where((h) => h.toLowerCase() != query.trim().toLowerCase())
        .toList();
    if (!isClosed) safeEmit(state.copyWith(history: updated));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_historyKey, updated);
    } catch (e, st) {
      ErrorLogger.log('Failed to remove search history entry',
          error: e, stackTrace: st, category: 'SearchCubit');
    }
  }

  // ── Search pipeline ─────────────────────────────────────────────────
  /// Excluded folders, cached for 5 s while typing. BUG FIX: a failed lookup
  /// used to be cached as "no exclusions" for 5 s, briefly showing hidden
  /// songs. Failures now fall back to the last known list and aren't cached.
  Future<List<String>> _excludedFolders() async {
    final cached = _cachedExcludedFolders;
    final fetched = _lastExcludedFetch;
    if (cached != null &&
        fetched != null &&
        DateTime.now().difference(fetched).inSeconds <= 5) {
      return cached;
    }
    final res = await _folderUseCases.getExcludedFolders();
    return res.fold((_) => cached ?? const <String>[], (r) {
      _cachedExcludedFolders = r;
      _lastExcludedFetch = DateTime.now();
      return r;
    });
  }

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

    final boundedQuery = trimmed.length > maxQueryLength
        ? trimmed.substring(0, maxQueryLength)
        : trimmed;

    safeEmit(state.copyWith(isLoading: true, errorMessage: null));

    try {
      final excluded = await _excludedFolders();
      if (_isStale(generation)) return;

      _searchSub = autoSub(
        _searchUseCase.searchSongs(boundedQuery,
            excludedFolders: excluded, limit: _searchLimit),
        (result) async {
          final emission = ++_emission;
          bool stale() => _isStale(generation) || emission != _emission;
          if (stale()) return;

          await result.fold(
            (failure) async => safeEmit(state.copyWith(
                isLoading: false, errorMessage: failure.message)),
            (allResults) async {
              final q = normalize(boundedQuery);
              final filter = filterOverride ?? state.selectedFilter;
              var filtered = _filterWithFuzzy(allResults, q, filter);

              if (filtered.isEmpty && boundedQuery.length >= 2) {
                try {
                  final prefixRes = await _searchUseCase
                      .searchSongs(boundedQuery.substring(0, 2),
                          excludedFolders: excluded, limit: _searchLimit)
                      .first
                      .timeout(const Duration(seconds: 2));
                  // BUG FIX: re-check against the *emission*, not just the
                  // generation, so a slow fallback can't overwrite a newer
                  // emission of the same live stream.
                  if (stale()) return;
                  final candidates =
                      prefixRes.fold((l) => <SongsTableData>[], (r) => r);
                  filtered = _filterWithFuzzy(
                      candidates.take(_searchLimit).toList(), q, filter);
                } catch (e, st) {
                  ErrorLogger.log('Fuzzy fallback search failed',
                      error: e, stackTrace: st, category: 'SearchCubit');
                }
              }

              if (stale()) return;
              safeEmit(state.copyWith(
                  results: filtered, isLoading: false, errorMessage: null));
            },
          );
        },
        onError: (error, stackTrace) =>
            _failSearch(generation, error, stackTrace),
      );
    } catch (e, st) {
      _failSearch(generation, e, st);
    }
  }

  void _failSearch(int generation, Object error, StackTrace stackTrace) {
    if (_isStale(generation)) return;
    addError(error, stackTrace);
    final message = error is AppFailure ? error.message : 'Search failed';
    safeEmit(state.copyWith(isLoading: false, errorMessage: message));
  }

  /// Backwards-compatible delegate; the implementation lives in
  /// [SearchAlgorithmUtils] so it can be tested without a Cubit.
  static String normalize(String s) => SearchAlgorithmUtils.normalize(s);

  List<SongsTableData> _filterWithFuzzy(
          List<SongsTableData> songs, String rawQ, String filter) =>
      SearchAlgorithmUtils.filterWithFuzzy(songs, rawQ, filter);

  @override
  Future<void> close() async {
    _debounceTimer?.cancel();
    _searchSub?.cancel();
    await super.close();
    savedSearches.value = const [];
    savedSearches.dispose();
  }
}
