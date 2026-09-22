import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/bloc/base_cubit.dart';
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
    _debounceTimer = autoTimer(Timer(const Duration(milliseconds: 300), () {
      _executeSearch(query);
    }));
  }

  int _generation = 0;
  List<String>? _cachedExcludedFolders;
  DateTime? _lastExcludedFetch;

  // FIX-L07: Expose historyMax for testing
  @visibleForTesting
  static const int historyMax = 10;

  /// Single bound applied to the query at every stage of the pipeline.
  /// The FTS query and the fuzzy post-filter MUST use the same length: if the
  /// post-filter tests a prefix of the real needle it admits false positives
  /// (defect 08-02).
  static const int maxQueryLength = 64;

  /// Maximum number of matches handed to the UI. Must stay >= the repository
  /// FTS window (music_repository.dart passes 'limit ?? 200'), so the
  /// presentation layer never truncates what the data layer was willing to
  /// return (defect 08-01).
  static const int maxResultCount = 200;
  static const String _historyKey = 'search_history';

  Future<void> _persistHistory(String query) async {
    final q = query.trim();
    if (q.isEmpty || q.length < 2) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getStringList(_historyKey) ?? List.from(state.history);
      final updated = [q, ...existing.where((h) => h.toLowerCase() != q.toLowerCase())].take(historyMax).toList();
      await prefs.setStringList(_historyKey, updated);
      if (!isClosed) safeEmit(state.copyWith(history: updated));
    } catch (_) {}
  }

  Future<void> clearHistory() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_historyKey);
    } catch (_) {}
    if (!isClosed) safeEmit(state.copyWith(history: []));
  }

  /// Removes a single recent-search entry (case-insensitive).
  Future<void> removeHistoryQuery(String query) async {
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
        trimmed.length > maxQueryLength ? trimmed.substring(0, maxQueryLength) : trimmed;

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

      // FIX-H4: Explicit limit 500 to prevent unbounded query load
      _searchSub = autoSub(
        _searchUseCase.searchSongs(boundedQuery, excludedFolders: excluded, limit: 500),
        (result) async {
          if (generation != _generation || isClosed) return;
          await result.fold(
            (failure) async => safeEmit(state.copyWith(
                isLoading: false, errorMessage: failure.message)),
            (allResults) async {
              // B-15: Ensure fuzzy post-filter uses normalize(boundedQuery) to match FTS bounded query
              final q = normalize(boundedQuery);
              final filter = filterOverride ?? state.selectedFilter;
              var filtered = _filterWithFuzzy(allResults, q, filter);

              if (filtered.isEmpty && boundedQuery.length >= 2) {
                // FIX-M03: Query by 2-character prefix instead of querying the entire database,
                // and cap candidate results at 500 to avoid UI/memory starvation.
                try {
                  final prefixRes = await _searchUseCase
                      .searchSongs(boundedQuery.substring(0, 2), excludedFolders: excluded, limit: 500)
                      .first;
                  if (generation != _generation || isClosed) return;
                  var candidates =
                      prefixRes.fold((l) => <SongsTableData>[], (r) => r);
                  if (candidates.length > 500) {
                    ErrorLogger.log(
                      'Fuzzy fallback candidate pool capped at 500 (was ${candidates.length})',
                      category: 'SearchCubit',
                    );
                    candidates = candidates.take(500).toList();
                  }
                  filtered = _filterWithFuzzy(candidates, q, filter);
                } catch (e, st) {
                  ErrorLogger.log(
                    'Fuzzy fallback search failed',
                    error: e,
                    stackTrace: st,
                    category: 'SearchCubit',
                  );
                }
              }

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

  // FIX-D02: Guard stale searches before addError to avoid firing BlocObserver on aborted queries
  void _failSearch(int generation, Object error, StackTrace stackTrace) {
    if (generation != _generation || isClosed) return;
    addError(error, stackTrace);
    safeEmit(state.copyWith(isLoading: false, errorMessage: 'Search failed'));
  }

  /// Backwards-compatible delegate; the implementation lives in
  /// [SearchAlgorithmUtils] so it can be tested without a Cubit.
  static String normalize(String s) => SearchAlgorithmUtils.normalize(s);

  List<SongsTableData> _filterWithFuzzy(
          List<SongsTableData> songs, String rawQ, String filter) =>
      SearchAlgorithmUtils.filterWithFuzzy(songs, rawQ, filter);

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
