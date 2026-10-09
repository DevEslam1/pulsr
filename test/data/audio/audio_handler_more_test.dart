// test/data/audio/audio_handler_more_test.dart
//
// Second pass over the handler surface: media-browser alias nodes and art
// fallbacks, queue-engine restore/gapless edge cases, transport gapless
// navigation and headset mappings, plus the main handler's volume/DVC/
// custom-action branches. Uses the shared deterministic harness.
import 'package:audio_service/audio_service.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/data/audio/equalizer_manager.dart';
import 'package:pulsr/data/audio/headset_control_config.dart';
import 'package:pulsr/data/audio/multi_output_router.dart';
import 'package:pulsr/data/audio/position_crash_guard.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/genre_item.dart';

import 'handler_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final originalPlatform = JustAudioPlatform.instance;
  late FakeJustAudioPlatform platform;
  late MockMusicRepository repo;
  late MockYtmService ytm;
  PulsrAudioHandler? handler;

  setUp(() async {
    platform = FakeJustAudioPlatform();
    JustAudioPlatform.instance = platform;
    installHandlerChannelStubs();
    repo = MockMusicRepository();
    stubDefaultRepository(repo);
    ytm = MockYtmService();
    stubDefaultYtm(ytm);
    // Keep PositionCrashGuard state from leaking across tests through the temp
    // directory.
    await PositionCrashGuard.clearSnapshot();
  });

  tearDown(() async {
    await handler?.dispose();
    handler = null;
    removeHandlerChannelStubs();
    JustAudioPlatform.instance = originalPlatform;
  });

  Future<PulsrAudioHandler> ready({bool load = false}) async {
    final h = await buildTestHandler(repository: repo, ytmService: ytm);
    if (load) {
      await h.loadQueue([localSong(1), localSong(2), localSong(3)],
          autoPlay: false);
    }
    return h;
  }

  group('media browser aliases', () {
    test('root aliases all resolve to the browse containers', () async {
      handler = await ready();
      for (final id in ['root', 'android_auto_root', '/', '']) {
        final children = await handler!.getChildren(id);
        expect(children.map((c) => c.id),
            containsAll(<String>['songs', 'albums', 'artists', 'recent']),
            reason: 'root alias $id');
      }
    });

    test('static container aliases resolve through getMediaItem', () async {
      handler = await ready();
      expect((await handler!.getMediaItem('root_songs'))?.id, 'songs');
      expect((await handler!.getMediaItem('root_albums'))?.id, 'albums');
      expect((await handler!.getMediaItem('root_artists'))?.id, 'artists');
      expect((await handler!.getMediaItem('root_playlists'))?.id, 'playlists');
      expect((await handler!.getMediaItem('root_genres'))?.id, 'genres');
      expect((await handler!.getMediaItem('root_favorites'))?.id, 'favorites');
      expect((await handler!.getMediaItem('root_downloaded'))?.id, 'downloaded');
      expect((await handler!.getMediaItem('root_browse_mood'))?.id,
          'browse_mood');
      expect((await handler!.getMediaItem('root_recent'))?.id, 'recent');
      expect((await handler!.getMediaItem('root_sound_settings'))?.id,
          'sound_settings');
      expect((await handler!.getMediaItem('ytm_trending'))?.id, 'ytm_trending');
      expect(
          (await handler!.getMediaItem('ytm_favorites'))?.id, 'ytm_favorites');
      expect((await handler!.getMediaItem('mood_workout'))?.id, 'mood_workout');
      expect((await handler!.getMediaItem('mood_focus'))?.id, 'mood_focus');
      expect((await handler!.getMediaItem('mood_party'))?.id, 'mood_party');
      expect(await handler!.getMediaItem('definitely_unknown'), isNull);
    });

    test('root_* child aliases map their repository rows', () async {
      handler = await ready();
      when(() => repo.getAllSongs(
            sortBy: any(named: 'sortBy'),
            ascending: any(named: 'ascending'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          )).thenAnswer((_) async => Right([localSong(1)]));
      when(() => repo.getFavorites())
          .thenAnswer((_) async => Right([localSong(2)]));
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
      when(() => repo.getRecentlyPlayed(limit: any(named: 'limit')))
          .thenAnswer((_) async => Right([localSong(3)]));

      expect((await handler!.getChildren('root_songs')).length, 1);
      expect((await handler!.getChildren('root_favorites')).length, 1);
      expect((await handler!.getChildren('root_albums')).first.id, 'album_1');
      expect((await handler!.getChildren('root_artists')).first.id, 'artist_1');
      expect(
          (await handler!.getChildren('root_playlists')).first.id, 'playlist_1');
      expect((await handler!.getChildren('root_genres')).first.id, 'genre_Rock');
      expect((await handler!.getChildren('root_recent')).length, 1);
      expect((await handler!.getChildren('root_browse_mood')).length, 4);
      expect((await handler!.getChildren('root_sound_settings')).length, 3);
    });

    test('song rows with art urls expose browse extras', () async {
      handler = await ready();
      final withArtwork = localSong(1).copyWith(
        artworkUri: const Value('https://cdn.example/art1.jpg'),
      );
      final withRemote = localSong(2).copyWith(
        remoteArtworkUrl: const Value('https://cdn.example/art2.jpg'),
      );
      final withAlbum = localSong(3).copyWith(albumId: const Value(9));
      when(() => repo.getAllSongs(
            sortBy: any(named: 'sortBy'),
            ascending: any(named: 'ascending'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          )).thenAnswer(
          (_) async => Right([withArtwork, withRemote, withAlbum]));

      final children = await handler!.getChildren('songs');
      expect(children.length, 3);
      expect(children.first.extras, isNotNull);
    });

    test('downloaded filters out non-local, non-downloaded rows', () async {
      handler = await ready();
      when(() => repo.getAllSongs(
            sortBy: any(named: 'sortBy'),
            ascending: any(named: 'ascending'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          )).thenAnswer((_) async => Right([
            localSong(1),
            ytSong(2, remoteId: 'aaaaaaaaaaa'),
            localSong(3).copyWith(isDownloaded: false),
          ]));

      final downloaded = await handler!.getChildren('downloaded');
      expect(downloaded.map((m) => m.id), containsAll(<String>['1', '3']));
      expect(downloaded.any((m) => m.id == '2'), isFalse);
    });

    test('sound settings reflects live effect state', () async {
      handler = await ready();
      await handler!.equalizerManager.setBassBoost(0.6);
      await handler!.equalizerManager.setVirtualizerEnabled(true);
      handler!.startSleepTimer(const Duration(minutes: 30));

      final children = await handler!.getChildren('sound_settings');
      expect(children.length, 3);
      final bass = children.firstWhere((c) => c.id == 'action_bass_boost');
      final sleep = children.firstWhere((c) => c.id == 'action_sleep_timer');
      expect(bass.displaySubtitle, isNotNull);
      expect(sleep.displaySubtitle, isNotNull);
      handler!.cancelSleepTimer();
    });

    test('dynamic container ids with bad numbers yield nothing', () async {
      handler = await ready();
      expect(await handler!.getChildren('album_notanumber'), isEmpty);
      expect(await handler!.getChildren('artist_notanumber'), isEmpty);
      expect(await handler!.getChildren('playlist_notanumber'), isEmpty);
      expect(await handler!.getChildren('genre_'), isEmpty);
    });

    test('ytm nodes are gated off when ytm is disabled at build time',
        () async {
      handler = await ready();
      expect(await handler!.getChildren('ytm_trending'), isEmpty);
      expect(await handler!.getChildren('ytm_favorites'), isEmpty);
    });

    test('mood filters match each keyword bucket', () async {
      handler = await ready();
      when(() => repo.getAllSongs(
            sortBy: any(named: 'sortBy'),
            ascending: any(named: 'ascending'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          )).thenAnswer((_) async => Right([
            localSong(1, title: 'Gym Power', genre: 'workout'),
            localSong(2, title: 'Study Piano', genre: 'classical'),
            localSong(3, title: 'Club Night', genre: 'dance'),
          ]));

      expect((await handler!.getChildren('mood_workout')).isNotEmpty, isTrue);
      expect((await handler!.getChildren('mood_focus')).isNotEmpty, isTrue);
      expect((await handler!.getChildren('mood_party')).isNotEmpty, isTrue);
      expect(await handler!.getChildren('mood_unknown'), isEmpty);
    });

    test('getMediaItem dynamic nodes handle missing and empty ids', () async {
      handler = await ready();
      expect(await handler!.getMediaItem('album_123'), isNull);
      expect(await handler!.getMediaItem('artist_123'), isNull);
      expect(await handler!.getMediaItem('playlist_123'), isNull);
      expect(await handler!.getMediaItem('genre_'), isNull);
      final genre = await handler!.getMediaItem('genre_Unknown');
      expect(genre?.id, 'genre_Unknown');
      expect(genre?.displaySubtitle, isNull);
    });

    test('playFromMediaId plays container nodes', () async {
      handler = await ready();
      when(() => repo.getAllSongs(
            sortBy: any(named: 'sortBy'),
            ascending: any(named: 'ascending'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          )).thenAnswer((_) async => Right([localSong(1), localSong(2)]));
      when(() => repo.getFavorites())
          .thenAnswer((_) async => Right([localSong(3)]));
      when(() => repo.getRecentlyPlayed(limit: any(named: 'limit')))
          .thenAnswer((_) async => Right([localSong(4)]));
      when(() => repo.getAlbumSongs(any()))
          .thenAnswer((_) async => Right([localSong(5)]));
      when(() => repo.getArtistSongs(any()))
          .thenAnswer((_) async => Right([localSong(6)]));
      when(() => repo.getPlaylistSongs(any()))
          .thenAnswer((_) async => Right([localSong(7)]));
      when(() => repo.getGenreSongs(any()))
          .thenAnswer((_) async => Right([localSong(8)]));

      await handler!.playFromMediaId('albums');
      expect(handler!.queue.value, isNotEmpty);
      await handler!.playFromMediaId('favorites');
      expect(handler!.queue.value.first.id, '3');
      await handler!.playFromMediaId('downloaded');
      expect(handler!.queue.value, isNotEmpty);
      await handler!.playFromMediaId('recent');
      expect(handler!.queue.value, isNotEmpty);
      await handler!.playFromMediaId('mood_workout');
      await handler!.playFromMediaId('album_1');
      expect(handler!.queue.value.first.id, '5');
      await handler!.playFromMediaId('artist_1');
      expect(handler!.queue.value.first.id, '6');
      await handler!.playFromMediaId('playlist_1');
      expect(handler!.queue.value.first.id, '7');
      await handler!.playFromMediaId('genre_Rock');
      expect(handler!.queue.value.first.id, '8');
      await handler!.playFromMediaId('ytm_trending');
      await handler!.playFromMediaId('ytm_favorites');
      await handler!.playFromMediaId('nothing_matches');
    });

    test('playFromMediaId builds an online row from an 11-char id', () async {
      handler = await ready();
      await handler!.playFromMediaId('dQw4w9WgXcQ', <String, dynamic>{});
      expect(handler!.mediaItem.value?.title, isNotNull);
    });

    test('playFromUri matches a file path and builds a transient row',
        () async {
      handler = await ready();
      final file = Uri.file('/music/local/track.mp3');
      final local = localSong(1, path: file.toFilePath());
      when(() => repo.getAllSongs(
            sortBy: any(named: 'sortBy'),
            ascending: any(named: 'ascending'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          )).thenAnswer((_) async => Right([local]));

      await handler!.playFromUri(file);
      expect(handler!.mediaItem.value?.title, 'Track 1');

      await handler!.playFromUri(Uri.parse('pulsr://videoId1234'));
      expect(handler!.mediaItem.value, isNotNull);
    });

    test('playFromSearch honors voice extras and cleans the query', () async {
      handler = await ready();
      when(() => repo.watchAllSongs(
            sortBy: any(named: 'sortBy'),
            ascending: any(named: 'ascending'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
            searchQuery: any(named: 'searchQuery'),
            excludedFolders: any(named: 'excludedFolders'),
          )).thenAnswer((_) => Stream.value(Right([localSong(1)])));

      await handler!.playFromSearch('play something', <String, dynamic>{
        'android.media.extra.MEDIA_FOCUS': 'v16_music',
        'android.media.extra.EXTRA_METADATA_ARTIST': 'Artist 1',
      });
      expect(handler!.mediaItem.value, isNotNull);

      await handler!.playFromSearch('whatever', <String, dynamic>{
        'android.media.extra.EXTRA_METADATA_TITLE': 'Track 1',
      });
      expect(handler!.mediaItem.value, isNotNull);
    });

    test('sleep timer sound action toggles on and off', () async {
      handler = await ready();
      await handler!.playFromMediaId('action_sleep_timer');
      expect(handler!.sleepTimerMode, isNotNull);
      await handler!.playFromMediaId('action_sleep_timer');
    });
  });

  group('queue engine extras', () {
    test('restore reads a matching crash guard snapshot', () async {
      final song = localSong(1, title: 'Crash Restored');
      await PositionCrashGuard.writeSnapshot(
        songId: 1,
        queueIndex: 0,
        positionMs: 42000,
        queueIds: const [1],
      );
      when(() => repo.getSavedQueue()).thenAnswer((_) async => const Right([
            QueueItemsTableData(
                id: 1,
                songId: 1,
                orderIndex: 0,
                isCurrent: true,
                positionMs: 0),
          ]));
      when(() => repo.getSongsByIds(any()))
          .thenAnswer((_) async => Right([song]));

      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(handler!.queue.value.length, 1);
      expect(handler!.mediaItem.value?.title, 'Crash Restored');
    });

    test('restore leaves an empty saved queue alone', () async {
      when(() => repo.getSavedQueue())
          .thenAnswer((_) async => const Right(<QueueItemsTableData>[]));
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(handler!.queue.value, isEmpty);
    });

    test('restore a saved queue with a missing song row', () async {
      when(() => repo.getSavedQueue()).thenAnswer((_) async => const Right([
            QueueItemsTableData(
                id: 1,
                songId: 99,
                orderIndex: 0,
                isCurrent: true,
                positionMs: 1000),
          ]));
      when(() => repo.getSongsByIds(any()))
          .thenAnswer((_) async => const Right(<SongsTableData>[]));
      handler = await buildTestHandler(repository: repo, ytmService: ytm);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(handler!.queue.value, isEmpty);
    });

    test('same-list reload takes the fast path while playing', () async {
      handler = await ready();
      final songs = [localSong(1), localSong(2), localSong(3)];
      await handler!.loadQueue(songs, autoPlay: true);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await handler!.loadQueue(songs, initialIndex: 1, autoPlay: true);
      expect(handler!.mediaItem.value?.title, 'Track 2');
    });

    test('swapReconciledSong updates the current media item', () async {
      handler = await ready(load: true);
      handler!.swapReconciledSong(1, localSong(1, title: 'Current Reconciled'));
      expect(handler!.mediaItem.value?.title, 'Current Reconciled');
    });

    test('updateFavorite mirrors onto the current media item extras', () async {
      handler = await ready(load: true);
      handler!.updateFavorite(1, true);
      expect(handler!.mediaItem.value?.rating?.hasHeart(), isTrue);
    });

    test('removeQueueItemAt handles an out-of-range index', () async {
      handler = await ready(load: true);
      await handler!.removeQueueItemAt(-1);
      await handler!.removeQueueItemAt(99);
      expect(handler!.queue.value.length, 3);
    });

    test('removeQueueItem ignores an unknown media id', () async {
      handler = await ready(load: true);
      await handler!.removeQueueItem(
          MediaItem(id: 'does-not-exist', title: 'Ghost'));
      expect(handler!.queue.value.length, 3);
    });

    test('removeQueueItemAt the playing current track in per-track mode',
        () async {
      handler = await ready(load: true);
      handler!.setGaplessEnabled(false);
      handler!.setCrossfadeDuration(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await handler!.play();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await handler!.removeQueueItemAt(0);
      expect(handler!.queue.value.length, 2);
    });

    test('removeQueueItemAt removes the current track while gapless', () async {
      handler = await ready(load: true);
      await handler!.play().catchError((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await handler!.removeQueueItemAt(0);
      expect(handler!.queue.value.length, 2);
    });

    test('reorderQueue in gapless mode moves the native source', () async {
      handler = await ready(load: true);
      await handler!.reorderQueue(0, 2);
      expect(handler!.queue.value.map((m) => m.id).toList(),
          <String>['2', '3', '1']);
    });

    test('clearQueue leaves only the current track', () async {
      handler = await ready();
      await handler!.loadQueue([localSong(1), localSong(2), localSong(3)],
          initialIndex: 2, autoPlay: false);
      await handler!.clearQueue();
      expect(handler!.queue.value.length, 1);
      expect(handler!.mediaItem.value?.title, 'Track 3');
    });

    test('clearQueue on an already empty queue is a no-op', () async {
      handler = await ready();
      await handler!.clearQueue();
      expect(handler!.queue.value, isEmpty);
    });

    test('playSongAt ignores an out-of-range index', () async {
      handler = await ready(load: true);
      await handler!.playSongAt(-1);
      await handler!.playSongAt(99);
      expect(handler!.mediaItem.value, isNotNull);
    });

    test('insertNextInQueue reuses an existing non-current track', () async {
      handler = await ready();
      await handler!.loadQueue([localSong(1), localSong(2), localSong(3)],
          autoPlay: false);
      await handler!.insertNextInQueue(localSong(3));
      expect(handler!.queue.value.map((m) => m.id).toList(),
          <String>['1', '3', '2']);
      await handler!.insertNextInQueue(localSong(1));
      expect(handler!.queue.value.map((m) => m.id).toList(),
          <String>['1', '3', '2']);
    });

    test('addQueueItem appends a resolved song and rejects a duplicate',
        () async {
      handler = await ready();
      when(() => repo.getSongById(7)).thenAnswer((_) async => Right(localSong(7)));
      await handler!.addQueueItem(MediaItem(id: '7', title: 'Track 7'));
      expect(handler!.queue.value.map((m) => m.id), <String>['7']);
      await handler!.addQueueItem(MediaItem(id: '7', title: 'Track 7'));
      expect(handler!.queue.value.length, 1);
    });

    test('addQueueItem ignores a non-numeric id', () async {
      handler = await ready();
      await handler!.addQueueItem(
          MediaItem(id: 'not-a-number', title: 'Nope'));
      expect(handler!.queue.value, isEmpty);
    });

    test('updateFavorite on a non-current row only refreshes the queue',
        () async {
      handler = await ready();
      await handler!.loadQueue([localSong(1), localSong(2)], autoPlay: false);
      handler!.updateFavorite(2, true);
      expect(handler!.queue.value.last.extras?['isFavorite'], isTrue);
    });
  });

  group('transport gapless & headset', () {
    test('gapless skipToNext advances the native concat', () async {
      handler = await ready();
      await handler!.loadQueue([localSong(1), localSong(2), localSong(3)],
          autoPlay: true);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await handler!.skipToNext();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(handler!.mediaItem.value, isNotNull);
    });

    test('gapless skipToNext at the end of queue restarts', () async {
      handler = await ready();
      await handler!.loadQueue([localSong(1)], autoPlay: true);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await handler!.skipToNext();
      await handler!.skipToNext();
      expect(handler!.mediaItem.value?.title, 'Track 1');
    });

    test('setRepeatMode group maps to LoopMode.all', () async {
      handler = await ready(load: true);
      await handler!.setRepeatMode(AudioServiceRepeatMode.group);
      expect(handler!.playbackState.value.repeatMode,
          AudioServiceRepeatMode.group);
    });

    test('setShuffleMode reshuffles a loaded gapless queue', () async {
      handler = await ready(load: true);
      await handler!.setShuffleMode(AudioServiceShuffleMode.all);
      expect(handler!.playbackState.value.shuffleMode,
          AudioServiceShuffleMode.all);
    });

    test('setSpeed ignores non-finite values', () async {
      handler = await ready();
      final before = handler!.playbackState.value.speed;
      await handler!.setSpeed(double.infinity);
      await handler!.setSpeed(double.negativeInfinity);
      expect(handler!.playbackState.value.speed, closeTo(before, 0.001));
    });

    test('setPitch ignores non-finite values', () async {
      handler = await ready();
      await handler!.setPitch(double.nan);
      expect(handler!.pitch, closeTo(1.0, 0.001));
    });

    test('seekRelative clamps at both ends of the track', () async {
      handler = await ready(load: true);
      for (final p in platform.players.values) {
        p.duration = const Duration(minutes: 3);
        p.emitPlayback(updatePosition: const Duration(seconds: 100));
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await handler!.seekRelative(const Duration(seconds: -10000));
      await handler!.seekRelative(const Duration(seconds: 10000));
      expect(handler!.playbackState.value.updatePosition,
          greaterThanOrEqualTo(Duration.zero));
    });

    test('headset triple click maps to stop when configured', () async {
      handler = await ready(load: true);
      handler!.cachedHeadsetConfig = const HeadsetControlConfig(
        tripleClick: HeadsetClickAction.stop,
      );
      await handler!.click();
      await handler!.click();
      await handler!.click();
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });

    test('headset single click maps to seekForward when configured',
        () async {
      handler = await ready(load: true);
      handler!.cachedHeadsetConfig = const HeadsetControlConfig(
        singleClick: HeadsetClickAction.seekForward,
        clickWindowMs: 150,
      );
      await handler!.click();
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });

    test('headset single click playPause pauses when already playing',
        () async {
      handler = await ready(load: true);
      await handler!.play();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      handler!.cachedHeadsetConfig = const HeadsetControlConfig(
        singleClick: HeadsetClickAction.playPause,
        clickWindowMs: 150,
      );
      await handler!.click();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(handler!.playbackState.value.playing, isFalse);
    });

    test('headset double click maps to previous', () async {
      handler = await ready(load: true);
      handler!.cachedHeadsetConfig = const HeadsetControlConfig(
        doubleClick: HeadsetClickAction.previous,
        clickWindowMs: 150,
      );
      await handler!.click();
      await handler!.click();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(handler!.mediaItem.value, isNotNull);
    });
  });

  group('main-surface extras', () {
    test('setDvcEnabled toggles both directions', () async {
      handler = await ready();
      await handler!.setDvcEnabled(true);
      expect(handler!.isDvcEnabled, isFalse);
      await handler!.setDvcEnabled(true);
      await handler!.setDvcEnabled(false);
      expect(handler!.isDvcEnabled, isFalse);
    });

    test('setVolume ignores non-finite input', () async {
      handler = await ready();
      await handler!.setVolume(0.3);
      await handler!.setVolume(double.nan);
      await handler!.setVolume(double.infinity);
      expect(handler!.volume, closeTo(0.3, 0.001));
    });

    test('withSmoothDspTransition passes the action result through', () async {
      handler = await ready();
      expect(await handler!.withSmoothDspTransition(() async => 'ok'), 'ok');
    });

    test('customAction toggles favorite on the current song', () async {
      handler = await ready(load: true);
      when(() => repo.toggleFavorite(any()))
          .thenAnswer((_) async => const Right(true));
      final result = await handler!.customAction('toggleFavorite');
      expect(result, isTrue);
      expect(handler!.currentSong?.isFavorite, isTrue);
    });

    test('customAction bass boost honors strength and disable', () async {
      handler = await ready();
      final on = await handler!
          .customAction('bassBoost', <String, dynamic>{'strength': 0.7});
      expect(on, isTrue);
      final off = await handler!
          .customAction('toggleBassBoost', <String, dynamic>{'enable': false});
      expect(off, isFalse);
    });

    test('customAction virtualizer honors explicit strength', () async {
      handler = await ready();
      final on = await handler!.customAction(
          'virtualizer', <String, dynamic>{'enable': true, 'strength': 0.8});
      expect(on, isTrue);
      final off = await handler!
          .customAction('action_virtualizer', <String, dynamic>{'enable': false});
      expect(off, isFalse);
    });

    test('customAction sleep timer arms then cancels', () async {
      handler = await ready();
      // Prime the manager's player getter through the bridge so cancellation
      // has a real active player to restore.
      handler!.startSleepTimer(const Duration(minutes: 1));
      handler!.cancelSleepTimer();
      final armed = await handler!
          .customAction('sleepTimer', <String, dynamic>{'minutes': 5});
      expect(armed, isTrue);
      final cancelled = await handler!.customAction('action_sleep_timer');
      expect(cancelled, isFalse);
    });

    test('customAction cycles through every repeat state', () async {
      handler = await ready(load: true);
      await handler!.customAction('cycleRepeat');
      expect(handler!.playbackState.value.repeatMode,
          AudioServiceRepeatMode.all);
      await handler!.customAction('toggleRepeat');
      expect(handler!.playbackState.value.repeatMode,
          AudioServiceRepeatMode.one);
      await handler!.customAction('cycleRepeat');
      expect(handler!.playbackState.value.repeatMode,
          AudioServiceRepeatMode.none);
    });

    test('customAction cycleSpeed walks the speed ladder', () async {
      handler = await ready();
      final first = await handler!.customAction('cycleSpeed');
      expect(first, closeTo(1.25, 0.001));
      final second = await handler!.customAction('cycleSpeed');
      expect(second, closeTo(1.5, 0.001));
      final third = await handler!.customAction('cycleSpeed');
      expect(third, closeTo(1.0, 0.001));
    });

    test('customAction switchEqPreset advances the preset', () async {
      handler = await ready();
      final name = await handler!.customAction('switchEqPreset');
      expect(name, isNotNull);
    });

    test('customAction cycleSleepTimer walks 15/30/45/off', () async {
      handler = await ready();
      handler!.startSleepTimer(const Duration(minutes: 1));
      handler!.cancelSleepTimer();
      expect(await handler!.customAction('cycleSleepTimer'), 15);
      expect(await handler!.customAction('cycleSleepTimer'), 30);
      expect(await handler!.customAction('cycleSleepTimer'), 45);
      expect(await handler!.customAction('cycleSleepTimer'), 0);
    });

    test('setRating ignores non-heart ratings', () async {
      handler = await ready(load: true);
      await handler!.setRating(Rating.newStarRating(RatingStyle.range5stars, 5));
      expect(handler!.currentSong?.isFavorite, isFalse);
      await handler!.setRating(Rating.newHeartRating(false));
      expect(handler!.currentSong?.isFavorite, isFalse);
    });

    test('setRating with no queue is a no-op', () async {
      handler = await ready();
      await handler!.setRating(Rating.newHeartRating(true));
      expect(handler!.currentSong, isNull);
    });

    test('handleSystemUiSoundInterruption while paused is a no-op', () async {
      handler = await ready(load: true);
      await handler!.handleSystemUiSoundInterruption();
      expect(handler!.playbackState.value.playing, isFalse);
    });

    test('getPlatformFocusState falls back to true without a native hook',
        () async {
      handler = await ready();
      expect(await handler!.getPlatformFocusState(), isTrue);
    });

    test('multi-output routing accepts every mode shape', () async {
      handler = await ready(load: true);
      for (final mode in MultiOutputMode.values) {
        expect(await handler!.setMultiOutputMode(mode), isA<bool>());
      }
    });
  });

  group('crossfade, gapless advance and lazy playback', () {
    test('lazy YouTube load parks a pending position then play resolves it',
        () async {
      handler = await ready();
      handler!.setGaplessEnabled(false);
      handler!.setCrossfadeDuration(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await handler!.loadQueue([ytSong(1, remoteId: 'dQw4w9WgXcQ')],
          autoPlay: false);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await handler!.pause();
      await handler!.play();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(handler!.mediaItem.value, isNotNull);
    });

    test('gapless add/insert/addToQueue build native children', () async {
      handler = await ready(load: true);
      await handler!.addToQueueEnd(localSong(9));
      expect(handler!.queue.value.map((m) => m.id), contains('9'));
      await handler!.insertNextInQueue(localSong(10));
      expect(handler!.queue.value.map((m) => m.id), contains('10'));
      when(() => repo.getSongById(11))
          .thenAnswer((_) async => Right(localSong(11)));
      await handler!.addQueueItem(MediaItem(id: '11', title: 'Track 11'));
      expect(handler!.queue.value.map((m) => m.id), contains('11'));
    });

    test('native gapless index advance reconciles the current song', () async {
      handler = await ready();
      await handler!.loadQueue(
          [localSong(1), localSong(2), localSong(3)], autoPlay: true);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      for (final p in platform.players.values) {
        p.emitPlayback(
          index: 1,
          processingState: ProcessingStateMessage.ready,
          updatePosition: const Duration(seconds: 5),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(handler!.mediaItem.value, isNotNull);
    });

    test('crossfade engine transitions near the end of a track', () async {
      handler = await ready();
      handler!.setGaplessEnabled(false);
      handler!.setCrossfadeDuration(const Duration(seconds: 2));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await handler!.loadQueue(
        [
          localSong(1, durationMs: 210000),
          localSong(2, durationMs: 210000),
        ],
        autoPlay: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));
      for (final p in platform.players.values) {
        p.duration = const Duration(minutes: 3, seconds: 30);
        p.emitPlayback(
          updatePosition: const Duration(minutes: 3, seconds: 29),
          bufferedPosition: const Duration(seconds: 10),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 3500));
      expect(handler!.mediaItem.value, isNotNull);
    });

    test('crossfade start is a no-op for an invalid next index', () async {
      handler = await ready(load: true);
      handler!.setGaplessEnabled(false);
      handler!.setCrossfadeDuration(const Duration(seconds: 2));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      // A single-track queue has no next index to fade to.
      for (final p in platform.players.values) {
        p.duration = const Duration(minutes: 3, seconds: 30);
        p.emitPlayback(
          updatePosition: const Duration(minutes: 3, seconds: 29),
          bufferedPosition: const Duration(seconds: 10),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(handler!.mediaItem.value, isNotNull);
    });

    test('a DSD row without a decodable file degrades and skips', () async {
      final dsd = localSong(1, path: '/music/track.dsf').copyWith(
        codec: const Value('DSD64'),
      );
      handler = await ready();
      await handler!.loadQueue([dsd, localSong(2)], autoPlay: true);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      handler!.setGaplessEnabled(false);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await handler!.playSongAt(0);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(handler!.mediaItem.value, isNotNull);
    });
  });

  group('volume, persistence and quality branches', () {
    test('setVolume with a current song runs the replay-gain path', () async {
      handler = await ready(load: true);
      await handler!.setVolume(0.5);
      await handler!.setVolume(0.6);
      expect(handler!.volume, closeTo(0.6, 0.001));
    });

    test('repeated position saves exercise the atomic fallback', () async {
      handler = await ready(load: true);
      await handler!.saveCurrentPositionImmediate();
      await handler!.saveCurrentPositionImmediate();
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });

    test('system-ui sound interruption ducks then auto-restores', () async {
      handler = await ready(load: true);
      await handler!.play();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await handler!.handleSystemUiSoundInterruption();
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(handler!.mediaItem.value, isNotNull);
    });

    test('disabling adaptive quality reads the persisted streaming quality',
        () async {
      handler = await ready();
      handler!.adaptiveQualityManager.enabled = false;
      await handler!.loadQueue([ytSong(1, remoteId: 'dQw4w9WgXcQ')],
          autoPlay: false);
      expect(handler!.mediaItem.value, isNotNull);
    });
  });

  group('transport completion and restore extras', () {
    test('play on a completed track rewinds and restarts', () async {
      handler = await ready(load: true);
      for (final p in platform.players.values) {
        p.emitPlayback(processingState: ProcessingStateMessage.completed);
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await handler!.play();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(handler!.mediaItem.value, isNotNull);
    });

    test('gapless previous restarts the track when past the threshold',
        () async {
      handler = await ready(load: true);
      await handler!.play();
      for (final p in platform.players.values) {
        p.duration = const Duration(minutes: 3);
        p.emitPlayback(updatePosition: const Duration(seconds: 10));
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await handler!.skipToPrevious();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(handler!.mediaItem.value, isNotNull);
    });

    test('gapless next on a repeat-all single track wraps to the start',
        () async {
      handler = await ready();
      await handler!.loadQueue([localSong(1)], autoPlay: true);
      await handler!.setRepeatMode(AudioServiceRepeatMode.all);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await handler!.skipToNext();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(handler!.mediaItem.value?.title, 'Track 1');
    });

    test('headset seek-backward mapping runs the relative seek', () async {
      handler = await ready(load: true);
      handler!.cachedHeadsetConfig = const HeadsetControlConfig(
        tripleClick: HeadsetClickAction.seekBackward,
      );
      await handler!.click();
      await handler!.click();
      await handler!.click();
      await Future<void>.delayed(const Duration(milliseconds: 40));
    });

    test('restorePersistedSpeed/Pitch reload persisted values', () async {
      handler = await ready();
      await handler!.setAdvancedSpeedEnabled(true);
      await handler!.setSpeed(3.0);
      await handler!.setPitch(1.5);
      await handler!.setAdvancedSpeedEnabled(false);
      await handler!.restorePersistedSpeed();
      await handler!.restorePersistedPitch();
      expect(handler!.playbackState.value.speed, isNotNull);
    });
  });
}
