// lib/features/library/cubit/library_cubit.dart
import 'dart:async';
import '../../../core/bloc/base_cubit.dart';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/di/injection.dart';
import '../../../data/services/ytm_account_service.dart';
import '../../../core/errors/failures.dart';
import '../../../core/utils/error_logger.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/models/ytm_track.dart';
import '../../../domain/models/genre_item.dart';
import '../../../domain/models/year_item.dart';
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

  StreamSubscription<void>? _songsSub;
  StreamSubscription<void>? _albumsSub;
  StreamSubscription<void>? _artistsSub;
  StreamSubscription<void>? _genresSub;
  StreamSubscription<void>? _yearsSub;
  StreamSubscription<void>? _favoritesSub;
  bool _initialized = false;
  int? _lastEmittedSongCount;
  // FIX: generation guard — rapid updateSort() re-subscribes faster than
  // Drift cancel() completes; stale stream events must not overwrite the
  // newest sort. Each _subscribeSongs bumps _songsGen and captures it.
  int _songsGen = 0;

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
        super(const LibraryState()) {
    init();
  }

  Future<void> init() async {
    // Guard against repeated calls (e.g. from pull-to-refresh) re-reading prefs
    // and double-emitting state which causes library screen overlap.
    final firstRun = !_initialized;
    _initialized = true;

    if (firstRun) {
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
    }

    await _subscribeSongs();
    if (isClosed) return;
    _subscribeAlbums();
    _subscribeArtists();
    _subscribeGenres();
    _subscribeYears();
    _subscribeFavorites();
    unawaited(loadFolders());
  }

  /// Refreshes all data streams without re-reading stored preferences or
  /// emitting a preference-state update. Use this for pull-to-refresh to
  /// avoid the double-emit / overlap caused by calling init() again.
  Future<void> refresh() async {
    await _subscribeSongs();
    if (isClosed) return;
    _subscribeAlbums();
    _subscribeArtists();
    _subscribeGenres();
    _subscribeYears();
    _subscribeFavorites();
    unawaited(loadFolders());
  }

  void clearError() {
    safeEmit(state.copyWith(errorMessage: null));
  }

  Future<void> _subscribeSongs() async {
    final gen = ++_songsGen;
    final oldSub = _songsSub;
    _songsSub = null;
    removeFromComposite(oldSub);
    try {
      await oldSub?.cancel();
    } catch (e, st) {
      ErrorLogger.log('_subscribeSongs failed', error: e, stackTrace: st, category: 'LibraryCubit');
    }
    if (isClosed || gen != _songsGen) return;
    final excludedRes = await _folderUseCases.getExcludedFolders();
    if (isClosed || gen != _songsGen) return;
    final excluded = excludedRes.fold((l) => <String>[], (r) => r);
    // Capture sort at subscribe time so a mid-flight sort change can't mix
    // old stream + new sort label.
    final sortBy = state.sortBy;
    final ascending = state.ascending;
    _songsSub = autoSub<Result<List<SongsTableData>>>(
      _getSongsUseCase.watchSongs(
        sortBy: sortBy,
        ascending: ascending,
        excludedFolders: excluded,
      ),
      (result) {
      if (isClosed || gen != _songsGen) return;
      result.fold(
        (failure) {
          ErrorLogger.log(
              'LibraryCubit.watchSongs emitted failure',
              error: failure,
              category: 'LibraryCubit');
          safeEmit(state.copyWith(errorMessage: failure.message));
        },
        (songs) {
          // SCAN-DEBUG: first emission + size changes are the key evidence
          // for 'scan count > 0 but library UI empty' reports.
          if (_lastEmittedSongCount == null ||
              songs.length != _lastEmittedSongCount) {
            ErrorLogger.addBreadcrumb(
                'LibraryCubit.watchSongs emitted ${songs.length} songs (prev: $_lastEmittedSongCount)',
                category: 'LibraryCubit');
          }
          _lastEmittedSongCount = songs.length;
          safeEmit(state.copyWith(songs: songs, isLoading: false, errorMessage: null));
        },
      );
    });
  }

  void _subscribeAlbums() {
    _albumsSub?.cancel();
    removeFromComposite(_albumsSub);
    _albumsSub = autoSub<Result<List<AlbumsTableData>>>(_getAlbumsUseCase.watchAlbums(), (result) {
      if (isClosed) return;
      result.fold(
        (failure) => safeEmit(state.copyWith(errorMessage: failure.message)),
        (albums) => safeEmit(state.copyWith(albums: albums, errorMessage: null)),
      );
    });
  }

  void _subscribeArtists() {
    _artistsSub?.cancel();
    removeFromComposite(_artistsSub);
    _artistsSub = autoSub<Result<List<ArtistsTableData>>>(_getArtistsUseCase.watchArtists(), (result) {
      if (isClosed) return;
      result.fold(
        (failure) => safeEmit(state.copyWith(errorMessage: failure.message)),
        (artists) => safeEmit(state.copyWith(artists: artists, errorMessage: null)),
      );
    });
  }

  void _subscribeGenres() {
    _genresSub?.cancel();
    removeFromComposite(_genresSub);
    _genresSub = autoSub<Result<List<GenreItem>>>(_getGenresUseCase.watchGenres(), (result) {
      if (isClosed) return;
      result.fold(
        (failure) => safeEmit(state.copyWith(errorMessage: failure.message)),
        (genres) => safeEmit(state.copyWith(genres: genres, errorMessage: null)),
      );
    });
  }

  void _subscribeYears() {
    _yearsSub?.cancel();
    removeFromComposite(_yearsSub);
    _yearsSub = autoSub<Result<List<YearItem>>>(_getYearsUseCase.watchYears(), (result) {
      if (isClosed) return;
      result.fold(
        (failure) => safeEmit(state.copyWith(errorMessage: failure.message)),
        (years) => safeEmit(state.copyWith(years: years, errorMessage: null)),
      );
    });
  }

  void _subscribeFavorites() {
    _favoritesSub?.cancel();
    removeFromComposite(_favoritesSub);
    _favoritesSub = autoSub<Result<List<SongsTableData>>>(_getFavoritesUseCase.watchFavorites(), (result) {
      if (isClosed) return;
      result.fold(
        (failure) => safeEmit(state.copyWith(errorMessage: failure.message)),
        (favs) => safeEmit(state.copyWith(favorites: favs, errorMessage: null)),
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
    // FIX: debounce rapid sort toggles to avoid overlapping drift queries
    unawaited(_subscribeSongs());
    SharedPreferences.getInstance().then((prefs) async {
      try {
        await prefs.setString('library_sort_by', sortBy);
        await prefs.setBool('library_sort_ascending', ascending);
      } catch (e, st) { ErrorLogger.log('Failed to persist library sort', error: e, stackTrace: st, category: 'LibraryCubit'); }
    }).catchError((Object e, StackTrace st) { ErrorLogger.log('Failed to persist library sort', error: e, stackTrace: st, category: 'LibraryCubit'); });
  }

  void toggleViewMode() {
    final nextMode = state.viewMode == LibraryViewMode.list
        ? LibraryViewMode.grid
        : LibraryViewMode.list;
    safeEmit(state.copyWith(viewMode: nextMode));
    SharedPreferences.getInstance().then((prefs) async {
      try { await prefs.setString('library_view_mode', nextMode.name); } catch (e, st) { ErrorLogger.log('Failed to persist view mode', error: e, stackTrace: st, category: 'LibraryCubit'); }
    }).catchError((Object e, StackTrace st) { ErrorLogger.log('Failed to persist view mode', error: e, stackTrace: st, category: 'LibraryCubit'); });
  }

  int _favoriteOpGen = 0;
  Future<void> toggleFavorite(int songId) async {
    final opGen = ++_favoriteOpGen;
    final previousFavorites = List<SongsTableData>.from(state.favorites);
    final previousSongs = List<SongsTableData>.from(state.songs);
    final currentFavs = List<SongsTableData>.from(state.favorites);
    final isFav = currentFavs.any((s) => s.id == songId);
    if (isFav) {
      currentFavs.removeWhere((s) => s.id == songId);
      safeEmit(state.copyWith(favorites: currentFavs,
          songs: state.songs
              .map((s) => s.id == songId ? s.copyWith(isFavorite: false) : s)
              .toList()));
    } else {
      final matchingSong = state.songs.cast<SongsTableData?>().firstWhere(
            (s) => s?.id == songId,
            orElse: () => null,
          );
      if (matchingSong != null) {
        currentFavs.add(matchingSong.copyWith(isFavorite: true));
      }
      // FIX: patch songs[] too so hearts stay in sync until DB re-emits.
      safeEmit(state.copyWith(
          favorites: currentFavs,
          songs: state.songs
              .map((s) => s.id == songId ? s.copyWith(isFavorite: !isFav) : s)
              .toList()));
    }

    final result = await _toggleFavoriteUseCase(songId);
    if (isClosed || opGen != _favoriteOpGen) return;
    result.fold(
      (failure) => safeEmit(state.copyWith(
          favorites: previousFavorites,
          songs: previousSongs,
          errorMessage: failure.message)),
      (_) => null,
    );
  }

  Future<void> toggleFolderExclusion(String folderPath) async {
    final result = await _folderUseCases.toggleExcludeFolder(folderPath);
    if (isClosed) return;
    result.fold(
      (failure) => safeEmit(state.copyWith(errorMessage: failure.message)),
      (_) async {
        await loadFolders();
        if (isClosed) return;
        unawaited(_subscribeSongs());
      },
    );
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

  void selectAllSongs() {
    final allIds = state.songs.map((s) => s.id).toSet();
    safeEmit(state.copyWith(selectedSongIds: allIds, isMultiSelectMode: true));
  }

  void clearSelection() {
    safeEmit(state.copyWith(selectedSongIds: {}, isMultiSelectMode: false));
  }

  List<SongsTableData> getSelectedSongs() {
    return state.songs
        .where((s) => state.selectedSongIds.contains(s.id))
        .toList();
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
  Future<void> close() async {
    await _songsSub?.cancel();
    removeFromComposite(_songsSub);
    await _albumsSub?.cancel();
    removeFromComposite(_albumsSub);
    await _artistsSub?.cancel();
    removeFromComposite(_artistsSub);
    await _genresSub?.cancel();
    removeFromComposite(_genresSub);
    await _yearsSub?.cancel();
    removeFromComposite(_yearsSub);
    await _favoritesSub?.cancel();
    removeFromComposite(_favoritesSub);
    return super.close();
  }
}
