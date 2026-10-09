// Additional PlaylistCubit coverage: CRUD result handling, smart-playlist
// count subscriptions, seeding, the online cache (load/save/validation) and
// custom online playlist bookkeeping. The live YTM network fetchers are gated
// behind a compile-time flag (AppConfig.ytmEnabled == false here) so they are
// intentionally out of scope.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/core/services/ytm_account_service.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/smart_playlist_criteria.dart';
import 'package:pulsr/domain/models/ytm_track.dart';
import 'package:pulsr/domain/usecases/playlist_usecases.dart';
import 'package:pulsr/features/playlists/cubit/playlist_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/test_song_factory.dart';

class _PlaylistUseCases extends Mock implements PlaylistUseCases {}

class _SmartCriteriaFake extends Fake implements SmartCriteria {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _PlaylistUseCases useCases;
  late StreamController<Result<List<PlaylistsTableData>>> playlists;
  late StreamController<List<SongsTableData>> smartSongs;

  PlaylistsTableData playlist(int id, {bool smart = false, String? criteria}) =>
      PlaylistsTableData(
        id: id,
        name: 'Playlist $id',
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
        isSmart: smart,
        smartCriteria: criteria,
      );

  setUpAll(() {
    registerFallbackValue('');
    registerFallbackValue(0);
    registerFallbackValue(false);
    registerFallbackValue(<int>[]);
    registerFallbackValue(const <String>[]);
    registerFallbackValue(_SmartCriteriaFake());
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({'smart_playlists_seeded': true});
    useCases = _PlaylistUseCases();
    playlists = StreamController<Result<List<PlaylistsTableData>>>.broadcast();
    smartSongs = StreamController<List<SongsTableData>>.broadcast();

    when(() => useCases.watchPlaylists())
        .thenAnswer((_) => playlists.stream);
    when(() => useCases.watchSmartPlaylistSongs(any()))
        .thenAnswer((_) => smartSongs.stream);
    when(() => useCases.createPlaylist(any(),
            isSmart: any(named: 'isSmart'),
            smartCriteria: any(named: 'smartCriteria')))
        .thenAnswer((_) async => const Right(1));
    when(() => useCases.renamePlaylist(any(), any()))
        .thenAnswer((_) async => const Right(null));
    when(() => useCases.updateSmartPlaylist(any(), any(), any()))
        .thenAnswer((_) async => const Right(null));
    when(() => useCases.deletePlaylist(any()))
        .thenAnswer((_) async => const Right(null));
    when(() => useCases.addSongToPlaylist(any(), any()))
        .thenAnswer((_) async => const Right(null));
    when(() => useCases.addSongsToPlaylist(any(), any()))
        .thenAnswer((_) async => const Right(null));
    when(() => useCases.removeSongFromPlaylist(any(), any()))
        .thenAnswer((_) async => const Right(null));
    when(() => useCases.reorderPlaylistSongs(any(), any()))
        .thenAnswer((_) async => const Right(null));
    when(() => useCases.watchPlaylistSongs(any()))
        .thenAnswer((_) => const Stream.empty());
    when(() => useCases.seedDefaultSmartPlaylists()).thenAnswer((_) async {});

    addTearDown(() async {
      await playlists.close();
      await smartSongs.close();
    });
  });

  PlaylistCubit create() => PlaylistCubit(playlistUseCases: useCases);

  group('playlist stream', () {
    test('populates playlists and clears loading', () async {
      final cubit = create();
      playlists.add(Right([playlist(1)]));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(cubit.state.playlists.length, 1);
      expect(cubit.state.isLoading, isFalse);
      await cubit.close();
    });

    test('a failed emission surfaces the error message', () async {
      final cubit = create();
      playlists.add(const Left(DatabaseFailure('nope')));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(cubit.state.errorMessage, 'nope');
      await cubit.close();
    });

    test('reloadPlaylists clears the error and resubscribes', () async {
      final cubit = create();
      playlists.add(const Left(DatabaseFailure('nope')));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      cubit.reloadPlaylists();
      expect(cubit.state.errorMessage, isNull);
      verify(() => useCases.watchPlaylists()).called(greaterThanOrEqualTo(2));
      await cubit.close();
    });

    test('seeds default smart playlists once when none exist', () async {
      SharedPreferences.setMockInitialValues({});
      final cubit = create();
      playlists.add(Right([playlist(1)]));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      verify(() => useCases.seedDefaultSmartPlaylists()).called(1);
      await cubit.close();
    });
  });

