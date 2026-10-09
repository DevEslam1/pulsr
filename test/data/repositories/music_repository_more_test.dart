// test/data/repositories/music_repository_more_test.dart
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/repositories/music_repository.dart';
import 'package:pulsr/domain/models/ytm_track.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  late AppDatabase db;
  late MusicRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = MusicRepository(db);
  });

  tearDown(() async {
    await db.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
  });

  Future<void> insertSong({
    required int id,
    required String title,
    String path = '',
    String artist = 'Artist',
    String album = 'Album',
    int? artistIdValue,
    int? albumId,
    String? genre,
    int? year,
    int playCount = 0,
    int? lastPlayed,
    bool isFavorite = false,
    bool isMissing = false,
    bool isDownloaded = false,
    int? durationMs,
    int? dateAdded,
    String source = SongSource.local,
    String? remoteId,
    int? cueStartMs,
    String? cueFile,
    String? uri,
    int? lastPositionMs,
  }) async {
    await db.into(db.songsTable).insert(SongsTableCompanion.insert(
          id: Value(id),
          title: title,
          path: path.isEmpty ? '/music/song_$id.mp3' : path,
          artist: Value(artist),
          album: Value(album),
          artistId: Value(artistIdValue),
          albumId: Value(albumId),
          genre: Value(genre),
          year: Value(year),
          playCount: Value(playCount),
          lastPlayed: Value(lastPlayed),
          isFavorite: Value(isFavorite),
          isMissing: Value(isMissing),
          isDownloaded: Value(isDownloaded),
          durationMs: Value(durationMs ?? 0),
          dateAdded: Value(dateAdded),
          source: Value(source),
          remoteId: Value(remoteId),
          cueStartMs: Value(cueStartMs),
          cueFile: Value(cueFile),
          uri: Value(uri),
          lastPositionMs: Value(lastPositionMs ?? 0),
        ));
  }

  group('watchAllSongs branches', () {
    test('every sort key and direction produces a stream', () async {
      await insertSong(id: 1, title: 'Zeta', path: '/music/z.mp3');
      await insertSong(id: 2, title: 'Alpha', path: '/music/a.mp3');

      for (final sort in [
        'title',
        'artist',
        'dateAdded',
        'duration',
        'album',
        'playCount',
        'lastPlayed',
        'fileSize',
        'year',
        'sampleRate',
        'unknownSort',
      ]) {
        final res =
            await repo.watchAllSongs(sortBy: sort, ascending: false).first;
        expect(res.isRight(), isTrue, reason: sort);
      }
    });

    test('excluded folders are normalised and excluded', () async {
      await insertSong(id: 1, title: 'Keep', path: r'\music\keep\a.mp3');
      await insertSong(id: 2, title: 'Drop', path: r'\music\private\b.mp3');
      await insertSong(id: 3, title: 'Blank', path: r'\music\blank\c.mp3');

      final res = await repo
          .watchAllSongs(excludedFolders: [r'\music\private', '   ']).first;
      final songs = res.getOrElse((_) => []);
      expect(songs.map((s) => s.id), isNot(contains(2)));
    });

    test('search fallback applies the excluded-folder filter too', () async {
      await insertSong(id: 1, title: 'Needle', path: r'\music\keep\needle.mp3');
      await insertSong(
          id: 2, title: 'Needle', path: r'\music\private\needle.mp3');

      final res = await repo
          .watchAllSongs(
              searchQuery: '!!!', excludedFolders: [r'\music\private'])
          .first;
      expect(res.isRight(), isTrue);
    });

    test('FTS search honours excluded folders and offset', () async {
      await insertSong(id: 1, title: 'Sunshine', path: r'\music\a\sun.mp3');
      await insertSong(id: 2, title: 'Sunshine Two',
          path: r'\music\private\sun.mp3');

      final res = await repo
          .watchAllSongs(
            searchQuery: 'sunshine',
            excludedFolders: [r'\music\private'],
            offset: 0,
          )
          .first;
      final songs = res.getOrElse((_) => []);
      expect(songs.map((s) => s.id), isNot(contains(2)));
    });
  });

  group('getAllSongs / unknown sort', () {
    test('an unrecognised sort still returns every row', () async {
      await insertSong(id: 1, title: 'B');
      await insertSong(id: 2, title: 'A');
      final res = await repo.getAllSongs(sortBy: 'nonsense');
      final songs = res.getOrElse((_) => []);
      expect(songs, hasLength(2));
    });
  });

  group('favorites', () {
    test('watchFavorites includes youtube rows and excludes missing local',
        () async {
      await insertSong(
          id: 1,
          title: 'LocalFav',
          isFavorite: true,
          path: '/music/f.mp3');
      await insertSong(
          id: 2,
          title: 'YtFav',
          isFavorite: true,
          source: SongSource.youtube,
          remoteId: 'vidFav',
          path: 'ytmusic://vidFav');
      await insertSong(
          id: 3,
          title: 'MissingFav',
          isFavorite: true,
          isMissing: true,
          path: '/music/gone.mp3');

      final res = await repo.watchFavorites().first;
      final ids = res.getOrElse((_) => []).map((s) => s.id).toSet();
      expect(ids, containsAll([1, 2]));
      expect(ids, isNot(contains(3)));

      final favs = await repo.getFavorites();
      expect(favs.getOrElse((_) => []).length, 2);
    });

    test('toggleFavorite flips the flag on and back off', () async {
      await insertSong(id: 1, title: 'Toggle');
      expect((await repo.toggleFavorite(1)).getOrElse((_) => false), isTrue);
      expect((await repo.toggleFavorite(1)).getOrElse((_) => true), isFalse);
    });
  });

  group('importOnlineTracksAsFavorites', () {
    test('inserts a brand-new online track as a favorite', () async {
      const track = YtmTrack(
        videoId: 'newvid12345',
        title: 'Fresh',
        artist: 'Someone',
        duration: Duration(minutes: 2),
      );
      final res = await repo.importOnlineTracksAsFavorites(const [track]);
      expect(res.getOrElse((_) => 0), 1);

      final row = await (db.select(db.songsTable)
            ..where((t) => t.remoteId.equals('newvid12345')))
          .getSingle();
      expect(row.isFavorite, isTrue);
      expect(row.source, SongSource.youtube);
      expect(row.id, lessThan(0));
    });

    test('allocates a different id when the deterministic id is taken',
        () async {
      const track = YtmTrack(
        videoId: 'collidevid1',
        title: 'Collide',
        artist: 'Someone',
        duration: Duration(minutes: 2),
      );
      // A local row already owns the deterministic online id.
      await insertSong(id: track.songId, title: 'Occupied', path: '/music/o.mp3');

      await repo.importOnlineTracksAsFavorites(const [track]);

      final row = await (db.select(db.songsTable)
            ..where((t) => t.remoteId.equals('collidevid1')))
          .getSingle();
      expect(row.id, isNot(track.songId));
      expect(row.id, lessThan(0));
    });
  });

  group('recently played / added', () {
    test('watchRecentlyAdded accepts a null limit', () async {
      await insertSong(id: 1, title: 'New', dateAdded: 100);
      final res = await repo.watchRecentlyAdded(limit: null).first;
      expect(res.isRight(), isTrue);
    });

    test('watchRecentlyPlayed and watchTopPlayed emit for qualifying rows',
        () async {
      await insertSong(id: 1, title: 'Played', lastPlayed: 500, playCount: 3);
      expect((await repo.watchRecentlyPlayed().first).isRight(), isTrue);
      expect((await repo.watchTopPlayed().first).isRight(), isTrue);
    });
  });

  group('syncScannedMusic', () {
    test('remaps a changed scanner id onto the existing path row', () async {
      await insertSong(id: 100, title: 'Old', path: '/music/a.mp3');

      final res = await repo.syncScannedMusic(
        songs: [
          const SongsTableCompanion(
            id: Value(999),
            title: Value('Updated'),
            path: Value('/music/a.mp3'),
            source: Value(SongSource.local),
          ),
        ],
        albums: const [],
        artists: const [],
      );
      expect(res.isRight(), isTrue);

      final rows = await (db.select(db.songsTable)
            ..where((t) => t.path.equals('/music/a.mp3')))
          .get();
      expect(rows, hasLength(1));
      expect(rows.single.id, 100);
      expect(rows.single.title, 'Updated');
    });

    test('an empty batch is a harmless no-op', () async {
      final res = await repo.syncScannedMusic(
          songs: const [], albums: const [], artists: const []);
      expect(res.isRight(), isTrue);
    });
  });

  group('deleteSongsWithReport file handling', () {
    test('deletes a file inside an allowed app root', () async {
      final temp = Directory.systemTemp.createTempSync('repo_delete');
      addTearDown(() => temp.deleteSync(recursive: true));
      final file = File('${temp.path}${Platform.pathSeparator}track.mp3')
        ..writeAsStringSync('audio');

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, (call) async {
        return temp.path;
      });

      await insertSong(id: 1, title: 'Del', path: file.path);
      final res = await repo.deleteSongsWithReport([1]);
      expect(res.isRight(), isTrue);
      expect(file.existsSync(), isFalse);
    });

    test('refuses to delete a file outside the allowed roots', () async {
      final allowed = Directory.systemTemp.createTempSync('repo_allowed');
      final outside = Directory.systemTemp.createTempSync('repo_outside');
      addTearDown(() {
        allowed.deleteSync(recursive: true);
        outside.deleteSync(recursive: true);
      });
      final file = File('${outside.path}${Platform.pathSeparator}track.mp3')
        ..writeAsStringSync('audio');

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, (call) async {
        return allowed.path;
      });

      await insertSong(id: 1, title: 'Keep', path: file.path);
      await repo.deleteSongsWithReport([1]);
      expect(file.existsSync(), isTrue);
    });

    test('an empty id list is a no-op', () async {
      expect((await repo.deleteSongsWithReport(const [])).getOrElse((_) => []),
          isEmpty);
    });
  });

  group('lookups and tag updates', () {
    test('missing album / artist / playlist ids return null', () async {
      expect((await repo.getAlbumById(123)).getOrElse((_) => null), isNull);
      expect((await repo.getArtistById(123)).getOrElse((_) => null), isNull);
      expect((await repo.getPlaylistById(123)).getOrElse((_) => null), isNull);
    });

    test('updateSongTags on an unknown path is a no-op', () async {
      final res = await repo.updateSongTags(
        path: '/music/absent.mp3',
        title: 'T',
        artist: 'A',
        album: 'B',
      );
      expect(res.isRight(), isTrue);
    });

    test('updateAudioQuality falls back to the id when the path is empty',
        () async {
      await insertSong(id: 5, title: 'NoPath', path: '');
      await repo.updateAudioQuality(songId: 5, codec: 'FLAC');
      final row = (await repo.getSongById(5)).getOrElse((_) => null);
      expect(row!.codec, 'FLAC');
    });

    test('updateAudioQuality on an unknown id still succeeds', () async {
      final res = await repo.updateAudioQuality(songId: 999, codec: 'AAC');
      expect(res.isRight(), isTrue);
    });
  });

  group('cleanupOrphanedSongs', () {
    test('marks empty paths missing and chunks large sets', () async {
      await insertSong(id: 1, title: 'Keep', path: '/music/keep.mp3');
      await insertSong(id: 2, title: 'NoPath', path: '');
      for (var i = 10; i < 90; i++) {
        await insertSong(id: i, title: 'Gone$i', path: '/music/gone_$i.mp3');
      }

      final marked =
          (await repo.cleanupOrphanedSongs({1})).getOrElse((_) => -1);
      expect(marked, 81);
      final noPath = (await repo.getSongById(2)).getOrElse((_) => null);
      expect(noPath!.isMissing, isTrue);
      final kept = (await repo.getSongById(1)).getOrElse((_) => null);
      expect(kept!.isMissing, isFalse);
    });
  });

  group('expandCueSheets guards', () {
    test('skips a multi-file cue sheet', () async {
      final temp = Directory.systemTemp.createTempSync('repo_cue_multi');
      addTearDown(() => temp.deleteSync(recursive: true));
      final flac = File('${temp.path}${Platform.pathSeparator}album.flac')
        ..writeAsStringSync('x');
      File('${temp.path}${Platform.pathSeparator}album.cue').writeAsStringSync(
          'FILE "album.flac" WAVE\n  TRACK 01 AUDIO\n    TITLE "One"\n    INDEX 01 00:00:00\n'
          'FILE "other.flac" WAVE\n  TRACK 02 AUDIO\n    TITLE "Two"\n    INDEX 01 00:00:00\n');

      await insertSong(id: 1, title: 'Container', path: flac.path,
          durationMs: 600000);
      expect((await repo.expandCueSheets()).getOrElse((_) => -1), 0);
    });

    test('skips a cue sheet referencing a different audio file', () async {
      final temp = Directory.systemTemp.createTempSync('repo_cue_mismatch');
      addTearDown(() => temp.deleteSync(recursive: true));
      final flac = File('${temp.path}${Platform.pathSeparator}album.flac')
        ..writeAsStringSync('x');
      File('${temp.path}${Platform.pathSeparator}album.cue').writeAsStringSync(
          'FILE "different.flac" WAVE\n  TRACK 01 AUDIO\n    TITLE "One"\n    INDEX 01 00:00:00\n');

      await insertSong(id: 1, title: 'Container', path: flac.path,
          durationMs: 600000);
      expect((await repo.expandCueSheets()).getOrElse((_) => -1), 0);
    });
  });

  group('reconcileDownloadedSong', () {
    test('merges stats when the scanner already owns the new path', () async {
      final temp = Directory.systemTemp.createTempSync('repo_reconcile');
      addTearDown(() => temp.deleteSync(recursive: true));
      final file = File('${temp.path}${Platform.pathSeparator}new.mp3')
        ..writeAsStringSync('audio');

      await insertSong(
          id: 1,
          title: 'Old Title',
          artist: 'Old Artist',
          album: 'Old Album',
          path: 'ytmusic://vidMerge',
          source: SongSource.youtube,
          remoteId: 'vidMerge',
          playCount: 5,
          lastPlayed: 100,
          isFavorite: true);
      await insertSong(
          id: 2,
          title: 'new',
          artist: 'new',
          album: 'new',
          path: file.path,
          playCount: 2,
          lastPlayed: 200);

      final plId = (await repo.createPlaylist('List')).getOrElse((_) => -1);
      await repo.addSongToPlaylist(plId, 1);
      await repo.addSongToPlaylist(plId, 2); // duplicate target entry

      final res = await repo.reconcileDownloadedSong(
          oldId: 1, newPath: file.path);
      final surviving = res.getOrElse((_) => null);
      expect(surviving, 2);

      expect((await repo.getSongById(1)).getOrElse((_) => null), isNull);
      final merged = (await repo.getSongById(2)).getOrElse((_) => null);
      expect(merged!.title, 'Old Title');
      expect(merged.artist, 'Old Artist');
      expect(merged.playCount, 7);
      expect(merged.lastPlayed, 200);
      expect(merged.isFavorite, isTrue);
      expect(merged.remoteId, 'vidMerge');

      final playlistSongs =
          (await repo.getPlaylistSongs(plId)).getOrElse((_) => []);
      expect(playlistSongs, hasLength(1));
      expect(playlistSongs.single.id, 2);
    });

    test('promotes an existing YTM row when the file appears with no scanner row',
        () async {
      final temp = Directory.systemTemp.createTempSync('repo_reconcile2');
      addTearDown(() => temp.deleteSync(recursive: true));
      final file = File('${temp.path}${Platform.pathSeparator}only.mp3')
        ..writeAsStringSync('audio');

      await insertSong(
          id: 3,
          title: 'Yt Only',
          path: 'ytmusic://vidOnly',
          source: SongSource.youtube,
          remoteId: 'vidOnly');

      final res =
          await repo.reconcileDownloadedSong(oldId: 3, newPath: file.path);
      expect(res.getOrElse((_) => null), 3);
      final row = (await repo.getSongById(3)).getOrElse((_) => null);
      expect(row!.source, SongSource.local);
      expect(row.path, file.path);
      expect(row.isDownloaded, isTrue);
    });

    test('inserts a fallback row when neither the old row nor a scanner row exists',
        () async {
      final temp = Directory.systemTemp.createTempSync('repo_reconcile3');
      addTearDown(() => temp.deleteSync(recursive: true));
      final file = File('${temp.path}${Platform.pathSeparator}fallback.mp3')
        ..writeAsStringSync('audio');

      const fallback = SongsTableData(
        id: -1,
        title: 'Fallback',
        artist: 'Artist',
        album: '',
        durationMs: 1000,
        path: 'ytmusic://fallbackVid',
        source: SongSource.youtube,
        isFavorite: false,
        isMissing: false,
        isDownloaded: false,
        playCount: 0,
        lastPositionMs: 0,
        remoteId: 'fallbackVid',
      );

      final res = await repo.reconcileDownloadedSong(
          oldId: 4, newPath: file.path, fallbackSong: fallback);
      expect(res.getOrElse((_) => null), 4);
      final row = (await repo.getSongById(4)).getOrElse((_) => null);
      expect(row!.title, 'Fallback');
      expect(row.album, 'YouTube Music');
      expect(row.path, file.path);
    });

    test('returns null when the new file does not exist and there is no row',
        () async {
      final res = await repo.reconcileDownloadedSong(
          oldId: 9, newPath: '/definitely/not/here.mp3');
      expect(res.isRight(), isTrue);
      expect(res.getOrElse((_) => 99), isNull);
    });

    test('ignores a metadata match that is flagged missing', () async {
      final temp = Directory.systemTemp.createTempSync('repo_reconcile4');
      addTearDown(() => temp.deleteSync(recursive: true));
      final file = File('${temp.path}${Platform.pathSeparator}m.mp3')
        ..writeAsStringSync('audio');

      await insertSong(
          id: 5,
          title: 'Match',
          artist: 'Match Artist',
          durationMs: 10000,
          path: '/music/other.mp3',
          isMissing: true);
      await insertSong(
          id: 6,
          title: 'Old',
          path: 'ytmusic://vidMeta',
          source: SongSource.youtube,
          remoteId: 'vidMeta');

      final res =
          await repo.reconcileDownloadedSong(oldId: 6, newPath: file.path);
      expect(res.getOrElse((_) => null), 6);
      final row = (await repo.getSongById(6)).getOrElse((_) => null);
      expect(row!.path, file.path);
    });
  });
}
