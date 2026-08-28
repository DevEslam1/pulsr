// lib/features/library/cubit/library_cubit.dart
import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/di/injection.dart';
import '../../../core/services/ytm_account_service.dart';
import '../../../core/utils/error_logger.dart';
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
class LibraryCubit extends Cubit<LibraryState> {
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
  bool _initialized = false;

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
        // TODO(inject): getIt fallback violates DI purity — keep for backward compatibility but prefer injecting IMusicRepository via constructor in production
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
          emit(state.copyWith(
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
    loadFolders();
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
    loadFolders();
  }

  void clearError() {
    emit(state.copyWith(errorMessage: null));
  }

  Future<void> _subscribeSongs() async {
    _songsSub?.cancel();
    final excludedRes = await _folderUseCases.getExcludedFolders();
    if (isClosed) return;
    final excluded = excludedRes.fold((l) => <String>[], (r) => r);
    _songsSub = _getSongsUseCase
        .watchSongs(
      sortBy: state.sortBy,
      ascending: state.ascending,
      excludedFolders: excluded,
    )
        .listen((result) {
      if (isClosed) return;
      result.fold(
        (failure) => emit(state.copyWith(errorMessage: failure.message)),
        (songs) => emit(state.copyWith(songs: songs, errorMessage: null)),
      );
    });
  }

  void _subscribeAlbums() {
    _albumsSub?.cancel();
    _albumsSub = _getAlbumsUseCase.watchAlbums().listen((result) {
      if (isClosed) return;
      result.fold(
        (failure) => emit(state.copyWith(errorMessage: failure.message)),
        (albums) => emit(state.copyWith(albums: albums, errorMessage: null)),
      );
    });
  }

  void _subscribeArtists() {
    _artistsSub?.cancel();
    _artistsSub = _getArtistsUseCase.watchArtists().listen((result) {
      if (isClosed) return;
      result.fold(
        (failure) => emit(state.copyWith(errorMessage: failure.message)),
        (artists) => emit(state.copyWith(artists: artists, errorMessage: null)),
      );
    });
  }

  void _subscribeGenres() {
    _genresSub?.cancel();
    _genresSub = _getGenresUseCase.watchGenres().listen((result) {
      if (isClosed) return;
      result.fold(
        (failure) => emit(state.copyWith(errorMessage: failure.message)),
        (genres) => emit(state.copyWith(genres: genres, errorMessage: null)),
      );
    });
  }

  void _subscribeYears() {
    _yearsSub?.cancel();
    _yearsSub = _getYearsUseCase.watchYears().listen((result) {
      if (isClosed) return;
      result.fold(
        (failure) => emit(state.copyWith(errorMessage: failure.message)),
        (years) => emit(state.copyWith(years: years, errorMessage: null)),
      );
    });
  }

  void _subscribeFavorites() {
    _favoritesSub?.cancel();
    _favoritesSub = _getFavoritesUseCase.watchFavorites().listen((result) {
      if (isClosed) return;
      result.fold(
        (failure) => emit(state.copyWith(errorMessage: failure.message)),
        (favs) => emit(state.copyWith(favorites: favs, errorMessage: null)),
      );
    });
  }

  Future<void> loadFolders() async {
    final result = await _folderUseCases.getFolderHierarchy();
    if (isClosed) return;
    result.fold(
      (failure) => emit(state.copyWith(errorMessage: failure.message)),
      (folders) => emit(state.copyWith(folders: folders, errorMessage: null)),
    );
  }

  void updateSort(String sortBy, bool ascending) {
    emit(state.copyWith(sortBy: sortBy, ascending: ascending));
    _subscribeSongs();
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
    emit(state.copyWith(viewMode: nextMode));
    SharedPreferences.getInstance().then((prefs) async {
      try { await prefs.setString('library_view_mode', nextMode.name); } catch (e, st) { ErrorLogger.log('Failed to persist view mode', error: e, stackTrace: st, category: 'LibraryCubit'); }
    }).catchError((e, st) { ErrorLogger.log('Failed to persist view mode', error: e, stackTrace: st, category: 'LibraryCubit'); });
  }

  int _favoriteOpGen = 0;
  Future<void> toggleFavorite(int songId) async {
    final opGen = ++_favoriteOpGen;
    final previousFavorites = List<SongsTableData>.from(state.favorites);
    final currentFavs = List<SongsTableData>.from(state.favorites);
    final isFav = currentFavs.any((s) => s.id == songId);
    if (isFav) {
      currentFavs.removeWhere((s) => s.id == songId);
      emit(state.copyWith(favorites: currentFavs));
    } else {
      final matchingSong = state.songs.cast<SongsTableData?>().firstWhere(
            (s) => s?.id == songId,
            orElse: () => null,
          );
      if (matchingSong != null) {
        currentFavs.add(matchingSong.copyWith(isFavorite: true));
        emit(state.copyWith(favorites: currentFavs));
      }
    }

    final result = await _toggleFavoriteUseCase(songId);
    if (isClosed || opGen != _favoriteOpGen) return;
    result.fold(
      (failure) => emit(state.copyWith(
          favorites: previousFavorites, errorMessage: failure.message)),
      (_) => null,
    );
  }

  Future<void> toggleFolderExclusion(String folderPath) async {
    final result = await _folderUseCases.toggleExcludeFolder(folderPath);
    if (isClosed) return;
    result.fold(
      (failure) => emit(state.copyWith(errorMessage: failure.message)),
      (_) async {
        await loadFolders();
        if (isClosed) return;
        _subscribeSongs();
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
    emit(state.copyWith(
      selectedSongIds: current,
      isMultiSelectMode: current.isNotEmpty,
    ));
  }

  void selectAllSongs() {
    final allIds = state.songs.map((s) => s.id).toSet();
    emit(state.copyWith(selectedSongIds: allIds, isMultiSelectMode: true));
  }

  void clearSelection() {
    emit(state.copyWith(selectedSongIds: {}, isMultiSelectMode: false));
  }

  List<SongsTableData> getSelectedSongs() {
    return state.songs
        .where((s) => state.selectedSongIds.contains(s.id))
        .toList();
  }

  /// Batch imports YouTube Music playlist tracks as Favorites.
  Future<int> importYtmTracksAsFavorites(List<YtmTrack> tracks) async {
    // TODO(inject): fallback to getIt is a test seam; prefer _musicRepository injected via ctor
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
        emit(state.copyWith(errorMessage: 'Not signed in to YouTube Music'));
        return 0;
      }
      final tracks = await accountService.fetchLikedSongs();
      final count = await importYtmTracksAsFavorites(tracks);
      return count;
    } catch (e, st) {
      ErrorLogger.log('Failed to sync YTM account likes',
          error: e, stackTrace: st, category: 'LibraryCubit');
      if (!isClosed) {
        emit(
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
