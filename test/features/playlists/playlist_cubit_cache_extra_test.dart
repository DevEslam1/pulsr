// PlaylistCubit offline cache + branch coverage: write-side caps (10 custom
// playlists, 200 liked tracks, 50 tracks per playlist), a failing queued save
// task, smart/empty restore paths, post-dispose safety and the compile-time
// gated YTM fetchers being no-ops in this (YTM-disabled) build.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/domain/models/smart_playlist_criteria.dart';
import 'package:pulsr/domain/models/ytm_track.dart';
import 'package:pulsr/domain/usecases/playlist_usecases.dart';
import 'package:pulsr/features/playlists/cubit/playlist_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PlaylistUseCases extends Mock implements PlaylistUseCases {}

class _SmartCriteriaFake extends Fake implements SmartCriteria {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _PlaylistUseCases useCases;

  setUpAll(() {
    registerFallbackValue('');
    registerFallbackValue(<int>[]);
    registerFallbackValue(_SmartCriteriaFake());
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({'smart_playlists_seeded': true});
    useCases = _PlaylistUseCases();
    when(() => useCases.watchPlaylists())
        .thenAnswer((_) => const Stream.empty());
    when(() => useCases.watchPlaylistSongs(any()))
        .thenAnswer((_) => const Stream.empty());
    when(() => useCases.createPlaylist(any(),
            isSmart: any(named: 'isSmart'),
            smartCriteria: any(named: 'smartCriteria')))
        .thenAnswer((_) async => const Right(1));
    when(() => useCases.addSongsToPlaylist(any(), any()))
        .thenAnswer((_) async => const Right(null));
  });

  PlaylistCubit create() => PlaylistCubit(playlistUseCases: useCases);

  Future<void> settle([int ms = 120]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  Future<Map<String, dynamic>> savedCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(PlaylistCubit.onlineCacheKey);
    return jsonDecode(raw!) as Map<String, dynamic>;
  }

  OnlinePlaylistEntry entry(String id, {List<YtmTrack> tracks = const []}) =>
      OnlinePlaylistEntry(id: id, title: id, uploader: 'u', tracks: tracks);

  test('the persisted cache keeps only the 10 most recent custom playlists',
      () async {
    final cubit = create();
    for (var i = 0; i < 12; i++) {
      cubit.restoreCustomPlaylist(entry('c$i'));
    }
    await settle();

    final cache = await savedCache();
    final customs = cache['customPlaylists'] as List;
    expect(customs.length, 10);
    // The 2 oldest (c0, c1) were dropped.
    final ids = customs.map((e) => e['id']).toList();
    expect(ids, isNot(contains('c0')));
    expect(ids, contains('c11'));

    await cubit.close();
  });

  test('the persisted cache caps liked tracks at 200', () async {
    SharedPreferences.setMockInitialValues({
      'smart_playlists_seeded': true,
      PlaylistCubit.onlineCacheKey: jsonEncode({
        'likedTracks': [
          for (var i = 0; i < 250; i++)
            YtmTrack(
                    videoId: 'v$i',
                    title: 'T$i',
                    artist: 'A',
                    duration: const Duration(seconds: 1))
                .toJson(),
        ],
      }),
    });
    final cubit = create();
    await cubit.loadOnlineCacheForTesting();
    expect(cubit.onlineState.likedTracks.length, 250);

    // Any custom mutation triggers a full cache write.
    cubit.restoreCustomPlaylist(entry('c1'));
    await settle();

    final cache = await savedCache();
    final liked = cache['likedTracks'] as List;
    expect(liked.length, 200);
    expect(liked.first['videoId'], 'v0');

    await cubit.close();
  });

  test('the persisted cache caps each playlist at 50 tracks', () async {
    final cubit = create();
    final tracks = [
      for (var i = 0; i < 60; i++)
        YtmTrack(
                videoId: 'v$i',
                title: 'T$i',
                artist: 'A',
                duration: const Duration(seconds: 1)),
    ];
    cubit.restoreCustomPlaylist(entry('big', tracks: tracks));
    await settle();

    final cache = await savedCache();
    final customs = cache['customPlaylists'] as List;
    expect((customs.single['tracks'] as List).length, 50);

    await cubit.close();
  });

  test('a failing queued cache task is swallowed and the queue drains',
      () async {
    final cubit = create();
    cubit.enqueueCacheSaveForTesting(() async => throw Exception('disk full'));
    // Trigger the drain without adding another writer.
    cubit.removeCustomPlaylist('missing');
    await settle();

    expect(cubit.cacheSaveQueueLength, 0);
    // Still usable afterwards.
    cubit.restoreCustomPlaylist(entry('c'));
    expect(cubit.onlineState.customPlaylists.length, 1);

    await cubit.close();
  });

  test('restorePlaylist for a smart playlist skips song insertion', () async {
    final cubit = create();
    final id = await cubit.restorePlaylist('Smart', isSmart: true, songIds: [1]);
    expect(id, 1);
    verifyNever(() => useCases.addSongsToPlaylist(any(), any()));
    await cubit.close();
  });

  test('restorePlaylist with no songs clears the error', () async {
    final cubit = create();
    final id = await cubit.restorePlaylist('Empty');
    expect(id, 1);
    expect(cubit.state.errorMessage, isNull);
    await cubit.close();
  });

  test('after close, online state is the default and mutations are no-ops',
      () async {
    final cubit = create();
    await cubit.close();

    expect(cubit.onlineState.customPlaylists, isEmpty);
    cubit.restoreCustomPlaylist(entry('c'));
    expect(cubit.onlineState.customPlaylists, isEmpty);
  });

  test('YTM fetchers are no-ops while YTM is disabled', () async {
    final cubit = create();
    await cubit.fetchLikedSongsPlaylist();
    await cubit.fetchAccountPlaylists();
    await cubit.fetchOnlinePlaylistByUrl('https://youtube.com/playlist?list=x');

    expect(cubit.onlineState.likedStatus, YtmFetchStatus.idle);
    expect(cubit.onlineState.customPlaylists, isEmpty);
    await cubit.close();
  });
}
