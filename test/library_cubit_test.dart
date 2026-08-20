// test/library_cubit_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/usecases/folder_usecases.dart';
import 'package:pulsr/domain/usecases/get_albums_usecase.dart';
import 'package:pulsr/domain/usecases/get_artists_usecase.dart';
import 'package:pulsr/domain/usecases/get_favorites_usecase.dart';
import 'package:pulsr/domain/usecases/get_genres_usecase.dart';
import 'package:pulsr/domain/usecases/get_years_usecase.dart';
import 'package:pulsr/domain/usecases/get_songs_usecase.dart';
import 'package:pulsr/domain/usecases/toggle_favorite_usecase.dart';
import 'package:pulsr/features/library/cubit/library_cubit.dart';
import 'package:pulsr/features/library/cubit/library_state.dart';

class MockGetSongsUseCase extends Mock implements GetSongsUseCase {}
class MockGetAlbumsUseCase extends Mock implements GetAlbumsUseCase {}
class MockGetArtistsUseCase extends Mock implements GetArtistsUseCase {}
class MockGetGenresUseCase extends Mock implements GetGenresUseCase {}
class MockGetYearsUseCase extends Mock implements GetYearsUseCase {}
class MockGetFavoritesUseCase extends Mock implements GetFavoritesUseCase {}
class MockToggleFavoriteUseCase extends Mock implements ToggleFavoriteUseCase {}
class MockFolderUseCases extends Mock implements FolderUseCases {}

