// lib/features/library/cubit/library_cubit.dart
import 'dart:async';
import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/bloc/base_cubit.dart';
import '../../../core/errors/failures.dart';
import '../../../core/di/injection.dart';
import '../../../core/services/ytm_account_service.dart';
import '../../../core/utils/error_logger.dart';
import '../../../data/audio/song_rating_store.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/models/ytm_track.dart';
import '../../../domain/repositories/music_repository_interface.dart';
import '../../../domain/usecases/get_songs_usecase.dart';
import '../../../domain/usecases/get_albums_usecase.dart';
import '../../../domain/usecases/get_artists_usecase.dart';
import '../../../domain/usecases/get_genres_usecase.dart';
import '../../../domain/usecases/get_years_usecase.dart';
import '../../../domain/usecases/get_favorites_usecase.dart';
import '../../../domain/usecases/toggle_favorite_usecase.dart';
import '../../../domain/usecases/folder_usecases.dart';
import 'library_state.dart';

@injectable
class LibraryCubit extends PulsrCubit<LibraryState> {
  final GetSongsUseCase _getSongsUseCase;
  final GetAlbumsUseCase _getAlbumsUseCase;
  final GetArtistsUseCase _getArtistsUseCase;
  final GetGenresUseCase _getGenresUseCase;
  final GetYearsUseCase _getYearsUseCase;
  final GetFavoritesUseCase _getFavoritesUseCase;
  final ToggleFavoriteUseCase _toggleFavoriteUseCase;
  final FolderUseCases _folderUseCases;
  final IMusicRepository? _musicRepository;

  StreamSubscription? _songsSub;
  StreamSubscription? _albumsSub;
  StreamSubscription? _artistsSub;
  StreamSubscription? _genresSub;
  StreamSubscription? _yearsSub;
  StreamSubscription? _favoritesSub;
  int _songsToken = 0;

  /// DB-level pagination window for the songs watch. The full 10k-row list
  /// is never held in state; [loadMoreSongs] grows the window by one page.
  static const int songsPageSize = 500;
  int _songsLimit = songsPageSize;
  bool _hasMoreSongs = false;
  bool _isLoadingMoreSongs = false;

  /// True when the last songs emission hit the current limit window, i.e.
  /// more rows may exist in the database.
  bool get hasMoreSongs => _hasMoreSongs;

  LibraryCubit({
    required GetSongsUseCase getSongsUseCase,
    required GetAlbumsUseCase getAlbumsUseCase,
    required GetArtistsUseCase getArtistsUseCase,
    required GetGenresUseCase getGenresUseCase,
    required GetYearsUseCase getYearsUseCase,
    required GetFavoritesUseCase getFavoritesUseCase,
    required ToggleFavoriteUseCase toggleFavoriteUseCase,
    required FolderUseCases folderUseCases,
    IMusicRepository? musicRepository,
  })  : _getSongsUseCase = getSongsUseCase,
        _getAlbumsUseCase = getAlbumsUseCase,
        _getArtistsUseCase = getArtistsUseCase,
        _getGenresUseCase = getGenresUseCase,
        _getYearsUseCase = getYearsUseCase,
        _getFavoritesUseCase = getFavoritesUseCase,
        _toggleFavoriteUseCase = toggleFavoriteUseCase,
        _folderUseCases = folderUseCases,
        _musicRepository = musicRepository ??
            (getIt.isRegistered<IMusicRepository>()
                ? getIt<IMusicRepository>()
                : null),
        super(const LibraryState(isLoading: true)) {
    init();
  }

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedSortBy = prefs.getString('library_sort_by') ?? 'title';
      final savedAscending = prefs.getBool('library_sort_ascending') ?? true;
      final savedViewMode = prefs.getString('library_view_mode') == 'grid'
          ? LibraryViewMode.grid
          : LibraryViewMode.list;

