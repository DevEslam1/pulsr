// lib/features/library/cubit/library_state.dart
import '../../../data/db/app_database.dart';
import '../../../domain/usecases/folder_usecases.dart';

enum LibraryViewMode { list, grid }

class LibraryState {
  final List<SongsTableData> songs;
  final List<AlbumsTableData> albums;
  final List<ArtistsTableData> artists;
  final List<SongsTableData> favorites;
  final List<FolderItem> folders;
  final String sortBy;
  final bool ascending;
  final bool isLoading;
  final String? errorMessage;
  final Set<int> selectedSongIds;
  final bool isMultiSelectMode;
  final LibraryViewMode viewMode;

  const LibraryState({
    this.songs = const [],
    this.albums = const [],
    this.artists = const [],
    this.favorites = const [],
    this.folders = const [],
    this.sortBy = 'title',
    this.ascending = true,
    this.isLoading = false,
    this.errorMessage,
    this.selectedSongIds = const {},
    this.isMultiSelectMode = false,
    this.viewMode = LibraryViewMode.list,
  });

  LibraryState copyWith({
    List<SongsTableData>? songs,
    List<AlbumsTableData>? albums,
    List<ArtistsTableData>? artists,
    List<SongsTableData>? favorites,
    List<FolderItem>? folders,
    String? sortBy,
    bool? ascending,
    bool? isLoading,
    String? errorMessage,
    Set<int>? selectedSongIds,
    bool? isMultiSelectMode,
    LibraryViewMode? viewMode,
  }) {
    return LibraryState(
      songs: songs ?? this.songs,
      albums: albums ?? this.albums,
      artists: artists ?? this.artists,
      favorites: favorites ?? this.favorites,
      folders: folders ?? this.folders,
      sortBy: sortBy ?? this.sortBy,
      ascending: ascending ?? this.ascending,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      selectedSongIds: selectedSongIds ?? this.selectedSongIds,
      isMultiSelectMode: isMultiSelectMode ?? this.isMultiSelectMode,
      viewMode: viewMode ?? this.viewMode,
    );
  }
}
