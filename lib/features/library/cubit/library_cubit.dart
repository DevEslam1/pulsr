// lib/features/library/cubit/library_cubit.dart
import 'dart:async';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/bloc/base_cubit.dart';
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

  Future<void> _subscribeSongs() async {
    final t = ++_songsToken;
    _songsSub?.cancel();
    removeFromComposite(_songsSub);
    _songsSub = null;
    final excludedRes = await _folderUseCases.getExcludedFolders();
    if (isClosed || t != _songsToken) return;
    final excluded = excludedRes.fold((l) => <String>[], (r) => r);
    _songsSub = autoSub(
      _getSongsUseCase.watchSongs(
        sortBy: state.sortBy,
        ascending: state.ascending,
        excludedFolders: excluded,
      ),
      (result) {
        result.fold(
          (failure) => safeEmit(state.copyWith(errorMessage: failure.message)),
          (songs) => safeEmit(state.copyWith(songs: songs, errorMessage: null)),
        );
      },
    );
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
    safeEmit(state.copyWith(viewMode: nextMode));
    SharedPreferences.getInstance().then((prefs) async {
      try { await prefs.setString('library_view_mode', nextMode.name); } catch (e, st) { ErrorLogger.log('Failed to persist view mode', error: e, stackTrace: st, category: 'LibraryCubit'); }
    }).catchError((e, st) { ErrorLogger.log('Failed to persist view mode', error: e, stackTrace: st, category: 'LibraryCubit'); });
  }

  final Map<int, int> _favoriteOpTokens = {};
  Future<void> toggleFavorite(int songId) async {
    final opToken = (_favoriteOpTokens[songId] ?? 0) + 1;
    _favoriteOpTokens[songId] = opToken;

    List<SongsTableData> songsWith(bool isFavorite) => state.songs
        .map((s) => s.id == songId ? s.copyWith(isFavorite: isFavorite) : s)
        .toList();

    final currentFavs = List<SongsTableData>.from(state.favorites);
    final wasFav = currentFavs.any((s) => s.id == songId);
    if (wasFav) {
      currentFavs.removeWhere((s) => s.id == songId);
      safeEmit(state.copyWith(favorites: currentFavs, songs: songsWith(false)));
    } else {
      final matchingSong = state.songs.cast<SongsTableData?>().firstWhere(
            (s) => s?.id == songId,
            orElse: () => null,
          );
      if (matchingSong != null) {
        currentFavs.add(matchingSong.copyWith(isFavorite: true));
        safeEmit(state.copyWith(favorites: currentFavs, songs: songsWith(true)));
      }
    }

    final result = await _toggleFavoriteUseCase(songId);
    if (isClosed || _favoriteOpTokens[songId] != opToken) return;
    final failureMessage = result.fold<String?>((l) => l.message, (_) => null);
    if (failureMessage == null) {
      safeEmit(state.copyWith(errorMessage: null));
      return;
    }
    final reconciled = List<SongsTableData>.from(state.favorites);
    if (wasFav) {
      final matchingSong = state.songs.cast<SongsTableData?>().firstWhere(
            (s) => s?.id == songId,
            orElse: () => null,
          );
      if (matchingSong != null && !reconciled.any((s) => s.id == songId)) {
        reconciled.add(matchingSong.copyWith(isFavorite: true));
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