      if (!isClosed) {
        safeEmit(state.copyWith(
          sortBy: savedSortBy,
          ascending: savedAscending,
          viewMode: savedViewMode,
        ));
      }
    } catch (e, st) {
      ErrorLogger.log(
          'Failed to load library preferences from SharedPreferences',
          error: e,
          stackTrace: st,
          category: 'LibraryCubit');
    }

    await _subscribeSongs();
    if (isClosed) return;
    _subscribeAlbums();
    _subscribeArtists();
    _subscribeGenres();
    _subscribeYears();
    _subscribeFavorites();
    loadFolders();
  }

  void clearError() {
    safeEmit(state.copyWith(errorMessage: null));
  }

  Future<void> _subscribeSongs({bool resetLimit = false}) async {
    final t = ++_songsToken;
    _songsSub?.cancel();
    removeFromComposite(_songsSub);
    _songsSub = null;
    if (resetLimit) {
      _songsLimit = songsPageSize;
      _hasMoreSongs = false;
    }
    final excludedRes = await _folderUseCases.getExcludedFolders();
    if (isClosed || t != _songsToken) return;
    final excluded = excludedRes.fold((l) => <String>[], (r) => r);
      // Top-rated sort is prefs-backed: SQL has no rating column, so watch a
      // bounded window and sort in Dart. 5000 covers realistic libraries
      // without holding the full table; pagination is disabled in this mode
      // and the cap is documented on the sort control.
      final isRatingSort = state.sortBy == 'rating';
      const ratingSortCap = 5000;
      final window = isRatingSort ? ratingSortCap : _songsLimit;
    _songsSub = autoSub(
      _getSongsUseCase.watchSongs(
        sortBy: isRatingSort ? 'title' : state.sortBy,
        ascending: state.ascending,
        limit: window,
        excludedFolders: excluded,
      ),
      (result) {
        result.fold(
          (failure) {
            _isLoadingMoreSongs = false;
            safeEmit(state.copyWith(
                errorMessage: failure.message, isLoading: false));
          },
          (songs) {
            if (isRatingSort) {
              _hasMoreSongs = false;
              _isLoadingMoreSongs = false;
              safeEmit(state.copyWith(
                  songs: _sortByRating(songs, ascending: state.ascending),
                  errorMessage: null,
                  isLoading: false));
              return;
            }
              // Hitting the cap means the DB may hold more rows.
              _hasMoreSongs = !isRatingSort && songs.length >= window;
            _isLoadingMoreSongs = false;
            safeEmit(state.copyWith(
                songs: songs, errorMessage: null, isLoading: false));
          },
        );
      },
    );
  }

  /// Dart-side top-rated sort (ratings live in SharedPreferences).
  List<SongsTableData> _sortByRating(List<SongsTableData> songs,
      {bool ascending = false}) {
    int ratingOf(SongsTableData s) {
      try {
        // Ratings are keyed by song id string (see SongRatingStore).
        final store = getIt.isRegistered<SongRatingStore>()
            ? getIt<SongRatingStore>()
            : null;
        return store?.getRating(s.id.toString()) ?? 0;
      } catch (_) {
        return 0;
      }
    }

    final sorted = List<SongsTableData>.from(songs);
    sorted.sort((a, b) {
      final cmp = ratingOf(a).compareTo(ratingOf(b));
      if (cmp != 0) return ascending ? cmp : -cmp;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return sorted;
  }

  /// Grows the songs window by one page. Called from the songs list scroll
  /// listener; no-ops while a page load is in flight or the cap wasn't hit.
  void loadMoreSongs() {
    if (_isLoadingMoreSongs || !_hasMoreSongs || isClosed) return;
    _isLoadingMoreSongs = true;
    _songsLimit += songsPageSize;
    _subscribeSongs();
  }

  void _subscribeAlbums() {
    _albumsSub?.cancel();
    removeFromComposite(_albumsSub);
    _albumsSub = autoSub(_getAlbumsUseCase.watchAlbums(), (result) {
      result.fold(
        (failure) => safeEmit(state.copyWith(errorMessage: failure.message)),
        (albums) => safeEmit(state.copyWith(albums: albums, errorMessage: null)),
      );
    });
  }

  void _subscribeArtists() {
    _artistsSub?.cancel();
    removeFromComposite(_artistsSub);
    _artistsSub = autoSub(_getArtistsUseCase.watchArtists(), (result) {
      result.fold(
        (failure) => safeEmit(state.copyWith(errorMessage: failure.message)),
        (artists) => safeEmit(state.copyWith(artists: artists, errorMessage: null)),
      );
    });
  }

  void _subscribeGenres() {
    _genresSub?.cancel();
    removeFromComposite(_genresSub);
    _genresSub = autoSub(_getGenresUseCase.watchGenres(), (result) {
      result.fold(
        (failure) => safeEmit(state.copyWith(errorMessage: failure.message)),
        (genres) => safeEmit(state.copyWith(genres: genres, errorMessage: null)),
      );
    });
  }

  void _subscribeYears() {
    _yearsSub?.cancel();
    removeFromComposite(_yearsSub);
    _yearsSub = autoSub(_getYearsUseCase.watchYears(), (result) {
      result.fold(
        (failure) => safeEmit(state.copyWith(errorMessage: failure.message)),
        (years) => safeEmit(state.copyWith(years: years, errorMessage: null)),
      );
    });
  }

  void _subscribeFavorites() {
    _favoritesSub?.cancel();
    removeFromComposite(_favoritesSub);
    _favoritesSub = autoSub(_getFavoritesUseCase.watchFavorites(), (result) {
      result.fold(
        (failure) => safeEmit(state.copyWith(errorMessage: failure.message)),
        (favs) {
          if (_pendingFavoriteTargets.isEmpty) {
            safeEmit(state.copyWith(favorites: favs, errorMessage: null));
            return;
          }
          // A favorite toggle is in flight: the DB still holds the pre-toggle
          // truth and this emission would flip the row back until the write
          // settles. Hold the optimistic direction for the affected songs.
          var merged = favs;
          _pendingFavoriteTargets.forEach((songId, targetFav) {
            final has = merged.any((s) => s.id == songId);
            if (targetFav && !has) {
              SongsTableData? optimistic;
              for (final s in state.favorites) {
                if (s.id == songId) {
                  optimistic = s;
                  break;
                }
              }
              if (optimistic == null) {
                for (final s in state.songs) {
                  if (s.id == songId) {
                    optimistic = s;
                    break;
                  }
                }
              }
              if (optimistic != null) {
                merged = [...merged, optimistic.copyWith(isFavorite: true)];
              }
            } else if (!targetFav && has) {
              merged = merged.where((s) => s.id != songId).toList();
            }
          });
          safeEmit(state.copyWith(favorites: merged, errorMessage: null));
        },
      );
    });
  }

  Future<void> loadFolders() async {
    final result = await _folderUseCases.getFolderHierarchy();
    if (isClosed) return;
    result.fold(
      (failure) => safeEmit(state.copyWith(errorMessage: failure.message)),
      (folders) => safeEmit(state.copyWith(folders: folders, errorMessage: null)),
    );
  }

  void updateSort(String sortBy, bool ascending) {
    safeEmit(state.copyWith(sortBy: sortBy, ascending: ascending));
    _subscribeSongs(resetLimit: true);
    SharedPreferences.getInstance().then((prefs) async {
      try {
        await prefs.setString('library_sort_by', sortBy);
        await prefs.setBool('library_sort_ascending', ascending);
      } catch (e, st) { ErrorLogger.log('Failed to persist library sort', error: e, stackTrace: st, category: 'LibraryCubit'); }
    }).catchError((e, st) { ErrorLogger.log('Failed to persist library sort', error: e, stackTrace: st, category: 'LibraryCubit'); });
  }

  void toggleViewMode() {
    final nextMode = state.viewMode == LibraryViewMode.list
        ? LibraryViewMode.grid
        : LibraryViewMode.list;
    safeEmit(state.copyWith(viewMode: nextMode));
    SharedPreferences.getInstance().then((prefs) async {
      try { await prefs.setString('library_view_mode', nextMode.name); } catch (e, st) { ErrorLogger.log('Failed to persist view mode', error: e, stackTrace: st, category: 'LibraryCubit'); }
    }).catchError((e, st) { ErrorLogger.log('Failed to persist view mode', error: e, stackTrace: st, category: 'LibraryCubit'); });
  }

  final Map<int, int> _favoriteOpTokens = {};

  /// Optimistic favorite direction per song while a toggle use case is in
  /// flight (songId -> target isFavorite). Live favorites emissions are
  /// reconciled against it so the row does not flip back to the pre-toggle DB
  /// truth for the duration of the write.
  final Map<int, bool> _pendingFavoriteTargets = {};

  Future<void> toggleFavorite(int songId) async {
    final opToken = (_favoriteOpTokens[songId] ?? 0) + 1;
    _favoriteOpTokens[songId] = opToken;

    List<SongsTableData> songsWith(bool isFavorite) => state.songs
        .map((s) => s.id == songId ? s.copyWith(isFavorite: isFavorite) : s)
        .toList();

    // Keep the actual pre-toggle row: rollback must restore it even when the
    // song is not visible in the current (possibly filtered) songs list.
    SongsTableData? preToggleFav;
    for (final s in state.favorites) {
      if (s.id == songId) {
        preToggleFav = s;
        break;
      }
    }
    final wasFav = preToggleFav != null;

    if (wasFav) {
      _pendingFavoriteTargets[songId] = false;
      final favs = List<SongsTableData>.from(state.favorites)
        ..removeWhere((s) => s.id == songId);
      safeEmit(state.copyWith(favorites: favs, songs: songsWith(false)));
    } else {
      _pendingFavoriteTargets[songId] = true;
      var matchingSong = state.songs.cast<SongsTableData?>().firstWhere(
            (s) => s?.id == songId,
            orElse: () => null,
          );
      if (matchingSong == null && _musicRepository != null) {
        try {
          final res = await _musicRepository!.getSongsByIds([songId]);
          matchingSong = res.fold((_) => null, (list) => list.firstOrNull);
        } catch (e, st) {
          ErrorLogger.log('Favorite toggle: song lookup failed for $songId',
              error: e, stackTrace: st, category: 'LibraryCubit');
        }
        // The repository lookup awaited: the favorites watch-stream may have
        // emitted during the gap. Bail if closed or superseded instead of
        // clobbering that update with the stale pre-await snapshot.
        if (isClosed || _favoriteOpTokens[songId] != opToken) return;
      }
      if (matchingSong != null) {
        // Re-read favorites after any await so a watch emission that landed in
        // the gap is not overwritten by our optimistic emit.
        final favs = List<SongsTableData>.from(state.favorites);
        if (!favs.any((s) => s.id == songId)) {
          favs.add(matchingSong.copyWith(isFavorite: true));
        }
        safeEmit(state.copyWith(favorites: favs, songs: songsWith(true)));
      }
    }

    Result<bool> result;
    try {
      result = await _toggleFavoriteUseCase(songId);
    } catch (e, st) {
      // The use case normally returns Left; a raw throw must not leak the
      // in-flight bookkeeping or crash the awaiting UI.
      ErrorLogger.log('Favorite toggle failed for song $songId',
          error: e, stackTrace: st, category: 'LibraryCubit');
      result = Left(DatabaseFailure('Could not update favorite'));
    }
    if (isClosed || _favoriteOpTokens[songId] != opToken) return;
    _favoriteOpTokens.remove(songId);
    _pendingFavoriteTargets.remove(songId);
    final failureMessage = result.fold<String?>((l) => l.message, (_) => null);
    if (failureMessage == null) {
      safeEmit(state.copyWith(errorMessage: null));
      return;
    }
    // Rollback restores from the pre-toggle snapshot regardless of whether the
    // song exists in state.songs — the old code silently dropped favorites for
    // songs outside the visible (filtered) list until the next emission.
    final reconciled = List<SongsTableData>.from(state.favorites);
    if (wasFav) {
      if (!reconciled.any((s) => s.id == songId)) {
        reconciled.add(preToggleFav.copyWith(isFavorite: true));
      }
    } else {
      reconciled.removeWhere((s) => s.id == songId);
    }
    safeEmit(state.copyWith(
      favorites: reconciled,
      songs: songsWith(wasFav),
      errorMessage: failureMessage,
    ));
  }

  Future<void> toggleFolderExclusion(String folderPath) async {
    final result = await _folderUseCases.toggleExcludeFolder(folderPath);
    if (isClosed) return;
    final failureMessage = result.fold<String?>((l) => l.message, (_) => null);
    if (failureMessage != null) {
      safeEmit(state.copyWith(errorMessage: failureMessage));
      return;
    }
    await loadFolders();
    if (isClosed) return;
    await _subscribeSongs();
  }

  // Multi-select actions
  void toggleSongSelection(int songId) {
    final current = Set<int>.from(state.selectedSongIds);
    if (current.contains(songId)) {
      current.remove(songId);
    } else {
      current.add(songId);
    }
    safeEmit(state.copyWith(
      selectedSongIds: current,
      isMultiSelectMode: current.isNotEmpty,
    ));
  }

  /// Selects every song in the library. Bounded (gap 06-04): resolves IDs in a
  /// capped window (2000) so a 10k+ select-all stays instant and never
  /// materialises the whole library into memory at once.
  static const int selectAllCap = 2000;
  Future<void> selectAllSongs() async {
    if (!_hasMoreSongs) {
      final allIds = state.songs.map((s) => s.id).toSet();
      safeEmit(
          state.copyWith(selectedSongIds: allIds, isMultiSelectMode: true));
      return;
    }
    final repo = _musicRepository;
    if (repo == null) {
      final allIds = state.songs.map((s) => s.id).toSet();
      safeEmit(
          state.copyWith(selectedSongIds: allIds, isMultiSelectMode: true));
      return;
    }
    final excluded =
        (await _folderUseCases.getExcludedFolders()).fold((_) => <String>[], (r) => r);
    if (isClosed) return;
    final res = await repo
        .watchAllSongs(limit: selectAllCap, excludedFolders: excluded)
        .first;
    if (isClosed) return;
    res.fold(
      (failure) => safeEmit(state.copyWith(errorMessage: failure.message)),
      (songs) => safeEmit(state.copyWith(
          selectedSongIds: songs.map((s) => s.id).toSet(),
          isMultiSelectMode: true,
          errorMessage: songs.length >= selectAllCap
              ? 'Selected first $selectAllCap tracks (library exceeds cap)'
              : null)),
    );
  }

  void clearSelection() {
    safeEmit(state.copyWith(selectedSongIds: {}, isMultiSelectMode: false));
  }

  /// Resolves the selected songs, fetching any that are outside the currently
  /// loaded page from the repository so batch actions are not silently
  /// truncated to the visible window.
  Future<List<SongsTableData>> getSelectedSongs() async {
    final ids = state.selectedSongIds;
    if (ids.isEmpty) return const [];
    final loaded = <int, SongsTableData>{
      for (final s in state.songs) s.id: s,
    };
    final result = <SongsTableData>[];
    final missing = <int>[];
    for (final id in ids) {
      final s = loaded[id];
      if (s != null) {
        result.add(s);
      } else {
        missing.add(id);
      }
    }
    final repo = _musicRepository;
    if (missing.isNotEmpty && repo != null) {
      final res = await repo.getSongsByIds(missing);
      if (isClosed) return result;
      res.fold((_) {}, result.addAll);
    }
    return result;
  }

  /// Batch imports YouTube Music playlist tracks as Favorites.
  Future<int> importYtmTracksAsFavorites(List<YtmTrack> tracks) async {
    final repo = _musicRepository ??
        (getIt.isRegistered<IMusicRepository>()
            ? getIt<IMusicRepository>()
            : null);
    if (repo == null) return 0;
    final result = await repo.importOnlineTracksAsFavorites(tracks);
    return result.fold((failure) => 0, (count) => count);
  }

  /// Synchronizes private Liked Music from the authenticated YouTube Music web account.
  Future<int> syncYtmAccountLikes() async {
    try {
      final accountService = getIt<YtmAccountService>();
      if (!accountService.isLoggedIn) {
        safeEmit(state.copyWith(errorMessage: 'Not signed in to YouTube Music'));
        return 0;
      }
      final tracks = await accountService.fetchLikedSongs();
      final count = await importYtmTracksAsFavorites(tracks);
      return count;
    } catch (e, st) {
      ErrorLogger.log('Failed to sync YTM account likes',
          error: e, stackTrace: st, category: 'LibraryCubit');
      if (!isClosed) {
        safeEmit(
            state.copyWith(errorMessage: 'Failed to sync YouTube Music likes'));
      }
      return 0;
    }
  }

  @override
  Future<void> close() {
    _songsSub?.cancel();
    _albumsSub?.cancel();
    _artistsSub?.cancel();
    _genresSub?.cancel();
    _yearsSub?.cancel();
    _favoritesSub?.cancel();
    return super.close();
  }
}