void main() {
  late MockGetSongsUseCase mockGetSongs;
  late MockGetAlbumsUseCase mockGetAlbums;
  late MockGetArtistsUseCase mockGetArtists;
  late MockGetGenresUseCase mockGetGenres;
  late MockGetYearsUseCase mockGetYears;
  late MockGetFavoritesUseCase mockGetFavorites;
  late MockToggleFavoriteUseCase mockToggleFavorite;
  late MockFolderUseCases mockFolderUseCases;

  setUp(() {
    mockGetSongs = MockGetSongsUseCase();
    mockGetAlbums = MockGetAlbumsUseCase();
    mockGetArtists = MockGetArtistsUseCase();
    mockGetGenres = MockGetGenresUseCase();
    mockGetYears = MockGetYearsUseCase();
    mockGetFavorites = MockGetFavoritesUseCase();
    mockToggleFavorite = MockToggleFavoriteUseCase();
    mockFolderUseCases = MockFolderUseCases();

    when(() => mockGetSongs.watchSongs(
          sortBy: any(named: 'sortBy'),
          ascending: any(named: 'ascending'),
          excludedFolders: any(named: 'excludedFolders'),
        )).thenAnswer((_) => Stream.value(const Right([])));
    when(() => mockGetAlbums.watchAlbums()).thenAnswer((_) => Stream.value(const Right([])));
    when(() => mockGetArtists.watchArtists()).thenAnswer((_) => Stream.value(const Right([])));
    when(() => mockGetGenres.watchGenres()).thenAnswer((_) => Stream.value(const Right([])));
    when(() => mockGetYears.watchYears()).thenAnswer((_) => Stream.value(const Right([])));
    when(() => mockGetFavorites.watchFavorites()).thenAnswer((_) => Stream.value(const Right([])));
    when(() => mockFolderUseCases.getFolderHierarchy()).thenAnswer((_) async => const Right([]));
    when(() => mockFolderUseCases.getExcludedFolders()).thenAnswer((_) async => const Right([]));
  });

  group('LibraryCubit', () {
    test('initial state has default list view and empty selection', () async {
      final cubit = LibraryCubit(
        getSongsUseCase: mockGetSongs,
        getAlbumsUseCase: mockGetAlbums,
        getArtistsUseCase: mockGetArtists,
        getGenresUseCase: mockGetGenres,
        getYearsUseCase: mockGetYears,
        getFavoritesUseCase: mockGetFavorites,
        toggleFavoriteUseCase: mockToggleFavorite,
        folderUseCases: mockFolderUseCases,
      );

      expect(cubit.state.viewMode, LibraryViewMode.list);
      expect(cubit.state.isMultiSelectMode, false);
      expect(cubit.state.selectedSongIds, isEmpty);

      await cubit.close();
    });

    test('toggleViewMode switches between list and grid', () async {
      final cubit = LibraryCubit(
        getSongsUseCase: mockGetSongs,
        getAlbumsUseCase: mockGetAlbums,
        getArtistsUseCase: mockGetArtists,
        getGenresUseCase: mockGetGenres,
        getYearsUseCase: mockGetYears,
        getFavoritesUseCase: mockGetFavorites,
        toggleFavoriteUseCase: mockToggleFavorite,
        folderUseCases: mockFolderUseCases,
      );

      cubit.toggleViewMode();
      expect(cubit.state.viewMode, LibraryViewMode.grid);

      cubit.toggleViewMode();
      expect(cubit.state.viewMode, LibraryViewMode.list);

      await cubit.close();
    });

    test('multi-select selects and deselects song IDs', () async {
      final cubit = LibraryCubit(
        getSongsUseCase: mockGetSongs,
        getAlbumsUseCase: mockGetAlbums,
        getArtistsUseCase: mockGetArtists,
        getGenresUseCase: mockGetGenres,
        getYearsUseCase: mockGetYears,
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

      await cubit.close();
    });

    test('toggleFavorite delegates to ToggleFavoriteUseCase', () async {
      when(() => mockToggleFavorite(101)).thenAnswer((_) async => const Right(true));

      final cubit = LibraryCubit(
        getSongsUseCase: mockGetSongs,
        getAlbumsUseCase: mockGetAlbums,
        getArtistsUseCase: mockGetArtists,
        getGenresUseCase: mockGetGenres,
        getYearsUseCase: mockGetYears,
        getFavoritesUseCase: mockGetFavorites,
        toggleFavoriteUseCase: mockToggleFavorite,
        folderUseCases: mockFolderUseCases,
      );

      await cubit.toggleFavorite(101);
      verify(() => mockToggleFavorite(101)).called(1);

      await cubit.close();
    });

    test('init subscribes to songs stream and populates state', () async {
      const song = SongsTableData(
        id: 1,
        title: 'Streamed Song',
        artist: 'Artist',
        album: 'Album',
        durationMs: 1000,
        path: '/path/s.mp3',
        isFavorite: false,
        playCount: 0,
        lastPositionMs: 0,
      );
      when(() => mockGetSongs.watchSongs(
            sortBy: any(named: 'sortBy'),
            ascending: any(named: 'ascending'),
            excludedFolders: any(named: 'excludedFolders'),
          )).thenAnswer((_) => Stream.value(const Right([song])));
      when(() => mockGetAlbums.watchAlbums()).thenAnswer((_) => Stream.value(const Right([])));
      when(() => mockGetArtists.watchArtists()).thenAnswer((_) => Stream.value(const Right([])));
      when(() => mockGetGenres.watchGenres()).thenAnswer((_) => Stream.value(const Right([])));
      when(() => mockGetYears.watchYears()).thenAnswer((_) => Stream.value(const Right([])));
      when(() => mockGetFavorites.watchFavorites()).thenAnswer((_) => Stream.value(const Right([])));
      when(() => mockFolderUseCases.getFolderHierarchy()).thenAnswer((_) async => const Right([]));
      when(() => mockFolderUseCases.getExcludedFolders()).thenAnswer((_) async => const Right([]));

      final cubit = LibraryCubit(
        getSongsUseCase: mockGetSongs,
        getAlbumsUseCase: mockGetAlbums,
        getArtistsUseCase: mockGetArtists,
        getGenresUseCase: mockGetGenres,
        getYearsUseCase: mockGetYears,
        getFavoritesUseCase: mockGetFavorites,
        toggleFavoriteUseCase: mockToggleFavorite,
        folderUseCases: mockFolderUseCases,
      );
      await Future.delayed(const Duration(milliseconds: 50));

      expect(cubit.state.songs.length, equals(1));
      expect(cubit.state.songs.first.title, equals('Streamed Song'));

      await cubit.close();
    });
  });
}
