// Additional LibraryCubit branch coverage: clearError, folder-load failure,
// excluded-folder lookup throwing during subscribe, the no-store rating sort,
// select-all fallbacks (null repo / repository throw), null-repo delete +
// import, a sync repository failure, a raw favorite-use-case throw and the
// loadMoreSongs no-op guards.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/core/services/ytm_account_service.dart';
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
  late StreamController<Result<List<SongsTableData>>> songs;

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
    songs = StreamController<Result<List<SongsTableData>>>.broadcast();

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
        .thenAnswer((_) => Stream.value(const Right([])));
    when(() => folders.getFolderHierarchy())
        .thenAnswer((_) async => const Right([]));
    when(() => folders.getExcludedFolders())
        .thenAnswer((_) async => const Right([]));
    when(() => folders.toggleExcludeFolder(any()))
        .thenAnswer((_) async => const Right(null));

    addTearDown(() async {
      await songs.close();
      await getIt.reset();
    });
  });

  LibraryCubit create({IMusicRepository? repo}) => LibraryCubit(
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

  Future<void> settle([int ms = 40]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  List<SongsTableData> manySongs(int count) => [
        for (var i = 0; i < count; i++) createTestSong(id: i, title: 'S$i'),
      ];

  test('clearError clears the message', () async {
    final cubit = create();
    await settle();
    songs.add(const Left(DatabaseFailure('boom')));
    await settle();
    expect(cubit.state.errorMessage, 'boom');
    cubit.clearError();
    expect(cubit.state.errorMessage, isNull);
    await cubit.close();
  });

  test('loadFolders failure surfaces the message', () async {
    when(() => folders.getFolderHierarchy())
        .thenAnswer((_) async => const Left(DatabaseFailure('no folders')));
    final cubit = create();
    await settle();
    await cubit.loadFolders();
    expect(cubit.state.errorMessage, 'no folders');
    await cubit.close();
  });

  test('a throwing excluded-folder lookup does not block the songs stream',
      () async {
    when(() => folders.getExcludedFolders()).thenThrow(Exception('io'));
    final cubit = create();
    await settle();
    songs.add(Right([createTestSong(id: 1, title: 'A')]));
    await settle();
    expect(cubit.state.songs.length, 1);
    await cubit.close();
  });

  test('rating sort without a registered store keeps the emitted order',
      () async {
    final cubit = create();
    await settle();
    cubit.updateSort('rating', false);
    await settle();
    songs.add(Right([
      createTestSong(id: 1, title: 'B'),
      createTestSong(id: 2, title: 'A'),
    ]));
    await settle();
    expect(cubit.state.songs.map((s) => s.id).toList(), [1, 2]);
    await cubit.close();
  });

  test('selectAllSongs falls back to the loaded window when repository is null',
      () async {
    when(() => getSongs.watchSongs(
          sortBy: any(named: 'sortBy'),
          ascending: any(named: 'ascending'),
          limit: any(named: 'limit'),
          excludedFolders: any(named: 'excludedFolders'),
        )).thenAnswer((_) => Stream.value(Right(manySongs(500))));
    final cubit = create();
    await settle(80);
    expect(cubit.hasMoreSongs, isTrue);

    await cubit.selectAllSongs();
    expect(cubit.state.selectedSongIds.length, 500);
    await cubit.close();
  });

  test('selectAllSongs falls back when the repository query throws', () async {
    final repo = _Repo();
    when(() => repo.watchAllSongs(
          sortBy: any(named: 'sortBy'),
          ascending: any(named: 'ascending'),
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
          searchQuery: any(named: 'searchQuery'),
          excludedFolders: any(named: 'excludedFolders'),
        )).thenThrow(Exception('db down'));
    when(() => getSongs.watchSongs(
          sortBy: any(named: 'sortBy'),
          ascending: any(named: 'ascending'),
          limit: any(named: 'limit'),
          excludedFolders: any(named: 'excludedFolders'),
        )).thenAnswer((_) => Stream.value(Right(manySongs(500))));
    final cubit = create(repo: repo);
    await settle(80);
    expect(cubit.hasMoreSongs, isTrue);

    await cubit.selectAllSongs();
    expect(cubit.state.selectedSongIds.length, 500);
    await cubit.close();
  });

  test('deleteSelectedSongs without a repository reports unavailable',
      () async {
    final cubit = create();
    await settle();
    songs.add(Right([createTestSong(id: 1, title: 'A')]));
    await settle();
    cubit.toggleSongSelection(1);

    final removed = await cubit.deleteSelectedSongs();
    expect(removed, -1);
    expect(cubit.state.errorMessage, 'Delete is unavailable right now');
    await cubit.close();
  });

  test('importYtmTracksAsFavorites without a repository returns -1', () async {
    final cubit = create();
    await settle();
    expect(await cubit.importYtmTracksAsFavorites(const []), -1);
    await cubit.close();
  });

  test('syncYtmAccountLikes surfaces a repository failure', () async {
    final account = _Account();
    when(() => account.isLoggedIn).thenReturn(true);
    when(() => account.fetchLikedSongs()).thenAnswer((_) async => const [
          YtmTrack(
              videoId: 'v',
              title: 'T',
              artist: 'A',
              duration: Duration(seconds: 1)),
        ]);
    final repo = _Repo();
    when(() => repo.importOnlineTracksAsFavorites(any()))
        .thenAnswer((_) async => const Left(DatabaseFailure('import failed')));
    getIt.registerSingleton<YtmAccountService>(account);
    final cubit = create(repo: repo);
    await settle();

    final count = await cubit.syncYtmAccountLikes();
    expect(count, 0);
    expect(cubit.state.errorMessage, isNotNull);
    await cubit.close();
  });

  test('a raw favorite-use-case throw rolls back and reports the error',
      () async {
    when(() => toggleFavorite(1)).thenThrow(Exception('boom'));
    final cubit = create();
    await settle();
    songs.add(Right([createTestSong(id: 1, title: 'A')]));
    await settle();
    await cubit.toggleFavorite(1);
    expect(cubit.state.favorites.any((s) => s.id == 1), isFalse);
    expect(cubit.state.errorMessage, 'Could not update favorite');
    await cubit.close();
  });

  test('loadMoreSongs is a no-op without more rows', () async {
    final cubit = create();
    await settle();
    songs.add(Right([createTestSong(id: 1, title: 'A')]));
    await settle();
    expect(cubit.hasMoreSongs, isFalse);

    cubit.loadMoreSongs();
    expect(cubit.state.isLoadingMore, isFalse);
    await cubit.close();
  });
}