  group('smart playlist counts', () {
    test('subscribes and tracks counts, then drops stale subscriptions',
        () async {
      final criteria = jsonEncode({
        'rules': [
          {'field': 'playCount', 'operator': 'greaterThan', 'value': '0'}
        ],
        'matchAll': true,
      });
      final cubit = create();
      playlists.add(Right([
        playlist(1, smart: true, criteria: criteria),
      ]));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      verify(() => useCases.watchSmartPlaylistSongs(any())).called(1);

      smartSongs.add([createTestSong(id: 5)]);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(cubit.state.smartPlaylistCounts[1], 1);

      // Delete: stale subscription must be removed.
      await cubit.deletePlaylist(1);
      expect(cubit.state.smartPlaylistCounts.containsKey(1), isFalse);
      await cubit.close();
    });
  });

  group('CRUD', () {
    test('createPlaylist reports success and failure', () async {
      final cubit = create();
      await cubit.createPlaylist('New');
      expect(cubit.state.errorMessage, isNull);

      when(() => useCases.createPlaylist(any(),
              isSmart: any(named: 'isSmart'),
              smartCriteria: any(named: 'smartCriteria')))
          .thenAnswer((_) async => const Left(DatabaseFailure('dup')));
      await cubit.createPlaylist('Dup');
      expect(cubit.state.errorMessage, 'dup');
      await cubit.close();
    });

    test('renamePlaylist reports success and failure', () async {
      final cubit = create();
      await cubit.renamePlaylist(1, 'Renamed');
      expect(cubit.state.errorMessage, isNull);

      when(() => useCases.renamePlaylist(any(), any()))
          .thenAnswer((_) async => const Left(DatabaseFailure('bad')));
      await cubit.renamePlaylist(1, 'x');
      expect(cubit.state.errorMessage, 'bad');
      await cubit.close();
    });

    test('updateSmartPlaylist returns true/false with the result', () async {
      final cubit = create();
      expect(await cubit.updateSmartPlaylist(1, 'n', '{}'), isTrue);
      when(() => useCases.updateSmartPlaylist(any(), any(), any()))
          .thenAnswer((_) async => const Left(DatabaseFailure('bad')));
      expect(await cubit.updateSmartPlaylist(1, 'n', '{}'), isFalse);
      expect(cubit.state.errorMessage, 'bad');
      await cubit.close();
    });

    test('restorePlaylist recreates with songs and returns the new id',
        () async {
      final cubit = create();
      final id = await cubit.restorePlaylist('Mix', songIds: [1, 2]);
      expect(id, 1);
      verify(() => useCases.addSongsToPlaylist(1, [1, 2])).called(1);
      await cubit.close();
    });

    test('restorePlaylist returns null when recreation fails', () async {
      when(() => useCases.createPlaylist(any(),
              isSmart: any(named: 'isSmart'),
              smartCriteria: any(named: 'smartCriteria')))
          .thenAnswer((_) async => const Left(DatabaseFailure('no')));
      final cubit = create();
      expect(await cubit.restorePlaylist('X'), isNull);
      expect(cubit.state.errorMessage, 'no');
      await cubit.close();
    });

    test('song mutation helpers emit on failure', () async {
      final cubit = create();
      when(() => useCases.addSongToPlaylist(any(), any()))
          .thenAnswer((_) async => const Left(DatabaseFailure('a')));
      when(() => useCases.addSongsToPlaylist(any(), any()))
          .thenAnswer((_) async => const Left(DatabaseFailure('b')));
      when(() => useCases.removeSongFromPlaylist(any(), any()))
          .thenAnswer((_) async => const Left(DatabaseFailure('c')));
      when(() => useCases.reorderPlaylistSongs(any(), any()))
          .thenAnswer((_) async => const Left(DatabaseFailure('d')));

      await cubit.addSongToPlaylist(1, 2);
      expect(cubit.state.errorMessage, 'a');
      await cubit.addSongsToPlaylist(1, [2]);
      expect(cubit.state.errorMessage, 'b');
      await cubit.removeSongFromPlaylist(1, 2);
      expect(cubit.state.errorMessage, 'c');
      await cubit.reorderPlaylistSongs(1, [2]);
      expect(cubit.state.errorMessage, 'd');
      await cubit.close();
    });

    test('deletePlaylist failure re-adds smart counts', () async {
      final criteria = jsonEncode({
        'rules': [
          {'field': 'playCount', 'operator': 'greaterThan', 'value': '0'}
        ],
        'matchAll': true,
      });
      final cubit = create();
      playlists.add(Right([playlist(1, smart: true, criteria: criteria)]));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      when(() => useCases.deletePlaylist(any()))
          .thenAnswer((_) async => const Left(DatabaseFailure('blocked')));
      await cubit.deletePlaylist(1);
      expect(cubit.state.errorMessage, 'blocked');
      await cubit.close();
    });

    test('clearError clears the message', () async {
      final cubit = create();
      playlists.add(const Left(DatabaseFailure('x')));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      cubit.clearError();
      expect(cubit.state.errorMessage, isNull);
      await cubit.close();
    });

    test('loadPlaylistSongs subscribes and emits songs', () async {
      final songs = StreamController<Result<List<SongsTableData>>>.broadcast();
      addTearDown(songs.close);
      when(() => useCases.watchPlaylistSongs(1))
          .thenAnswer((_) => songs.stream);
      final cubit = create();
      cubit.loadPlaylistSongs(1);
      songs.add(Right([createTestSong(id: 9)]));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(cubit.state.currentPlaylistSongs.length, 1);
      await cubit.close();
    });
  });

