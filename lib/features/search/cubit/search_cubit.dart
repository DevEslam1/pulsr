import 'package:mutex/mutex.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/bloc/base_cubit.dart';
import '../../../core/di/injection.dart';
import '../../../core/errors/failures.dart';
import '../../../core/utils/error_logger.dart';
import '../../../core/utils/search_algorithm_utils.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/repositories/music_repository_interface.dart';
import '../../../domain/usecases/folder_usecases.dart';
import '../../../domain/usecases/search_music_usecase.dart';
import 'search_state.dart';

import '../../../core/errors/app_error.dart';

@injectable
class SearchCubit extends PulsrCubit<SearchState> {
  final SearchMusicUseCase _searchUseCase;
  final FolderUseCases _folderUseCases;
  final IMusicRepository? _musicRepository;
  StreamSubscription? _searchSub;
  StreamSubscription? _excludedSub;
  Timer? _debounceTimer;
  final Mutex _historyMutex = Mutex();

  IMusicRepository? get _repo {
    if (_musicRepository != null) return _musicRepository;
    try {
      return getIt.isRegistered<IMusicRepository>()
          ? getIt<IMusicRepository>()
          : null;
    } catch (_) {
      return null;
    }
  }

  SearchCubit({
    required SearchMusicUseCase searchUseCase,
    required FolderUseCases folderUseCases,
    IMusicRepository? musicRepository,
  })  : _searchUseCase = searchUseCase,
        _folderUseCases = folderUseCases,
        _musicRepository = musicRepository,
        super(const SearchState()) {
    historyReady = _loadHistoryAsync();
    _loadFilter();
    savedSearchesReady = _loadSavedSearches();
    searchPlayedSongsReady = _loadSearchPlayedSongs();
    _watchExcludedFoldersForPlayed();
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

  static const String _searchPlayedSongsKey = 'search_played_songs';
  static const int searchPlayedSongsMax = 10;

  /// Reactive list of songs played from the search screen, kept outside the
  /// freezed state so no code generation is required.
  final ValueNotifier<List<SongsTableData>> searchPlayedSongs =
      ValueNotifier<List<SongsTableData>>(const []);
  late final Future<void> searchPlayedSongsReady;

  /// Direct repository artist/album search matches, kept outside freezed state
  /// so results are not capped at the 500-song FTS window.
  final ValueNotifier<List<ArtistsTableData>> artistResults =
      ValueNotifier<List<ArtistsTableData>>(const []);
  final ValueNotifier<List<AlbumsTableData>> albumResults =
      ValueNotifier<List<AlbumsTableData>>(const []);

  final List<int> _searchPlayedIds = <int>[];
  final Map<int, SongsTableData> _playedSongCache = <int, SongsTableData>{};

  /// True while the latest query has not been executed yet (debounce window).
  /// The UI uses this to keep the skeleton up instead of flashing "no results".
  bool get isDebouncing => _debounceTimer?.isActive ?? false;

  /// True when more matches exist beyond the results currently emitted.
  final ValueNotifier<bool> hasMoreResults = ValueNotifier<bool>(false);

  // ── Pipeline bookkeeping ────────────────────────────────────────────
  /// Bumped for every new query/filter/clear. Invalidates in-flight work.
  int _generation = 0;

  /// Current fuzzy cap for this query; raised by [showMoreResults].
  int _resultLimit = SearchAlgorithmUtils.maxResultCount;

  /// Source pool of the last emission, retained so "show more" can re-filter
  /// with a higher cap without another network/DB round-trip.
  List<SongsTableData>? _lastPool;
  String? _lastPoolFilter;

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
        safeEmit(state.copyWith(
            history: List<String>.unmodifiable(merged.take(historyMax))));
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

  void _watchExcludedFoldersForPlayed() {
    final repo = _repo;
    if (repo == null) return;
    try {
      _excludedSub = autoSub(repo.watchExcludedFolders(), (_) {
        invalidateExcludedFoldersCache();
        unawaited(reconcileSearchPlayedSongs());
        if (state.query.trim().isNotEmpty) {
          _executeSearch(state.query);
        }
      });
    } catch (_) {
      // Optional in unit tests whose mock repository leaves watchExcludedFolders unstubbed.
    }
  }

  static String _normDirPath(String path) =>
      path.replaceAll('\\', '/').toLowerCase().trim();

  static bool _isSongInExcludedFolders(
    SongsTableData song,
    List<String> excludedFolders,
  ) {
    if (excludedFolders.isEmpty) return false;
    final normSong = _normDirPath(song.path);
    for (final raw in excludedFolders) {
      var folder = _normDirPath(raw);
      if (folder.isEmpty) continue;
      if (!folder.endsWith('/')) folder = '$folder/';
      if (normSong.startsWith(folder)) return true;
    }
    return false;
  }

  Future<void> _loadSearchPlayedSongs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list =
          prefs.getStringList(_searchPlayedSongsKey) ?? const <String>[];
      _searchPlayedIds.clear();
      var hadLegacyEntries = false;
      for (final item in list) {
        final parsedId = int.tryParse(item.trim());
        if (parsedId != null) {
          if (!_searchPlayedIds.contains(parsedId)) {
            _searchPlayedIds.add(parsedId);
          }
          continue;
        }
        try {
          final decoded = jsonDecode(item);
          if (decoded is Map<String, dynamic>) {
            final song = SongsTableData.fromJson(decoded);
            if (!_searchPlayedIds.contains(song.id)) {
              _searchPlayedIds.add(song.id);
            }
            _playedSongCache[song.id] = song;
            hadLegacyEntries = true;
          }
        } catch (_) {}
      }
      if (hadLegacyEntries && !isClosed) {
        unawaited(_persistSearchPlayedIds());
      }
      await reconcileSearchPlayedSongs();
    } catch (e, st) {
      ErrorLogger.log('Failed to load search played songs',
          error: e, stackTrace: st, category: 'SearchCubit');
    }
  }

  Future<void> reconcileSearchPlayedSongs() async {
    if (isClosed) return;
    if (_searchPlayedIds.isEmpty) {
      if (searchPlayedSongs.value.isNotEmpty) {
        searchPlayedSongs.value = const [];
      }
      return;
    }
    final excluded = await _excludedFolders();
    if (isClosed) return;

    final repo = _repo;
    if (repo != null) {
      try {
        final res = await repo.getSongsByIds(List<int>.from(_searchPlayedIds));
        if (isClosed) return;
        res.fold((_) {}, (rows) {
          final byId = <int, SongsTableData>{
            for (final r in rows) r.id: r,
          };
          var prunedDeleted = false;
          _searchPlayedIds.removeWhere((id) {
            final row = byId[id];
            if (row == null || row.isMissing) {
              // Keep negative online sentinel IDs only if cached in memory;
              // drop missing or deleted local DB rows.
              if (id < 0 && _playedSongCache.containsKey(id)) {
                return false;
              }
              _playedSongCache.remove(id);
              prunedDeleted = true;
              return true;
            }
            _playedSongCache[id] = row;
            return false;
          });
          if (prunedDeleted) {
            unawaited(_persistSearchPlayedIds());
          }
        });
      } catch (_) {}
    }

    if (isClosed) return;
    final visible = <SongsTableData>[
      for (final id in _searchPlayedIds)
        if (_playedSongCache[id] != null &&
            !_playedSongCache[id]!.isMissing &&
            !_isSongInExcludedFolders(_playedSongCache[id]!, excluded))
          _playedSongCache[id]!,
    ];
    searchPlayedSongs.value = List.unmodifiable(visible);
  }

  Future<void> _persistSearchPlayedIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final idStrings =
          _searchPlayedIds.map((id) => id.toString()).toList(growable: false);
      await prefs.setStringList(_searchPlayedSongsKey, idStrings);
    } catch (e, st) {
      ErrorLogger.log('Failed to persist search played songs',
          error: e, stackTrace: st, category: 'SearchCubit');
    }
  }

  // ── Public API: query / filter ──────────────────────────────────────
  void clearError() {
    safeEmit(state.copyWith(error: null));
  }

  void setFilter(String filter) {
    if (filter == state.selectedFilter) return;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _resetResultWindow();
    safeEmit(state.copyWith(selectedFilter: filter));
    unawaited(_persistFilter(filter));
    _executeSearch(state.query, filterOverride: filter);
  }

  void _resetResultWindow() {
    _resultLimit = SearchAlgorithmUtils.maxResultCount;
    _lastPool = null;
    _lastPoolFilter = null;
    if (hasMoreResults.value) hasMoreResults.value = false;
  }

  /// [immediate] skips the debounce (chip taps, suggestions, deep links).
  /// An empty query always clears at once instead of waiting for the debounce
  /// (previously stale results lingered for 300 ms after deleting the text).
  void onQueryChanged(String query, {bool immediate = false}) {
    _generation++;
    _resetResultWindow();
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
    invalidateExcludedFoldersCache();
    await reconcileSearchPlayedSongs();
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
    _resetResultWindow();
    if (artistResults.value.isNotEmpty) artistResults.value = const [];
    if (albumResults.value.isNotEmpty) albumResults.value = const [];
    safeEmit(
        state.copyWith(query: '', results: [], isLoading: false, error: null));
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

  // ── Search-played songs ─────────────────────────────────────────────
  Future<void> recordPlayedSong(SongsTableData song) async {
    await searchPlayedSongsReady;
    if (isClosed) return;
    _searchPlayedIds.remove(song.id);
    _searchPlayedIds.insert(0, song.id);
    if (_searchPlayedIds.length > searchPlayedSongsMax) {
      _searchPlayedIds.removeRange(
          searchPlayedSongsMax, _searchPlayedIds.length);
    }
    _playedSongCache[song.id] = song;
    final current = searchPlayedSongs.value;
    final updated = [
      song,
      ...current.where((s) => s.id != song.id),
    ].take(searchPlayedSongsMax).toList();
    searchPlayedSongs.value = List.unmodifiable(updated);
    await _persistSearchPlayedIds();
  }

  Future<void> removeSearchPlayedSong(int songId) async {
    await searchPlayedSongsReady;
    if (isClosed) return;
    _searchPlayedIds.remove(songId);
    _playedSongCache.remove(songId);
    final updated = searchPlayedSongs.value
        .where((s) => s.id != songId)
        .toList(growable: false);
    searchPlayedSongs.value = List.unmodifiable(updated);
    await _persistSearchPlayedIds();
  }

  Future<void> clearSearchPlayedSongs() async {
    await searchPlayedSongsReady;
    if (isClosed) return;
    _searchPlayedIds.clear();
    _playedSongCache.clear();
    searchPlayedSongs.value = const [];
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_searchPlayedSongsKey);
    } catch (e, st) {
      ErrorLogger.log('Failed to clear search played songs',
          error: e, stackTrace: st, category: 'SearchCubit');
    }
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
    await _historyMutex.protect(() async {
      if (isClosed) return;
      try {
        final prefs = await SharedPreferences.getInstance();
        if (isClosed) return;
        final existing = prefs.getStringList(_historyKey) ??
            List<String>.from(state.history);
        final updated = [
          q,
          ...existing.where((h) => h.toLowerCase() != q.toLowerCase())
        ].take(historyMax).toList();
        await prefs.setStringList(_historyKey, updated);
        if (!isClosed) {
          safeEmit(state.copyWith(history: List<String>.unmodifiable(updated)));
        }
      } catch (e, st) {
        ErrorLogger.log('Failed to persist search history',
            error: e, stackTrace: st, category: 'SearchCubit');
      }
    });
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
    if (!isClosed) safeEmit(state.copyWith(history: const []));
  }

  /// Removes a single recent-search entry (case-insensitive).
  Future<void> removeHistoryQuery(String query) async {
    await historyReady;
    final updated = state.history
        .where((h) => h.toLowerCase() != query.trim().toLowerCase())
        .toList();
    if (!isClosed) {
      safeEmit(state.copyWith(history: List<String>.unmodifiable(updated)));
    }
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
  void invalidateExcludedFoldersCache() {
    _cachedExcludedFolders = null;
    _lastExcludedFetch = null;
  }

  Future<List<String>> _excludedFolders({bool forceRefresh = false}) async {
    final cached = _cachedExcludedFolders;
    final fetched = _lastExcludedFetch;
    if (!forceRefresh &&
        cached != null &&
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
      if (artistResults.value.isNotEmpty) artistResults.value = const [];
      if (albumResults.value.isNotEmpty) albumResults.value = const [];
      safeEmit(state.copyWith(results: [], isLoading: false, error: null));
      return;
    }

    final boundedQuery = trimmed.length > maxQueryLength
        ? trimmed.substring(0, maxQueryLength)
        : trimmed;

    safeEmit(state.copyWith(isLoading: true, error: null));
    unawaited(_searchDirectEntities(normalize(boundedQuery), generation));

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
            (failure) async =>
                safeEmit(state.copyWith(isLoading: false, error: failure)),
            (allResults) async {
              final q = normalize(boundedQuery);
              final filter = filterOverride ?? state.selectedFilter;
              var pool = allResults;
              var filtered = await _filterWithFuzzy(pool, q, filter);

              if (pool.isEmpty && boundedQuery.length >= 2) {
                try {
                  pool = await _fallbackFuzzyPool(
                    boundedQuery,
                    q,
                    excluded: excluded,
                  );
                  if (stale()) return;
                  filtered = await _filterWithFuzzy(pool, q, filter);
                } catch (e, st) {
                  ErrorLogger.log('Fuzzy fallback search failed',
                      error: e, stackTrace: st, category: 'SearchCubit');
                }
              }

              if (stale()) return;
              _lastPool = pool;
              _lastPoolFilter = filter;
              _updateHasMore(filtered, pool);
              safeEmit(state.copyWith(
                  results: List<SongsTableData>.unmodifiable(filtered),
                  isLoading: false,
                  error: null));
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

  static List<String> _fuzzyAnchorsFor(String normalizedQuery) {
    final tokens = normalizedQuery
        .split(RegExp(r'\s+'))
        .where((t) => t.length >= 2)
        .toList();
    final anchors = <String>[];
    void addAnchor(String s) {
      if (s.length >= 2 && !anchors.contains(s) && anchors.length < 4) {
        anchors.add(s);
      }
    }

    for (final token in tokens) {
      addAnchor(token.substring(0, 2));
      if (token.length >= 3) {
        addAnchor(token.substring(1, 3));
        addAnchor(token.substring(token.length - 2));
      }
      if (anchors.length >= 4) break;
    }
    return anchors;
  }

  Future<List<SongsTableData>> _fallbackFuzzyPool(
    String boundedQuery,
    String normalizedQ, {
    required List<String> excluded,
  }) async {
    final repo = _repo;
    if (repo != null) {
      try {
        final libRes = await repo
            .getAllSongs(excludedFolders: excluded, limit: 2000)
            .timeout(const Duration(seconds: 3));
        final libSongs = libRes.fold((_) => <SongsTableData>[], (r) => r);
        if (libSongs.isNotEmpty) {
          return libSongs;
        }
      } catch (_) {}
    }

    final anchors = _fuzzyAnchorsFor(normalizedQ);
    if (anchors.isEmpty ||
        (anchors.length == 1 && anchors.first == normalizedQ)) {
      return const [];
    }
    final merged = <int, SongsTableData>{};
    await Future.wait(anchors.map((anchor) async {
      try {
        final res = await _searchUseCase
            .searchSongs(anchor, excludedFolders: excluded, limit: _searchLimit)
            .first
            .timeout(const Duration(seconds: 2));
        res.fold((_) {}, (list) {
          for (final song in list) {
            merged.putIfAbsent(song.id, () => song);
          }
        });
      } catch (_) {}
    }));
    return merged.values.take(_searchLimit).toList();
  }

  Future<void> _searchDirectEntities(String q, int generation) async {
    final repo = _repo;
    if (repo == null || q.isEmpty) {
      if (!_isStale(generation)) {
        if (artistResults.value.isNotEmpty) artistResults.value = const [];
        if (albumResults.value.isNotEmpty) albumResults.value = const [];
      }
      return;
    }
    try {
      final results = await Future.wait([
        repo.getArtists(),
        repo.getAlbums(),
      ]);
      if (_isStale(generation)) return;

      final artists = (results[0] as Result<List<ArtistsTableData>>)
          .fold((_) => const <ArtistsTableData>[], (r) => r);
      final albums = (results[1] as Result<List<AlbumsTableData>>)
          .fold((_) => const <AlbumsTableData>[], (r) => r);

      int matchRank(String primary, [String secondary = '']) {
        final p = normalize(primary);
        if (p == q) return 0;
        if (p.startsWith(q)) return 1;
        if (p.contains(q)) return 2;
        if (secondary.isNotEmpty && normalize(secondary).contains(q)) return 3;
        if (q.length >= 3) {
          final maxDist = q.length <= 4 ? 1 : 2;
          for (final word in p.split(RegExp(r'\s+'))) {
            if (word.isEmpty) continue;
            if ((word.length - q.length).abs() <= maxDist &&
                SearchAlgorithmUtils.levenshtein(word, q) <= maxDist) {
              return 4;
            }
          }
        }
        return -1;
      }

      final scoredArtists = <(int, ArtistsTableData)>[];
      for (final a in artists) {
        final r = matchRank(a.name);
        if (r >= 0) scoredArtists.add((r, a));
      }
      scoredArtists.sort((a, b) {
        final c = a.$1.compareTo(b.$1);
        return c != 0 ? c : a.$2.name.compareTo(b.$2.name);
      });

      final scoredAlbums = <(int, AlbumsTableData)>[];
      for (final al in albums) {
        final r = matchRank(al.title, al.artist);
        if (r >= 0) scoredAlbums.add((r, al));
      }
      scoredAlbums.sort((a, b) {
        final c = a.$1.compareTo(b.$1);
        return c != 0 ? c : a.$2.title.compareTo(b.$2.title);
      });

      if (_isStale(generation)) return;
      artistResults.value = List.unmodifiable(
        scoredArtists.take(20).map((e) => e.$2),
      );
      albumResults.value = List.unmodifiable(
        scoredAlbums.take(20).map((e) => e.$2),
      );
    } catch (_) {}
  }

  void _failSearch(int generation, Object error, StackTrace stackTrace) {
    if (_isStale(generation)) return;
    addError(error, stackTrace);
    final message = error is AppFailure ? error.message : 'Search failed';
    safeEmit(state.copyWith(isLoading: false, error: uiError(message)));
  }

  /// Backwards-compatible delegate; the implementation lives in
  /// [SearchAlgorithmUtils] so it can be tested without a Cubit.
  static String normalize(String s) => SearchAlgorithmUtils.normalize(s);

  static const Set<String> _extraLosslessCodecs = {
    'flac',
    'wav',
    'wave',
    'alac',
    'aiff',
    'aif',
    'aifc',
    'dsd',
    'dsf',
    'dff',
    'ape',
    'wv',
    'tta',
    'tak',
    'mlp',
    'pcm',
  };

  static bool _isExtraLossless(SongsTableData song) {
    final codec = (song.codec ?? '').trim().toLowerCase();
    if (codec.isNotEmpty) {
      return _extraLosslessCodecs.contains(codec) || codec.startsWith('pcm');
    }
    final path = song.path.toLowerCase();
    final dot = path.lastIndexOf('.');
    if (dot == -1 || dot == path.length - 1) return false;
    return _extraLosslessCodecs.contains(path.substring(dot + 1));
  }

  Future<List<SongsTableData>> _filterWithFuzzy(
      List<SongsTableData> songs, String rawQ, String filter) {
    // Levenshtein ranking is CPU-bound; keep small result sets inline and
    // move the large ones off the UI isolate. `SongsTableData` and the query
    // arguments are plain values, so the closure is sendable — capture the
    // limit locally so the closure does not reference `this`.
    final effectiveSongs =
        filter == 'Lossless' ? songs.where(_isExtraLossless).toList() : songs;
    final effectiveFilter = filter == 'Lossless' ? 'All' : filter;
    final limit = _resultLimit;
    if (effectiveSongs.length < 250) {
      return Future.value(SearchAlgorithmUtils.filterWithFuzzy(
          effectiveSongs, rawQ, effectiveFilter,
          maxResults: limit));
    }
    return Isolate.run(() => SearchAlgorithmUtils.filterWithFuzzy(
        effectiveSongs, rawQ, effectiveFilter,
        maxResults: limit));
  }

  void _updateHasMore(
      List<SongsTableData> filtered, List<SongsTableData> pool) {
    final more =
        filtered.length >= _resultLimit && pool.length > filtered.length;
    if (hasMoreResults.value != more) hasMoreResults.value = more;
  }

  /// Raises the fuzzy cap by [SearchAlgorithmUtils.maxResultCount] and
  /// re-filters the cached pool, so a capped result set is never silently
  /// truncated.
  Future<void> showMoreResults() async {
    final pool = _lastPool;
    if (isClosed || pool == null || !hasMoreResults.value) return;
    final generation = _generation;
    final raised = _resultLimit + SearchAlgorithmUtils.maxResultCount;
    _resultLimit = raised > _searchLimit ? _searchLimit : raised;
    final trimmed = state.query.trim();
    final bounded = trimmed.length > maxQueryLength
        ? trimmed.substring(0, maxQueryLength)
        : trimmed;
    final q = normalize(bounded);
    final filtered = await _filterWithFuzzy(
        pool, q, _lastPoolFilter ?? state.selectedFilter);
    if (isClosed || generation != _generation) return;
    _updateHasMore(filtered, pool);
    safeEmit(
        state.copyWith(results: List<SongsTableData>.unmodifiable(filtered)));
  }

  @override
  Future<void> close() async {
    _debounceTimer?.cancel();
    _searchSub?.cancel();
    _excludedSub?.cancel();
    await super.close();
    savedSearches.value = const [];
    savedSearches.dispose();
    searchPlayedSongs.value = const [];
    searchPlayedSongs.dispose();
    artistResults.value = const [];
    artistResults.dispose();
    albumResults.value = const [];
    albumResults.dispose();
    hasMoreResults.dispose();
  }
}
