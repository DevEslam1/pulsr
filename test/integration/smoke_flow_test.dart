// test/integration/smoke_flow_test.dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/db/app_database.dart';
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
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_pulsr_audio_handler.dart';

class MockMusicRepository extends Mock implements IMusicRepository {}

class MockToggleFavoriteUseCase extends Mock implements ToggleFavoriteUseCase {}

class MockGetSongsUseCase extends Mock implements GetSongsUseCase {}

class MockGetAlbumsUseCase extends Mock implements GetAlbumsUseCase {}

class MockGetArtistsUseCase extends Mock implements GetArtistsUseCase {}

class MockGetGenresUseCase extends Mock implements GetGenresUseCase {}

class MockGetYearsUseCase extends Mock implements GetYearsUseCase {}

class MockGetFavoritesUseCase extends Mock implements GetFavoritesUseCase {}

class MockFolderUseCases extends Mock implements FolderUseCases {}

/// Polls [condition] until it is true or [timeout] elapses. Using a condition
/// instead of a fixed-duration sleep keeps the smoke journey deterministic when
/// the suite is run with high test concurrency (many isolates on few cores),
/// where a fixed 100 ms window can starve the async `LibraryCubit.init()` chain.
Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 15),
  Duration poll = const Duration(milliseconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Condition not met within $timeout');
    }
    await Future<void>.delayed(poll);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Integration Smoke Test: Cold Start -> Library Load -> Play Song', () {
    late TestPulsrAudioHandler fakeAudioHandler;
    late MockMusicRepository mockMusicRepo;
    late MockToggleFavoriteUseCase mockToggleFavorite;

    late MockGetSongsUseCase mockGetSongs;
    late MockGetAlbumsUseCase mockGetAlbums;
    late MockGetArtistsUseCase mockGetArtists;
    late MockGetGenresUseCase mockGetGenres;
    late MockGetYearsUseCase mockGetYears;
    late MockGetFavoritesUseCase mockGetFavorites;
    late MockFolderUseCases mockFolderUseCases;

    final sampleSong = SongsTableData(
      id: 1,
      title: 'Flagship Symphony',
      artist: 'Pulsr Acoustic Lab',
      album: 'Audiophile Master Series',
      durationMs: 240000,
      path: '/music/flagship_symphony.flac',
      isFavorite: false,
      isMissing: false,
      isDownloaded: false,
      playCount: 0,
      lastPositionMs: 0,
      source: SongSource.local,
    );

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      fakeAudioHandler = TestPulsrAudioHandler();
      mockMusicRepo = MockMusicRepository();
      mockToggleFavorite = MockToggleFavoriteUseCase();

      mockGetSongs = MockGetSongsUseCase();
      mockGetAlbums = MockGetAlbumsUseCase();
      mockGetArtists = MockGetArtistsUseCase();
      mockGetGenres = MockGetGenresUseCase();
      mockGetYears = MockGetYearsUseCase();
      mockGetFavorites = MockGetFavoritesUseCase();
      mockFolderUseCases = MockFolderUseCases();

      when(() => mockGetSongs.watchSongs(
            sortBy: any(named: 'sortBy'),
            ascending: any(named: 'ascending'),
            limit: any(named: 'limit'),
            excludedFolders: any(named: 'excludedFolders'),
          )).thenAnswer((_) => Stream.value(Right([sampleSong])));
      when(() => mockGetAlbums.watchAlbums())
          .thenAnswer((_) => Stream.value(const Right([])));
      when(() => mockGetArtists.watchArtists())
          .thenAnswer((_) => Stream.value(const Right([])));
      when(() => mockGetGenres.watchGenres())
          .thenAnswer((_) => Stream.value(const Right([])));
      when(() => mockGetYears.watchYears())
          .thenAnswer((_) => Stream.value(const Right([])));
      when(() => mockGetFavorites.watchFavorites())
          .thenAnswer((_) => Stream.value(const Right([])));
      when(() => mockFolderUseCases.getFolderHierarchy())
          .thenAnswer((_) async => const Right([]));
      when(() => mockFolderUseCases.getExcludedFolders())
          .thenAnswer((_) async => const Right([]));
      when(() => mockMusicRepo.getSongById(any()))
          .thenAnswer((_) async => Right(sampleSong));
      when(() => mockMusicRepo.getSongsByIds(any()))
          .thenAnswer((_) async => Right([sampleSong]));
    });

    tearDown(() async {
      await fakeAudioHandler.dispose();
    });

    test('Full smoke journey transitions cleanly', () async {
      // Step 1: Cold start initialization
      final libraryCubit = LibraryCubit(
        getSongsUseCase: mockGetSongs,
        getAlbumsUseCase: mockGetAlbums,
        getArtistsUseCase: mockGetArtists,
        getGenresUseCase: mockGetGenres,
        getYearsUseCase: mockGetYears,
        getFavoritesUseCase: mockGetFavorites,
        toggleFavoriteUseCase: mockToggleFavorite,
        folderUseCases: mockFolderUseCases,
        musicRepository: mockMusicRepo,
      );

      final playerCubit = PlayerCubit(
        audioHandler: fakeAudioHandler,
        repository: mockMusicRepo,
        toggleFavoriteUseCase: mockToggleFavorite,
      );

      expect(playerCubit.state.isPlaying, isFalse);
      expect(playerCubit.state.currentSong, isNull);

      // Step 2: Library load
      await _waitUntil(() => libraryCubit.state.songs.isNotEmpty);

      expect(libraryCubit.state.songs.isNotEmpty, isTrue);
      expect(libraryCubit.state.songs.first.title, 'Flagship Symphony');

      // Step 3: Play song from library
      final selectedSong = libraryCubit.state.songs.first;
      await playerCubit.playSong(selectedSong, queue: libraryCubit.state.songs);
      await _waitUntil(() => playerCubit.state.currentSong != null);

      // Step 4: Verify playback state and currentSong
      expect(playerCubit.state.currentSong?.id, 1);
      expect(playerCubit.state.currentSong?.title, 'Flagship Symphony');

      await libraryCubit.close();
      await playerCubit.close();
    });
  });
}
