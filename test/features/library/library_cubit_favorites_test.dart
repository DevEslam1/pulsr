import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/usecases/folder_usecases.dart';
import 'package:pulsr/domain/usecases/get_albums_usecase.dart';
import 'package:pulsr/domain/usecases/get_artists_usecase.dart';
import 'package:pulsr/domain/usecases/get_favorites_usecase.dart';
import 'package:pulsr/domain/usecases/get_genres_usecase.dart';
import 'package:pulsr/domain/usecases/get_songs_usecase.dart';
import 'package:pulsr/domain/usecases/get_years_usecase.dart';
import 'package:pulsr/domain/usecases/toggle_favorite_usecase.dart';
import 'package:pulsr/features/library/cubit/library_cubit.dart';
import '../../helpers/test_song_factory.dart';

class MockGetSongsUseCase extends Mock implements GetSongsUseCase {}
class MockGetAlbumsUseCase extends Mock implements GetAlbumsUseCase {}
class MockGetArtistsUseCase extends Mock implements GetArtistsUseCase {}
class MockGetGenresUseCase extends Mock implements GetGenresUseCase {}
class MockGetYearsUseCase extends Mock implements GetYearsUseCase {}
class MockGetFavoritesUseCase extends Mock implements GetFavoritesUseCase {}
class MockToggleFavoriteUseCase extends Mock implements ToggleFavoriteUseCase {}
class MockFolderUseCases extends Mock implements FolderUseCases {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockGetSongsUseCase mockGetSongs;
  late MockGetAlbumsUseCase mockGetAlbums;
  late MockGetArtistsUseCase mockGetArtists;
  late MockGetGenresUseCase mockGetGenres;
  late MockGetYearsUseCase mockGetYears;
  late MockGetFavoritesUseCase mockGetFavorites;
  late MockToggleFavoriteUseCase mockToggleFavorite;
  late MockFolderUseCases mockFolderUseCases;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
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
          limit: any(named: 'limit'),
          excludedFolders: any(named: 'excludedFolders'),
        )).thenAnswer((_) => Stream.value(const Right([])));
    when(() => mockGetAlbums.watchAlbums())
        .thenAnswer((_) => Stream.value(const Right([])));
    when(() => mockGetArtists.watchArtists())
        .thenAnswer((_) => Stream.value(const Right([])));
    when(() => mockGetGenres.watchGenres(
            excludedFolders: any(named: 'excludedFolders')))
        .thenAnswer((_) => Stream.value(const Right([])));
    when(() => mockGetYears.watchYears(
            excludedFolders: any(named: 'excludedFolders')))
        .thenAnswer((_) => Stream.value(const Right([])));
    when(() => mockGetFavorites.watchFavorites())
        .thenAnswer((_) => Stream.value(const Right([])));
    when(() => mockFolderUseCases.watchExcludedFolders())
        .thenAnswer((_) => Stream.value(const Right([])));
    when(() => mockFolderUseCases.getFolderHierarchy())
        .thenAnswer((_) async => const Right([]));
    when(() => mockFolderUseCases.getExcludedFolders())
        .thenAnswer((_) async => const Right([]));
  });

  LibraryCubit createCubit() {
    return LibraryCubit(
      getSongsUseCase: mockGetSongs,
      getAlbumsUseCase: mockGetAlbums,
      getArtistsUseCase: mockGetArtists,
      getGenresUseCase: mockGetGenres,
      getYearsUseCase: mockGetYears,
      getFavoritesUseCase: mockGetFavorites,
      toggleFavoriteUseCase: mockToggleFavorite,
      folderUseCases: mockFolderUseCases,
    );
  }

  group('LibraryCubit Favorites Toggle & Rollback', () {
    test('rapid toggle race resolves sequentially via song mutex', () async {
      final song = createTestSong(id: 42, title: 'Rapid Song', isFavorite: false);
      final songsController = StreamController<Result<List<SongsTableData>>>.broadcast();
      when(() => mockGetSongs.watchSongs(
            sortBy: any(named: 'sortBy'),
            ascending: any(named: 'ascending'),
            limit: any(named: 'limit'),
            excludedFolders: any(named: 'excludedFolders'),
          )).thenAnswer((_) => songsController.stream);

      final cubit = createCubit();
      await cubit.init();
      songsController.add(Right([song]));
      await pumpEventQueue();

      int callCount = 0;
      final completer1 = Completer<void>();
      final completer2 = Completer<void>();

      when(() => mockToggleFavorite(42)).thenAnswer((_) async {
        callCount++;
        if (callCount == 1) {
          await completer1.future;
          return const Right(true);
        } else {
          await completer2.future;
          return const Right(false);
        }
      });

      // Fire 2 toggles rapidly in parallel
      final future1 = cubit.toggleFavorite(42);
      final future2 = cubit.toggleFavorite(42);

      // Finish first call
      completer1.complete();
      await future1;

      // Finish second call
      completer2.complete();
      await future2;

      expect(callCount, equals(2));
      await cubit.close();
      await songsController.close();
    });

    test('failure rollback restores pre-toggle state and sets error message', () async {
      final song = createTestSong(id: 99, title: 'Rollback Song', isFavorite: false);
      final songsController = StreamController<Result<List<SongsTableData>>>.broadcast();
      when(() => mockGetSongs.watchSongs(
            sortBy: any(named: 'sortBy'),
            ascending: any(named: 'ascending'),
            limit: any(named: 'limit'),
            excludedFolders: any(named: 'excludedFolders'),
          )).thenAnswer((_) => songsController.stream);

      final cubit = createCubit();
      await cubit.init();
      songsController.add(Right([song]));
      await pumpEventQueue();

      when(() => mockToggleFavorite(99)).thenAnswer(
        (_) async => Left(DatabaseFailure('Disk write failed')),
      );

      await cubit.toggleFavorite(99);

      // Should have rolled back favorite to false
      expect(cubit.state.favorites.any((s) => s.id == 99), isFalse);
      expect(cubit.state.songs.firstWhere((s) => s.id == 99).isFavorite, isFalse);
      expect(cubit.state.errorMessage, equals('Disk write failed'));

      await cubit.close();
      await songsController.close();
    });

    test('failure rollback when un-favoriting restores favorite to true', () async {
      final song = createTestSong(id: 77, title: 'Already Fav', isFavorite: true);
      final favsController = StreamController<Result<List<SongsTableData>>>.broadcast();
      when(() => mockGetFavorites.watchFavorites())
          .thenAnswer((_) => favsController.stream);

      final cubit = createCubit();
      await cubit.init();
      favsController.add(Right([song]));
      await pumpEventQueue();

      when(() => mockToggleFavorite(77)).thenThrow(Exception('Simulated crash'));

      await cubit.toggleFavorite(77);

      // Exception was caught, rolled back, and preserved favorite = true
      expect(cubit.state.favorites.any((s) => s.id == 77), isTrue);
      expect(cubit.state.errorMessage, contains('Could not update favorite'));

      await cubit.close();
      await favsController.close();
    });
  });
}
