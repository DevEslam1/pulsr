// Additional LibraryCubit coverage: preference hydration, rating sort,
// pagination, favorite reconciliation (optimistic + rollback), folder
// exclusion, multi-select, batch delete and YTM import/sync paths.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/core/services/ytm_account_service.dart';
import 'package:pulsr/data/audio/song_rating_store.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/ytm_track.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';
import 'package:pulsr/domain/usecases/folder_usecases.dart';
import 'package:pulsr/domain/usecases/get_albums_usecase.dart';
import 'package:pulsr/domain/usecases/get_artists_usecase.dart';
import 'package:pulsr/domain/usecases/get_favorites_usecase.dart';
import 'package:pulsr/domain/usecases/get_genres_usecase.dart';
import 'package:pulsr/domain/usecases/get_songs_usecase.dart';
import 'package:pulsr/domain/usecases/get_years_usecase.dart';
import 'package:pulsr/domain/usecases/toggle_favorite_usecase.dart';
import 'package:pulsr/features/library/cubit/library_cubit.dart';
import 'package:pulsr/features/library/cubit/library_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/test_song_factory.dart';

class _GetSongs extends Mock implements GetSongsUseCase {}

class _GetAlbums extends Mock implements GetAlbumsUseCase {}

class _GetArtists extends Mock implements GetArtistsUseCase {}

class _GetGenres extends Mock implements GetGenresUseCase {}

class _GetYears extends Mock implements GetYearsUseCase {}

class _GetFavorites extends Mock implements GetFavoritesUseCase {}

class _ToggleFavorite extends Mock implements ToggleFavoriteUseCase {}

class _FolderUseCases extends Mock implements FolderUseCases {}

class _Repo extends Mock implements IMusicRepository {}

