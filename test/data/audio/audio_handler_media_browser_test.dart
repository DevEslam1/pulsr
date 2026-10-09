// test/data/audio/audio_handler_media_browser_test.dart
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/genre_item.dart';

import 'handler_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final originalPlatform = JustAudioPlatform.instance;
  late MockMusicRepository repo;
  late MockYtmService ytm;
  PulsrAudioHandler? handler;

  setUp(() {
    JustAudioPlatform.instance = FakeJustAudioPlatform();
    installHandlerChannelStubs();
    repo = MockMusicRepository();
    stubDefaultRepository(repo);
    ytm = MockYtmService();
    stubDefaultYtm(ytm);
  });

  tearDown(() async {
    await handler?.dispose();
    handler = null;
    removeHandlerChannelStubs();
    JustAudioPlatform.instance = originalPlatform;
  });

  group('getChildren', () {
    test('root exposes the browse containers', () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      final children = await handler!.getChildren('root');
      final ids = children.map((c) => c.id).toList();
      expect(ids, containsAll(['songs', 'albums', 'artists', 'recent']));
      expect(children.every((c) => c.playable == false), isTrue);
    });

    test('songs/favorites/downloaded map song rows', () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      when(() => repo.getAllSongs(
            sortBy: any(named: 'sortBy'),
            ascending: any(named: 'ascending'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          )).thenAnswer((_) async => Right([localSong(1), localSong(2)]));
      when(() => repo.getFavorites())
          .thenAnswer((_) async => Right([localSong(3)]));

      expect((await handler!.getChildren('songs')).length, 2);
      expect((await handler!.getChildren('favorites')).length, 1);
      expect((await handler!.getChildren('downloaded')).length, 2);
    });

    test('albums/artists/playlists/genres map their rows', () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      when(() => repo.getAlbums()).thenAnswer((_) async => Right([
            const AlbumsTableData(
                id: 1, title: 'Album', artist: 'Artist', songCount: 3),
          ]));
      when(() => repo.getArtists()).thenAnswer((_) async => Right([
            const ArtistsTableData(
                id: 1, name: 'Artist', songCount: 3, albumCount: 1),
          ]));
      when(() => repo.getPlaylists()).thenAnswer((_) async => Right([
            PlaylistsTableData(
                id: 1,
                name: 'Mix',
                createdAt: DateTime(2020),
                updatedAt: DateTime(2020),
                isSmart: false),
          ]));
      when(() => repo.getGenres()).thenAnswer(
          (_) async => const Right([GenreItem(name: 'Rock', songCount: 4)]));

      expect((await handler!.getChildren('albums')).first.id, 'album_1');
      expect((await handler!.getChildren('artists')).first.id, 'artist_1');
      expect((await handler!.getChildren('playlists')).first.id, 'playlist_1');
      expect((await handler!.getChildren('genres')).first.id, 'genre_Rock');
    });

    test('recent, moods and sound settings', () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      when(() => repo.getRecentlyPlayed(limit: any(named: 'limit')))
          .thenAnswer((_) async => Right([localSong(1)]));

      expect((await handler!.getChildren(AudioService.recentRootId)).length, 1);
      expect((await handler!.getChildren('browse_mood')).length, 4);
      expect((await handler!.getChildren('sound_settings')).length, 3);
      expect((await handler!.getChildren('mood_chill')), isNotNull);
    });

    test('dynamic album/artist/playlist/genre children', () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      when(() => repo.getAlbumSongs(1))
          .thenAnswer((_) async => Right([localSong(1)]));
      when(() => repo.getArtistSongs(1))
          .thenAnswer((_) async => Right([localSong(2)]));
      when(() => repo.getPlaylistSongs(1))
          .thenAnswer((_) async => Right([localSong(3)]));
      when(() => repo.getGenreSongs('Rock'))
          .thenAnswer((_) async => Right([localSong(4)]));

      expect((await handler!.getChildren('album_1')).length, 1);
      expect((await handler!.getChildren('artist_1')).length, 1);
      expect((await handler!.getChildren('playlist_1')).length, 1);
      expect((await handler!.getChildren('genre_Rock')).length, 1);
      expect(await handler!.getChildren('album_notanumber'), isEmpty);
      expect(await handler!.getChildren('unknown_node'), isEmpty);
    });

    test('mood filtering matches keywords', () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      when(() => repo.getAllSongs(
            sortBy: any(named: 'sortBy'),
            ascending: any(named: 'ascending'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          )).thenAnswer((_) async => Right([
            localSong(1, title: 'Chill Vibes', genre: 'ambient'),
            localSong(2, title: 'Heavy Metal', genre: 'rock'),
          ]));

      final chill = await handler!.getChildren('mood_chill');
      expect(chill.map((c) => c.title), contains('Chill Vibes'));
    });
  });

  group('getMediaItem', () {
    test('resolves a numeric song id', () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      when(() => repo.getSongById(1)).thenAnswer((_) async => Right(localSong(1)));
      final item = await handler!.getMediaItem('1');
      expect(item?.title, 'Track 1');
    });

    test('returns null for an unknown numeric id', () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      when(() => repo.getSongById(404))
          .thenAnswer((_) async => const Right(null));
      expect(await handler!.getMediaItem('404'), isNull);
    });

    test('resolves dynamic container ids', () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      when(() => repo.getAlbums()).thenAnswer((_) async => Right([
            const AlbumsTableData(
                id: 1, title: 'Album', artist: 'Artist', songCount: 3),
          ]));
      when(() => repo.getArtists()).thenAnswer((_) async => Right([
            const ArtistsTableData(
                id: 1, name: 'Artist', songCount: 3, albumCount: 1),
          ]));
      when(() => repo.getPlaylists()).thenAnswer((_) async => Right([
            PlaylistsTableData(
                id: 1,
                name: 'Mix',
                createdAt: DateTime(2020),
                updatedAt: DateTime(2020),
                isSmart: false),
          ]));
      when(() => repo.getGenres()).thenAnswer(
          (_) async => const Right([GenreItem(name: 'Rock', songCount: 4)]));

      expect((await handler!.getMediaItem('album_1'))?.title, 'Album');
      expect((await handler!.getMediaItem('artist_1'))?.title, 'Artist');
      expect((await handler!.getMediaItem('playlist_1'))?.title, 'Mix');
      expect((await handler!.getMediaItem('genre_Rock'))?.title, 'Rock');
      expect((await handler!.getMediaItem('songs'))?.id, 'songs');
      expect(await handler!.getMediaItem('album_bad'), isNull);
    });
  });

  group('search', () {
    test('empty query returns nothing', () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      expect(await handler!.search('   '), isEmpty);
    });

    test('library matches are returned as media items', () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      when(() => repo.watchAllSongs(
            sortBy: any(named: 'sortBy'),
            ascending: any(named: 'ascending'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
            searchQuery: any(named: 'searchQuery'),
            excludedFolders: any(named: 'excludedFolders'),
          )).thenAnswer((_) => Stream.value(Right([localSong(1)])));

      final results = await handler!.search('track');
      expect(results.single.title, 'Track 1');
    });
  });

  group('playFromMediaId', () {
    test('plays a queue entry by id', () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      await handler!.loadQueue([localSong(1), localSong(2)], autoPlay: false);
      await handler!.playFromMediaId('2');
      expect(handler!.mediaItem.value?.title, 'Track 2');
    });

    test('plays a library entry by numeric id', () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      when(() => repo.getAllSongs(
            sortBy: any(named: 'sortBy'),
            ascending: any(named: 'ascending'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          )).thenAnswer((_) async => Right([localSong(5), localSong(6)]));
      await handler!.playFromMediaId('6');
      expect(handler!.mediaItem.value?.title, 'Track 6');
    });

    test('creates a transient online row from extras', () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      await handler!.playFromMediaId('dQw4w9WgXcQ', {
        'remoteId': 'dQw4w9WgXcQ',
        'title': 'Never Gonna Give You Up',
        'artist': 'Rick Astley',
        'source': SongSource.youtube,
      });
      expect(handler!.mediaItem.value?.title, 'Never Gonna Give You Up');
    });

    test('falls back to play-all for a container id', () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      when(() => repo.getAllSongs(
            sortBy: any(named: 'sortBy'),
            ascending: any(named: 'ascending'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          )).thenAnswer((_) async => Right([localSong(1)]));
      await handler!.playFromMediaId('songs');
      expect(handler!.mediaItem.value, isNotNull);
    });

    test('toggles sound settings actions', () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      await handler!.playFromMediaId('action_bass_boost');
      await handler!.playFromMediaId('action_virtualizer');
      await handler!.playFromMediaId('action_sleep_timer');
    });
  });

  group('playFromUri', () {
    test('matches a library song by uri', () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      final song = SongsTableData(
        id: 10,
        title: 'Uri Song',
        artist: 'Artist',
        album: 'Album',
        durationMs: 1000,
        path: 'content://media/10',
        uri: 'content://media/10',
        source: SongSource.local,
        isFavorite: false,
        isMissing: false,
        isDownloaded: false,
        playCount: 0,
        lastPositionMs: 0,
      );
      when(() => repo.getAllSongs(
            sortBy: any(named: 'sortBy'),
            ascending: any(named: 'ascending'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          )).thenAnswer((_) async => Right([song]));

      await handler!.playFromUri(Uri.parse('content://media/10'));
      expect(handler!.mediaItem.value?.title, 'Uri Song');
    });

    test('creates a transient row for an unmatched uri', () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      await handler!.playFromUri(Uri.parse('pulsr://video123'));
      expect(handler!.mediaItem.value, isNotNull);
    });

    test('ignores an empty uri', () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      await handler!.playFromUri(Uri.parse(''));
      expect(handler!.mediaItem.value, isNull);
    });
  });

  group('playFromSearch', () {
    test('empty query does nothing', () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      await handler!.playFromSearch('   ');
      expect(handler!.mediaItem.value, isNull);
    });

    test('library matches start a queue', () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      when(() => repo.watchAllSongs(
            sortBy: any(named: 'sortBy'),
            ascending: any(named: 'ascending'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
            searchQuery: any(named: 'searchQuery'),
            excludedFolders: any(named: 'excludedFolders'),
          )).thenAnswer((_) => Stream.value(Right([localSong(1)])));

      await handler!.playFromSearch('track');
      expect(handler!.mediaItem.value?.title, 'Track 1');
    });

    test('voice effects commands route to the DSP toggles', () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      await handler!.playFromSearch('boost the bass');
      await handler!.playFromSearch('surround sound');
      await handler!.playFromSearch('sleep timer');
    });
  });

  group('custom actions', () {
    test('bass boost, virtualizer and sleep timer actions', () async {
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      await handler!.customAction('action_bass_boost', {'enable': true});
      await handler!.customAction('toggleBassBoost', {'enable': false});
      await handler!.customAction('action_virtualizer', {'enable': true});
      await handler!.customAction('virtualizer', {'strength': 0.7});
      // Arm via the bridge first so the manager holds a real player getter;
      // the bare customAction path does not wire one.
      await handler!.playFromMediaId('action_sleep_timer');
      await handler!.customAction('sleepTimer', {'minutes': 5});
      await handler!.customAction('action_sleep_timer');
      await handler!.customAction('switchEqPreset');
      await handler!.customAction('cycleSleepTimer');
    });
  });
}
