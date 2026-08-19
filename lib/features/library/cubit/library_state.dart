// lib/features/library/cubit/library_state.dart
import 'package:freezed_annotation/freezed_annotation.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/models/genre_item.dart';
import '../../../domain/models/year_item.dart';
import '../../../domain/usecases/folder_usecases.dart';

part 'library_state.freezed.dart';

enum LibraryViewMode { list, grid }

@freezed
abstract class LibraryState with _$LibraryState {
  const LibraryState._();

  const factory LibraryState({
    @Default([]) List<SongsTableData> songs,
    @Default([]) List<AlbumsTableData> albums,
    @Default([]) List<ArtistsTableData> artists,
    @Default([]) List<GenreItem> genres,
    @Default([]) List<YearItem> years,
    @Default([]) List<SongsTableData> favorites,
    @Default([]) List<FolderItem> folders,
    @Default('title') String sortBy,
    @Default(true) bool ascending,
    @Default(false) bool isLoading,
    String? errorMessage,
    @Default({}) Set<int> selectedSongIds,
    @Default(false) bool isMultiSelectMode,
    @Default(LibraryViewMode.list) LibraryViewMode viewMode,
  }) = _LibraryState;
}