class _Account extends Mock implements YtmAccountService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _GetSongs getSongs;
  late _GetAlbums getAlbums;
  late _GetArtists getArtists;
  late _GetGenres getGenres;
  late _GetYears getYears;
  late _GetFavorites getFavorites;
  late _ToggleFavorite toggleFavorite;
  late _FolderUseCases folders;
  late _Repo repo;
  late StreamController<Result<List<SongsTableData>>> songs;
  late StreamController<Result<List<SongsTableData>>> favorites;

  setUpAll(() {
    registerFallbackValue(createTestSong(id: -1));
    registerFallbackValue(<int>[]);
    registerFallbackValue(const <String>[]);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    getSongs = _GetSongs();
    getAlbums = _GetAlbums();
    getArtists = _GetArtists();
    getGenres = _GetGenres();
    getYears = _GetYears();
    getFavorites = _GetFavorites();
    toggleFavorite = _ToggleFavorite();
    folders = _FolderUseCases();
    repo = _Repo();
    songs = StreamController<Result<List<SongsTableData>>>.broadcast();
    favorites = StreamController<Result<List<SongsTableData>>>.broadcast();

    when(() => getSongs.watchSongs(
          sortBy: any(named: 'sortBy'),
          ascending: any(named: 'ascending'),
          limit: any(named: 'limit'),
          excludedFolders: any(named: 'excludedFolders'),
        )).thenAnswer((_) => songs.stream);
    when(() => getAlbums.watchAlbums())
        .thenAnswer((_) => Stream.value(const Right([])));
    when(() => getArtists.watchArtists())
        .thenAnswer((_) => Stream.value(const Right([])));
    when(() => getGenres.watchGenres())
        .thenAnswer((_) => Stream.value(const Right([])));
    when(() => getYears.watchYears())
        .thenAnswer((_) => Stream.value(const Right([])));
    when(() => getFavorites.watchFavorites())
        .thenAnswer((_) => favorites.stream);
    when(() => folders.getFolderHierarchy())
        .thenAnswer((_) async => const Right([]));
    when(() => folders.getExcludedFolders())
        .thenAnswer((_) async => const Right([]));
    when(() => folders.toggleExcludeFolder(any()))
        .thenAnswer((_) async => const Right(null));
    when(() => repo.getSongsByIds(any()))
        .thenAnswer((_) async => const Right([]));
    when(() => repo.deleteSongs(any()))
        .thenAnswer((_) async => const Right(null));
    when(() => repo.importOnlineTracksAsFavorites(any()))
        .thenAnswer((_) async => const Right(0));
    when(() => repo.watchAllSongs(
          sortBy: any(named: 'sortBy'),
          ascending: any(named: 'ascending'),
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
          searchQuery: any(named: 'searchQuery'),
          excludedFolders: any(named: 'excludedFolders'),
        )).thenAnswer((_) => Stream.value(const Right([])));

    addTearDown(() async {
      await songs.close();
      await favorites.close();
      await getIt.reset();
    });
  });

  LibraryCubit create() => LibraryCubit(
        getSongsUseCase: getSongs,
        getAlbumsUseCase: getAlbums,
        getArtistsUseCase: getArtists,
        getGenresUseCase: getGenres,
        getYearsUseCase: getYears,
        getFavoritesUseCase: getFavorites,
        toggleFavoriteUseCase: toggleFavorite,
        folderUseCases: folders,
        musicRepository: repo,
      );

  Future<void> settle([int ms = 30]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  group('init hydration', () {
    test('restores saved sort and grid view mode', () async {
      SharedPreferences.setMockInitialValues({
        'library_sort_by': 'artist',
        'library_sort_ascending': false,
        'library_view_mode': 'grid',
      });
      final cubit = create();
      await settle();
      expect(cubit.state.sortBy, 'artist');
      expect(cubit.state.ascending, isFalse);
      expect(cubit.state.viewMode, LibraryViewMode.grid);
      await cubit.close();
    });

    test('songs emission populates the list', () async {
      final cubit = create();
      await settle();
      songs.add(Right([createTestSong(id: 1, title: 'A')]));
      await settle();
      expect(cubit.state.songs.length, 1);
      await cubit.close();
    });

    test('a failed songs emission surfaces the error', () async {
      final cubit = create();
      await settle();
      songs.add(const Left(DatabaseFailure('read failed')));
      await settle();
      expect(cubit.state.errorMessage, 'read failed');
      await cubit.close();
    });
  });

  group('sort, view mode and pagination', () {
    test('updateSort persists and re-subscribes with the new sort', () async {
      final cubit = create();
      await settle();
      cubit.updateSort('album', false);
      await settle();
      expect(cubit.state.sortBy, 'album');
      verify(() => getSongs.watchSongs(
            sortBy: 'album',
            ascending: false,
            limit: any(named: 'limit'),
            excludedFolders: any(named: 'excludedFolders'),
          )).called(greaterThanOrEqualTo(1));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('library_sort_by'), 'album');
      await cubit.close();
    });

    test('toggleViewMode persists the new mode', () async {
      final cubit = create();
      await settle();
      cubit.toggleViewMode();
      await settle();
      expect(cubit.state.viewMode, LibraryViewMode.grid);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('library_view_mode'), 'grid');
      await cubit.close();
    });

    test('hitting the window marks hasMore and loadMore grows the window',
        () async {
      when(() => getSongs.watchSongs(
            sortBy: any(named: 'sortBy'),
            ascending: any(named: 'ascending'),
            limit: any(named: 'limit'),
            excludedFolders: any(named: 'excludedFolders'),
          )).thenAnswer((inv) {
        final limit = inv.namedArguments[#limit] as int?;
        final count = limit ?? 500;
        return Stream.value(Right([
          for (var i = 0; i < count; i++) createTestSong(id: i, title: 'S$i'),
        ]));
      });
      final cubit = create();
      await settle(50);
      expect(cubit.hasMoreSongs, isTrue);

      cubit.loadMoreSongs();
      expect(cubit.state.isLoadingMore, isTrue);
      await settle(50);
      verify(() => getSongs.watchSongs(
            sortBy: any(named: 'sortBy'),
            ascending: any(named: 'ascending'),
            limit: LibraryCubit.songsPageSize * 2,
            excludedFolders: any(named: 'excludedFolders'),
          )).called(1);
      await cubit.close();
    });

    test('rating sort evaluates ratings through SongRatingStore', () async {
      SharedPreferences.setMockInitialValues({
        'song_ratings_v1': '{"1":2,"2":5}',
      });
      final store = SongRatingStore();
      getIt.registerSingleton<SongRatingStore>(store);
      await store.ready;

      when(() => getSongs.watchSongs(
            sortBy: any(named: 'sortBy'),
            ascending: any(named: 'ascending'),
            limit: any(named: 'limit'),
            excludedFolders: any(named: 'excludedFolders'),
          )).thenAnswer((_) => Stream.value(Right([
            createTestSong(id: 1, title: 'One'),
            createTestSong(id: 2, title: 'Two'),
          ])));
      final cubit = create();
      await settle();
      cubit.updateSort('rating', false);
      await settle(50);
      expect(cubit.state.songs.first.id, 2);
      await cubit.close();
    });
  });

  group('favorites', () {
    test('promotion is held optimistically while a write is in flight',
        () async {
      final completer = Completer<Result<bool>>();
      when(() => toggleFavorite(1)).thenAnswer((_) => completer.future);
      final cubit = create();
      await settle();
      songs.add(Right([createTestSong(id: 1, title: 'A')]));
      await settle();
      favorites.add(const Right(<SongsTableData>[]));
      await settle();

      final future = cubit.toggleFavorite(1);
      await settle();
      expect(cubit.state.favorites.any((s) => s.id == 1), isTrue);

      completer.complete(const Right(true));
      await future;
      expect(cubit.state.favorites.any((s) => s.id == 1), isTrue);
      await cubit.close();
    });

    test('a failed promotion rolls back and reports the error', () async {
      when(() => toggleFavorite(1))
          .thenAnswer((_) async => const Left(DatabaseFailure('nope')));
      final cubit = create();
      await settle();
      songs.add(Right([createTestSong(id: 1, title: 'A')]));
      await settle();
      favorites.add(const Right(<SongsTableData>[]));
      await settle();

      await cubit.toggleFavorite(1);
      expect(cubit.state.favorites.any((s) => s.id == 1), isFalse);
      expect(cubit.state.errorMessage, 'nope');
      await cubit.close();
    });

    test('demotion removes the favorite on success', () async {
      when(() => toggleFavorite(1))
          .thenAnswer((_) async => const Right(true));
      final cubit = create();
      await settle();
      favorites.add(Right([createTestSong(id: 1, title: 'A', isFavorite: true)]));
      await settle();
      await cubit.toggleFavorite(1);
      expect(cubit.state.favorites.any((s) => s.id == 1), isFalse);
      await cubit.close();
    });

    test('falls back to the repository when the song is not loaded',
        () async {
      when(() => repo.getSongsByIds(any())).thenAnswer(
          (_) async => Right([createTestSong(id: 7, title: 'Hidden')]));
      when(() => toggleFavorite(7))
          .thenAnswer((_) async => const Right(true));
      final cubit = create();
      await settle();
      await cubit.toggleFavorite(7);
      verify(() => repo.getSongsByIds([7])).called(1);
      await cubit.close();
    });
  });

  group('folder exclusion', () {
    test('success reloads folders and re-subscribes songs', () async {
      final cubit = create();
      await settle();
      final res = await cubit.toggleFolderExclusion('/music/hidden');
      expect(res.isRight(), isTrue);
      verify(() => folders.getFolderHierarchy()).called(greaterThanOrEqualTo(2));
      await cubit.close();
    });

    test('failure surfaces the message', () async {
      when(() => folders.toggleExcludeFolder(any()))
          .thenAnswer((_) async => const Left(DatabaseFailure('denied')));
      final cubit = create();
      await settle();
      await cubit.toggleFolderExclusion('/x');
      expect(cubit.state.errorMessage, 'denied');
      await cubit.close();
    });
  });

  group('selection and batch actions', () {
    test('toggleSongSelection and clearSelection manage the set', () async {
      final cubit = create();
      await settle();
      cubit.toggleSongSelection(5);
      expect(cubit.state.selectedSongIds, {5});
      expect(cubit.state.isMultiSelectMode, isTrue);
      cubit.clearSelection();
      expect(cubit.state.selectedSongIds, isEmpty);
      expect(cubit.state.isMultiSelectMode, isFalse);
      await cubit.close();
    });

    test('getSelectedSongs resolves missing ids through the repository',
        () async {
      when(() => repo.getSongsByIds(any())).thenAnswer(
          (_) async => Right([createTestSong(id: 2, title: 'Far')]));
      final cubit = create();
      await settle();
      songs.add(Right([createTestSong(id: 1, title: 'Near')]));
      await settle();
      cubit.toggleSongSelection(1);
      cubit.toggleSongSelection(2);
      final selected = await cubit.getSelectedSongs();
      expect(selected.map((s) => s.id).toSet(), {1, 2});
      await cubit.close();
    });

    test('deleteSelectedSongs reports the removed count', () async {
      when(() => repo.deleteSongs(any()))
          .thenAnswer((_) async => const Right(null));
      final cubit = create();
      await settle();
      songs.add(Right([createTestSong(id: 1, title: 'A')]));
      await settle();
      cubit.toggleSongSelection(1);
      final removed = await cubit.deleteSelectedSongs();
      expect(removed, 1);
      expect(cubit.state.selectedSongIds, isEmpty);
      await cubit.close();
    });

    test('deleteSelectedSongs surfaces a repository failure', () async {
      when(() => repo.deleteSongs(any()))
          .thenAnswer((_) async => const Left(DatabaseFailure('locked')));
      final cubit = create();
      await settle();
      songs.add(Right([createTestSong(id: 1, title: 'A')]));
      await settle();
      cubit.toggleSongSelection(1);
      final removed = await cubit.deleteSelectedSongs();
      expect(removed, -1);
      expect(cubit.state.errorMessage, 'locked');
      await cubit.close();
    });

    test('selectAllSongs uses the loaded window when fully loaded', () async {
      final cubit = create();
      await settle();
      songs.add(Right([createTestSong(id: 1), createTestSong(id: 2)]));
      await settle();
      await cubit.selectAllSongs();
      expect(cubit.state.selectedSongIds, {1, 2});
      await cubit.close();
    });

    test('selectAllSongs queries the repository when more rows exist',
        () async {
      when(() => getSongs.watchSongs(
            sortBy: any(named: 'sortBy'),
            ascending: any(named: 'ascending'),
            limit: any(named: 'limit'),
            excludedFolders: any(named: 'excludedFolders'),
          )).thenAnswer((_) => Stream.value(Right([
            for (var i = 0; i < LibraryCubit.songsPageSize; i++)
              createTestSong(id: i),
          ])));
      when(() => repo.watchAllSongs(
            sortBy: any(named: 'sortBy'),
            ascending: any(named: 'ascending'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
            searchQuery: any(named: 'searchQuery'),
            excludedFolders: any(named: 'excludedFolders'),
          )).thenAnswer((_) => Stream.value(Right([
            for (var i = 0; i < 3; i++) createTestSong(id: 100 + i),
          ])));
      final cubit = create();
      await settle(60);
      expect(cubit.hasMoreSongs, isTrue);
      await cubit.selectAllSongs();
      expect(cubit.state.selectedSongIds, {100, 101, 102});
      await cubit.close();
    });
  });

  group('YTM import and sync', () {
    test('importYtmTracksAsFavorites returns the imported count', () async {
      when(() => repo.importOnlineTracksAsFavorites(any()))
          .thenAnswer((_) async => const Right(4));
      final cubit = create();
      final count = await cubit.importYtmTracksAsFavorites(const [
        YtmTrack(
            videoId: 'v',
            title: 'T',
            artist: 'A',
            duration: Duration(seconds: 1)),
      ]);
      expect(count, 4);
      await cubit.close();
    });

    test('importYtmTracksAsFavorites returns -1 on failure', () async {
      when(() => repo.importOnlineTracksAsFavorites(any()))
          .thenAnswer((_) async => const Left(DatabaseFailure('no')));
      final cubit = create();
      final count = await cubit.importYtmTracksAsFavorites(const []);
      expect(count, -1);
      await cubit.close();
    });

    test('syncYtmAccountLikes reports when not signed in', () async {
      final account = _Account();
      when(() => account.isLoggedIn).thenReturn(false);
      getIt.registerSingleton<YtmAccountService>(account);
      final cubit = create();
      final count = await cubit.syncYtmAccountLikes();
      expect(count, 0);
      expect(cubit.state.errorMessage, contains('Not signed in'));
      await cubit.close();
    });

    test('syncYtmAccountLikes imports liked songs when signed in', () async {
      final account = _Account();
      when(() => account.isLoggedIn).thenReturn(true);
      when(() => account.fetchLikedSongs()).thenAnswer((_) async => const [
        YtmTrack(
            videoId: 'v',
            title: 'T',
            artist: 'A',
            duration: Duration(seconds: 1)),
      ]);
      when(() => repo.importOnlineTracksAsFavorites(any()))
          .thenAnswer((_) async => const Right(1));
      getIt.registerSingleton<YtmAccountService>(account);
      final cubit = create();
      final count = await cubit.syncYtmAccountLikes();
      expect(count, 1);
      await cubit.close();
    });

    test('syncYtmAccountLikes handles a thrown error', () async {
      final account = _Account();
      when(() => account.isLoggedIn).thenReturn(true);
      when(() => account.fetchLikedSongs())
          .thenThrow(Exception('network'));
      getIt.registerSingleton<YtmAccountService>(account);
      final cubit = create();
      final count = await cubit.syncYtmAccountLikes();
      expect(count, 0);
      expect(cubit.state.errorMessage, contains('Failed to sync'));
      await cubit.close();
    });
  });
}
