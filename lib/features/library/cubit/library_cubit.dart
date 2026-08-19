// lib/features/library/cubit/library_cubit.dart
import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/usecases/get_songs_usecase.dart';
import '../../../domain/usecases/get_albums_usecase.dart';
import '../../../domain/usecases/get_artists_usecase.dart';
import '../../../domain/usecases/get_favorites_usecase.dart';
import '../../../domain/usecases/toggle_favorite_usecase.dart';
import '../../../domain/usecases/folder_usecases.dart';
import 'library_state.dart';

class LibraryCubit extends Cubit<LibraryState> {
  final GetSongsUseCase _getSongsUseCase;
  final GetAlbumsUseCase _getAlbumsUseCase;
  final GetArtistsUseCase _getArtistsUseCase;
  final GetFavoritesUseCase _getFavoritesUseCase;
  final ToggleFavoriteUseCase _toggleFavoriteUseCase;
  final FolderUseCases _folderUseCases;

  StreamSubscription? _songsSub;
  StreamSubscription? _albumsSub;
  StreamSubscription? _artistsSub;
  StreamSubscription? _favoritesSub;

  LibraryCubit({
    required GetSongsUseCase getSongsUseCase,
    required GetAlbumsUseCase getAlbumsUseCase,
    required GetArtistsUseCase getArtistsUseCase,
    required GetFavoritesUseCase getFavoritesUseCase,
    required ToggleFavoriteUseCase toggleFavoriteUseCase,
    required FolderUseCases folderUseCases,
  })  : _getSongsUseCase = getSongsUseCase,
        _getAlbumsUseCase = getAlbumsUseCase,
        _getArtistsUseCase = getArtistsUseCase,
        _getFavoritesUseCase = getFavoritesUseCase,
        _toggleFavoriteUseCase = toggleFavoriteUseCase,
        _folderUseCases = folderUseCases,
        super(const LibraryState()) {
    init();
  }

  void init() {
    _subscribeSongs();
    _subscribeAlbums();
    _subscribeArtists();
    _subscribeFavorites();
    loadFolders();
  }

  void _subscribeSongs() {
    _songsSub?.cancel();
    _songsSub = _getSongsUseCase.watchSongs(
      sortBy: state.sortBy,
      ascending: state.ascending,
    ).listen((songs) {
      emit(state.copyWith(songs: songs));
    });
  }

  void _subscribeAlbums() {
    _albumsSub?.cancel();
    _albumsSub = _getAlbumsUseCase.watchAlbums().listen((albums) {
      emit(state.copyWith(albums: albums));
    });
  }

  void _subscribeArtists() {
    _artistsSub?.cancel();
    _artistsSub = _getArtistsUseCase.watchArtists().listen((artists) {
      emit(state.copyWith(artists: artists));
    });
  }

  void _subscribeFavorites() {
    _favoritesSub?.cancel();
    _favoritesSub = _getFavoritesUseCase.watchFavorites().listen((favs) {
      emit(state.copyWith(favorites: favs));
    });
  }

  Future<void> loadFolders() async {
    final folders = await _folderUseCases.getFolderHierarchy();
    if (isClosed) return;
    emit(state.copyWith(folders: folders));
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
    await _toggleFavoriteUseCase(songId);
  }

  Future<void> toggleFolderExclusion(String folderPath) async {
    await _folderUseCases.toggleExcludeFolder(folderPath);
    await loadFolders();
    _subscribeSongs();
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
    _favoritesSub?.cancel();
    return super.close();
  }
}
