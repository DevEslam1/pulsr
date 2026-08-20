// lib/features/library/cubit/library_cubit.dart
import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../../data/db/app_database.dart';
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

  StreamSubscription? _songsSub;
  StreamSubscription? _albumsSub;
  StreamSubscription? _artistsSub;
  StreamSubscription? _genresSub;
  StreamSubscription? _yearsSub;
  StreamSubscription? _favoritesSub;

  LibraryCubit({
    required GetSongsUseCase getSongsUseCase,
    required GetAlbumsUseCase getAlbumsUseCase,
    required GetArtistsUseCase getArtistsUseCase,
    required GetGenresUseCase getGenresUseCase,
    required GetYearsUseCase getYearsUseCase,
    required GetFavoritesUseCase getFavoritesUseCase,
    required ToggleFavoriteUseCase toggleFavoriteUseCase,
    required FolderUseCases folderUseCases,
  })  : _getSongsUseCase = getSongsUseCase,
        _getAlbumsUseCase = getAlbumsUseCase,
        _getArtistsUseCase = getArtistsUseCase,
        _getGenresUseCase = getGenresUseCase,
        _getYearsUseCase = getYearsUseCase,
        _getFavoritesUseCase = getFavoritesUseCase,
        _toggleFavoriteUseCase = toggleFavoriteUseCase,
        _folderUseCases = folderUseCases,
        super(const LibraryState()) {
    init();
  }

  Future<void> init() async {
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
  }

  void toggleViewMode() {
    emit(state.copyWith(
      viewMode: state.viewMode == LibraryViewMode.list ? LibraryViewMode.grid : LibraryViewMode.list,
    ));
  }

  Future<void> toggleFavorite(int songId) async {
    final result = await _toggleFavoriteUseCase(songId);
    result.fold(
      (failure) => emit(state.copyWith(errorMessage: failure.message)),
      (_) => null,
    );
  }

  Future<void> toggleFolderExclusion(String folderPath) async {
    final result = await _folderUseCases.toggleExcludeFolder(folderPath);
    result.fold(
      (failure) => emit(state.copyWith(errorMessage: failure.message)),
      (_) async {
        await loadFolders();
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
    return state.songs.where((s) => state.selectedSongIds.contains(s.id)).toList();
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
