// test/library_cubit_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pulsr/domain/usecases/folder_usecases.dart';
import 'package:pulsr/domain/usecases/get_albums_usecase.dart';
import 'package:pulsr/domain/usecases/get_artists_usecase.dart';
import 'package:pulsr/domain/usecases/get_favorites_usecase.dart';
import 'package:pulsr/domain/usecases/get_songs_usecase.dart';
import 'package:pulsr/domain/usecases/toggle_favorite_usecase.dart';
import 'package:pulsr/features/library/cubit/library_cubit.dart';
import 'package:pulsr/features/library/cubit/library_state.dart';

class MockGetSongsUseCase extends Mock implements GetSongsUseCase {}
class MockGetAlbumsUseCase extends Mock implements GetAlbumsUseCase {}
class MockGetArtistsUseCase extends Mock implements GetArtistsUseCase {}
class MockGetFavoritesUseCase extends Mock implements GetFavoritesUseCase {}
class MockToggleFavoriteUseCase extends Mock implements ToggleFavoriteUseCase {}
class MockFolderUseCases extends Mock implements FolderUseCases {}

void main() {
  late MockGetSongsUseCase mockGetSongs;
  late MockGetAlbumsUseCase mockGetAlbums;
  late MockGetArtistsUseCase mockGetArtists;
  late MockGetFavoritesUseCase mockGetFavorites;
  late MockToggleFavoriteUseCase mockToggleFavorite;
  late MockFolderUseCases mockFolderUseCases;

  setUp(() {
    mockGetSongs = MockGetSongsUseCase();
    mockGetAlbums = MockGetAlbumsUseCase();
    mockGetArtists = MockGetArtistsUseCase();
    mockGetFavorites = MockGetFavoritesUseCase();
    mockToggleFavorite = MockToggleFavoriteUseCase();
    mockFolderUseCases = MockFolderUseCases();

    when(() => mockGetSongs.watchSongs(sortBy: any(named: 'sortBy'), ascending: any(named: 'ascending')))
        .thenAnswer((_) => Stream.value([]));
    when(() => mockGetAlbums.watchAlbums()).thenAnswer((_) => Stream.value([]));
    when(() => mockGetArtists.watchArtists()).thenAnswer((_) => Stream.value([]));
    when(() => mockGetFavorites.watchFavorites()).thenAnswer((_) => Stream.value([]));
    when(() => mockFolderUseCases.getFolderHierarchy()).thenAnswer((_) async => []);
  });

  group('LibraryCubit', () {
    test('initial state has default list view and empty selection', () {
      final cubit = LibraryCubit(
        getSongsUseCase: mockGetSongs,
        getAlbumsUseCase: mockGetAlbums,
        getArtistsUseCase: mockGetArtists,
        getFavoritesUseCase: mockGetFavorites,
        toggleFavoriteUseCase: mockToggleFavorite,
        folderUseCases: mockFolderUseCases,
      );

      expect(cubit.state.viewMode, LibraryViewMode.list);
      expect(cubit.state.isMultiSelectMode, false);
      expect(cubit.state.selectedSongIds, isEmpty);

      cubit.close();
    });

    test('toggleViewMode switches between list and grid', () {
      final cubit = LibraryCubit(
        getSongsUseCase: mockGetSongs,
        getAlbumsUseCase: mockGetAlbums,
        getArtistsUseCase: mockGetArtists,
        getFavoritesUseCase: mockGetFavorites,
        toggleFavoriteUseCase: mockToggleFavorite,
        folderUseCases: mockFolderUseCases,
      );

      cubit.toggleViewMode();
      expect(cubit.state.viewMode, LibraryViewMode.grid);

      cubit.toggleViewMode();
      expect(cubit.state.viewMode, LibraryViewMode.list);

      cubit.close();
    });

    test('multi-select selects and deselects song IDs', () {
      final cubit = LibraryCubit(
        getSongsUseCase: mockGetSongs,
        getAlbumsUseCase: mockGetAlbums,
        getArtistsUseCase: mockGetArtists,
        getFavoritesUseCase: mockGetFavorites,
        toggleFavoriteUseCase: mockToggleFavorite,
        folderUseCases: mockFolderUseCases,
      );

      cubit.toggleSongSelection(101);
      expect(cubit.state.isMultiSelectMode, true);
      expect(cubit.state.selectedSongIds.contains(101), true);

      cubit.toggleSongSelection(101);
      expect(cubit.state.isMultiSelectMode, false);
      expect(cubit.state.selectedSongIds.isEmpty, true);

      cubit.close();
    });

    test('toggleFavorite delegates to ToggleFavoriteUseCase', () async {
      when(() => mockToggleFavorite(101)).thenAnswer((_) async => const Right(true));

      final cubit = LibraryCubit(
        getSongsUseCase: mockGetSongs,
        getAlbumsUseCase: mockGetAlbums,
        getArtistsUseCase: mockGetArtists,
        getFavoritesUseCase: mockGetFavorites,
        toggleFavoriteUseCase: mockToggleFavorite,
        folderUseCases: mockFolderUseCases,
      );

      await cubit.toggleFavorite(101);
      verify(() => mockToggleFavorite(101)).called(1);

      cubit.close();
    });
  });
}