  group('online cache', () {
    test('restores a valid cache', () async {
      final track = const YtmTrack(
          videoId: 'v1', title: 'T', artist: 'A', duration: Duration(seconds: 3));
      final account = const YtmAccountPlaylist(
          playlistId: 'p1', title: 'P', subtitle: 's');
      final custom = OnlinePlaylistEntry(
          id: 'c1', title: 'C', uploader: 'u', tracks: [track]);
      SharedPreferences.setMockInitialValues({
        PlaylistCubit.onlineCacheKey: jsonEncode({
          'likedTracks': [track.toJson()],
          'accountPlaylists': [account.toJson()],
          'customPlaylists': [custom.toJson()],
        }),
      });
      final cubit = create();
      await cubit.loadOnlineCacheForTesting();
      expect(cubit.onlineState.likedTracks.length, 1);
      expect(cubit.onlineState.accountPlaylists.length, 1);
      expect(cubit.onlineState.customPlaylists.length, 1);
      expect(cubit.onlineState.likedStatus, YtmFetchStatus.done);
      await cubit.close();
    });

    test('truncates more than ten custom playlists', () async {
      final customs = [
        for (var i = 0; i < 12; i++)
          OnlinePlaylistEntry(id: 'c$i', title: 'C$i', uploader: '', tracks: const []).toJson(),
      ];
      SharedPreferences.setMockInitialValues({
        PlaylistCubit.onlineCacheKey: jsonEncode({
          'customPlaylists': customs,
        }),
      });
      final cubit = create();
      await cubit.loadOnlineCacheForTesting();
      expect(cubit.onlineState.customPlaylists.length, 10);
      await cubit.close();
    });

    test('truncates a playlist with more than fifty tracks', () async {
      final tracks = [
        for (var i = 0; i < 60; i++)
          YtmTrack(
                  videoId: 'v$i',
                  title: 'T$i',
                  artist: 'A',
                  duration: const Duration(seconds: 1))
              .toJson(),
      ];
      SharedPreferences.setMockInitialValues({
        PlaylistCubit.onlineCacheKey: jsonEncode({
          'customPlaylists': [
            {'id': 'c', 'title': 'C', 'uploader': 'u', 'tracks': tracks},
          ],
        }),
      });
      final cubit = create();
      await cubit.loadOnlineCacheForTesting();
      expect(cubit.onlineState.customPlaylists.single.tracks.length, 50);
      await cubit.close();
    });

    test('a non-object root clears the cache', () async {
      SharedPreferences.setMockInitialValues({
        PlaylistCubit.onlineCacheKey: '[1,2,3]',
      });
      final cubit = create();
      await cubit.loadOnlineCacheForTesting();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(PlaylistCubit.onlineCacheKey), isFalse);
      await cubit.close();
    });

    test('a schema mismatch clears the cache', () async {
      SharedPreferences.setMockInitialValues({
        PlaylistCubit.onlineCacheKey: jsonEncode({
          'likedTracks': [
            {'videoId': 123, 'title': 'T'}
          ],
        }),
      });
      final cubit = create();
      await cubit.loadOnlineCacheForTesting();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(PlaylistCubit.onlineCacheKey), isFalse);
      await cubit.close();
    });

    test('custom playlist removal, restore and clear persist the cache',
        () async {
      final entry = OnlinePlaylistEntry(
          id: 'c1',
          title: 'C',
          uploader: 'u',
          tracks: [
            const YtmTrack(
                videoId: 'v',
                title: 'T',
                artist: 'A',
                duration: Duration(seconds: 1))
          ]);
      final cubit = create();
      cubit.restoreCustomPlaylist(entry);
      expect(cubit.onlineState.customPlaylists.length, 1);
      // Duplicate restore is a no-op.
      cubit.restoreCustomPlaylist(entry);
      expect(cubit.onlineState.customPlaylists.length, 1);

      cubit.removeCustomPlaylist('c1');
      expect(cubit.onlineState.customPlaylists, isEmpty);

      cubit.restoreCustomPlaylist(entry);
      cubit.clearOnlinePlaylists();
      expect(cubit.onlineState.customPlaylists, isEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(PlaylistCubit.onlineCacheKey), isTrue);
      await cubit.close();
    });
  });
}
