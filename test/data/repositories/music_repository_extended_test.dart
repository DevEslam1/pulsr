// test/data/repositories/music_repository_extended_test.dart
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/audio_formats.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/repositories/music_repository.dart';
import 'package:pulsr/domain/models/chapter_info.dart';
import 'package:pulsr/domain/models/ytm_track.dart';

void main() {
  late AppDatabase db;
  late MusicRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = MusicRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insertSong({
    required int id,
    required String title,
    String? path,
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
  }) async {
    await db.into(db.songsTable).insert(SongsTableCompanion.insert(
          id: Value(id),
          title: title,
          path: path ?? '/music/song_$id.mp3',
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
        ));
  }

  group('toFtsQuery', () {
    test('builds a prefix query for plain words', () {
      expect(MusicRepository.toFtsQuery('Hello World'), '"hello"* "world"*');
    });

    test('strips FTS operators and returns null for symbol-only input', () {
      expect(MusicRepository.toFtsQuery('***'), isNull);
      expect(MusicRepository.toFtsQuery('   '), isNull);
    });

    test('supported CJK tokenization', () {
      final q = MusicRepository.toFtsQuery('音乐');
      expect(q, isNotNull);
      expect(q, contains('"音乐"*'));
    });
  });

  group('song queries', () {
    test('getAllSongs honours sort branches and limit', () async {
      await insertSong(id: 1, title: 'Zeta', artist: 'B');
      await insertSong(id: 2, title: 'Alpha', artist: 'A');

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
      ]) {
        final res = await repo.getAllSongs(sortBy: sort);
        expect(res.isRight(), isTrue, reason: sort);
      }

      final limited = await repo.getAllSongs(limit: 1, offset: 0);
      expect(limited.getOrElse((_) => []).length, 1);
    });

    test('getLocalSongPaths and getLocalSongEntries exclude virtual/yt rows',
        () async {
      await insertSong(id: 1, title: 'A', path: '/music/a.mp3');
      await insertSong(
          id: 2, title: 'V', path: '/music/a.mp3', cueStartMs: 1000);
      await insertSong(
          id: 3,
          title: 'Ytm',
          path: 'ytmusic://vid',
          source: SongSource.youtube,
          remoteId: 'vid');
      await insertSong(id: 4, title: 'Missing', path: '/music/m.mp3',
          isMissing: true);

      final paths = (await repo.getLocalSongPaths()).getOrElse((_) => []);
      expect(paths, ['/music/a.mp3']);

      final entries =
          (await repo.getLocalSongEntries()).getOrElse((_) => []);
      expect(entries.length, 1);
      expect(entries.first.id, 1);
    });

    test('watchSongsInFolder returns only direct children', () async {
      await insertSong(id: 1, title: 'Direct', path: '/music/album/one.mp3');
      await insertSong(id: 2, title: 'Deep', path: '/music/album/sub/two.mp3');

      final result =
          await repo.watchSongsInFolder('/music/album').first;
      final songs = result.getOrElse((_) => []);
      expect(songs.map((s) => s.id), [1]);
    });

    test('getSongById / by path / by uri / by remoteId', () async {
      await insertSong(
          id: 5, title: 'Lookup', path: '/music/look.mp3', uri: 'content://x/5',
          remoteId: 'remote5');

      expect(
          (await repo.getSongById(5)).getOrElse((_) => null)?.title, 'Lookup');
      expect(
          (await repo.getSongByPath('/music/look.mp3')).getOrElse((_) => null)?.id,
          5);
      expect(
          (await repo.getSongByUri('content://x/5')).getOrElse((_) => null)?.id,
          5);
      expect((await repo.getSongByRemoteId('remote5')).getOrElse((_) => null)?.id,
          5);
      expect((await repo.getSongByRemoteId('')).getOrElse((_) => null), isNull);
    });

    test('findMatchingLocalSong matches by remoteId, then title/artist', () async {
      await insertSong(
          id: 10,
          title: 'Match Me',
          artist: 'The Artist',
          path: '/music/match.mp3',
          remoteId: 'r10');

      final byId = await repo.findMatchingLocalSong(remoteId: 'r10');
      expect(byId.getOrElse((_) => null)?.id, 10);

      final byMeta = await repo
          .findMatchingLocalSong(title: 'match me', artist: 'the artist');
      expect(byMeta.getOrElse((_) => null)?.id, 10);

      final none = await repo.findMatchingLocalSong(title: 'nope');
      expect(none.getOrElse((_) => null), isNull);
    });

    test('getSongsByIds handles empty and populated lists', () async {
      expect((await repo.getSongsByIds(const [])).getOrElse((_) => <SongsTableData>[]),
          isEmpty);
      await insertSong(id: 20, title: 'Twenty');
      final res = await repo.getSongsByIds([20, 999]);
      expect(res.getOrElse((_) => []).map((s) => s.id), [20]);
    });
  });

  group('favorites / history / queue', () {
    test('clearRecentlyPlayed wipes lastPlayed', () async {
      await insertSong(id: 1, title: 'Played', lastPlayed: 1234);
      await repo.clearRecentlyPlayed();
      final recent = (await repo.getRecentlyPlayed()).getOrElse((_) => []);
      expect(recent, isEmpty);
    });

    test('recordPlayHistory ignores non-positive ids and dedupes', () async {
      final res = await repo.recordPlayHistory(-5);
      expect(res.isRight(), isTrue);

      await insertSong(id: 2, title: 'Played');
      await repo.recordPlayHistory(2, completed: true);
      await repo.recordPlayHistory(2, completed: true); // dedup within 1.5s
      final recent = (await repo.getRecentlyPlayed()).getOrElse((_) => []);
      expect(recent.length, 1);
      expect(recent.first.playCount, 1);
    });

    test('updateLastPosition persists the position', () async {
      await insertSong(id: 3, title: 'Pos');
      await repo.updateLastPosition(3, 42000);
      final song = (await repo.getSongById(3)).getOrElse((_) => null);
      expect(song!.lastPositionMs, 42000);
    });

    test('toggleFavorite returns failure for a missing song', () async {
      final res = await repo.toggleFavorite(999);
      expect(res.isLeft(), isTrue);
    });

    test('importOnlineTracksAsFavorites updates an existing row', () async {
      const track = YtmTrack(
        videoId: 'existingvid',
        title: 'Existing',
        artist: 'A',
        duration: Duration(minutes: 2),
      );
      await insertSong(
          id: track.songId,
          title: 'Existing',
          path: 'ytmusic://existingvid',
          source: SongSource.youtube,
          remoteId: 'existingvid',
          isMissing: true);

      final res = await repo.importOnlineTracksAsFavorites(const [track]);
      expect(res.getOrElse((_) => 0), 1);
      final row = await (db.select(db.songsTable)
            ..where((t) => t.remoteId.equals('existingvid')))
          .getSingle();
      expect(row.isFavorite, isTrue);
      expect(row.isMissing, isFalse);
    });

    test('favorites / recently added / top played streams emit', () async {
      await insertSong(id: 1, title: 'Fav', isFavorite: true, playCount: 5,
          lastPlayed: 1000, dateAdded: 500);
      expect((await repo.watchFavorites().first).isRight(), isTrue);
      expect((await repo.watchRecentlyAdded(limit: null).first).isRight(), isTrue);
      expect((await repo.watchRecentlyAdded().first).isRight(), isTrue);
      expect((await repo.watchTopPlayed().first).isRight(), isTrue);
      expect((await repo.watchRecentlyPlayed().first).isRight(), isTrue);
      expect((await repo.getFavorites()).getOrElse((_) => []).length, 1);
    });

    test('queue persistence round-trips', () async {
      await insertSong(id: 1, title: 'Q1');
      await insertSong(id: 2, title: 'Q2');

      await repo.saveQueue([1, 2], 1, 777);
      final items = (await repo.getSavedQueue()).getOrElse((_) => []);
      expect(items.length, 2);
      expect(items.firstWhere((i) => i.isCurrent).songId, 2);
      expect(items.firstWhere((i) => i.isCurrent).positionMs, 777);

      await repo.updateQueuePosition(999);
      final updated = (await repo.getSavedQueue()).getOrElse((_) => []);
      expect(updated.firstWhere((i) => i.isCurrent).positionMs, 999);
    });
  });

  group('albums / artists / genres / years', () {
    test('album and artist queries', () async {
      await db.into(db.albumsTable).insert(AlbumsTableCompanion.insert(
          id: const Value(100),
          title: 'Album A',
          artistId: const Value(200),
          songCount: const Value(1)));
      await db.into(db.artistsTable).insert(ArtistsTableCompanion.insert(
          id: const Value(200), name: 'Artist A', songCount: const Value(1)));
      await insertSong(
          id: 1,
          title: 'Track',
          album: 'Album A',
          albumId: 100,
          artist: 'Artist A',
          artistIdValue: 200);

      expect((await repo.getAlbums()).getOrElse((_) => []).length, 1);
      expect((await repo.getAlbumById(100)).getOrElse((_) => null)?.title,
          'Album A');
      expect((await repo.getAlbumSongs(100)).getOrElse((_) => []).length, 1);
      expect((await repo.watchAlbumSongs(100).first).getOrElse((_) => []).length,
          1);
      expect((await repo.watchAlbums().first).getOrElse((_) => []).length, 1);

      expect((await repo.getArtists()).getOrElse((_) => []).length, 1);
      expect((await repo.getArtistById(200)).getOrElse((_) => null)?.name,
          'Artist A');
      expect((await repo.getArtistSongs(200)).getOrElse((_) => []).length, 1);
      expect(
          (await repo.watchArtistSongs(200).first).getOrElse((_) => []).length,
          1);
      expect(
          (await repo.watchArtistAlbums(200).first).getOrElse((_) => []).length,
          1);

      await repo.updateAlbumArtwork(100, 'art://x');
      final album = (await repo.getAlbumById(100)).getOrElse((_) => null);
      expect(album!.artworkUri, 'art://x');
    });

    test('genre and year aggregation', () async {
      await insertSong(id: 1, title: 'G1', genre: 'Rock', year: 1994);
      await insertSong(id: 2, title: 'G2', genre: 'Rock', year: 2004);
      await insertSong(id: 3, title: 'G3', genre: 'Jazz', year: 2004);

      final genres = (await repo.getGenres()).getOrElse((_) => []);
      expect(genres.length, 2);
      expect(genres.firstWhere((g) => g.name == 'Rock').songCount, 2);
      expect((await repo.watchGenres().first).getOrElse((_) => []).length, 2);
      expect((await repo.getGenreSongs('Rock')).getOrElse((_) => []).length, 2);
      expect(
          (await repo.watchGenreSongs('Jazz').first).getOrElse((_) => []).length,
          1);

      final years = (await repo.watchYears().first).getOrElse((_) => []);
      expect(years.length, 2);
      expect(years.first.year, 2004); // descending
      expect(
          (await repo.watchYearSongs(2004).first).getOrElse((_) => []).length,
          2);
    });
  });

  group('playlists', () {
    test('full playlist lifecycle', () async {
      await insertSong(id: 1, title: 'P1');
      await insertSong(id: 2, title: 'P2');

      final plId = (await repo.createPlaylist('My List')).getOrElse((_) => -1);
      expect(plId, greaterThan(0));
      expect((await repo.getPlaylistById(plId)).getOrElse((_) => null)?.name,
          'My List');
      expect((await repo.getPlaylists()).getOrElse((_) => []).length, 1);
      expect((await repo.watchPlaylists().first).getOrElse((_) => []).length, 1);

      await repo.addSongToPlaylist(plId, 1);
      await repo.addSongToPlaylist(plId, 1); // duplicate ignored
      await repo.addSongsToPlaylist(plId, [2, 2]);
      var songs = (await repo.getPlaylistSongs(plId)).getOrElse((_) => []);
      expect(songs.length, 2);
      expect(
          (await repo.watchPlaylistSongs(plId).first).getOrElse((_) => []).length,
          2);

      await repo.removeSongFromPlaylist(plId, 1);
      songs = (await repo.getPlaylistSongs(plId)).getOrElse((_) => []);
      expect(songs.length, 1);

      await repo.reorderPlaylistSongs(plId, [2]);
      await repo.renamePlaylist(plId, 'Renamed');
      expect((await repo.getPlaylistById(plId)).getOrElse((_) => null)?.name,
          'Renamed');

      await repo.updateSmartPlaylist(plId, 'Smart', '{"rules":[]}');
      final smart = (await repo.getPlaylistById(plId)).getOrElse((_) => null);
      expect(smart!.isSmart, isFalse); // updateSmartPlaylist does not set flag

      await repo.deletePlaylist(plId);
      expect((await repo.getPlaylists()).getOrElse((_) => []), isEmpty);
    });

    test('createPlaylist supports smart criteria', () async {
      final id = (await repo.createPlaylist('Smart One',
              isSmart: true, smartCriteria: '{"rules":[]}'))
          .getOrElse((_) => -1);
      final pl = (await repo.getPlaylistById(id)).getOrElse((_) => null);
      expect(pl!.isSmart, isTrue);
      expect(pl.smartCriteria, '{"rules":[]}');
    });
  });

  group('excluded folders', () {
    test('toggle adds then removes', () async {
      await repo.toggleFolderExclusion('/music/private');
      expect((await repo.getExcludedFolderPaths()).getOrElse((_) => []),
          ['/music/private']);
      expect(
          (await repo.watchExcludedFolders().first).getOrElse((_) => []).length,
          1);

      await repo.toggleFolderExclusion('/music/private');
      expect((await repo.getExcludedFolderPaths()).getOrElse((_) => []),
          isEmpty);
    });
  });

  group('tag / audio quality updates', () {
    test('updateSongTags updates denormalised album and artist rows', () async {
      await db.into(db.albumsTable).insert(AlbumsTableCompanion.insert(
          id: const Value(7), title: 'Old Album'));
      await db.into(db.artistsTable).insert(
          ArtistsTableCompanion.insert(id: const Value(8), name: 'Old Artist'));
      await insertSong(
          id: 9,
          title: 'Old',
          path: '/music/tag.mp3',
          albumId: 7,
          artistIdValue: 8);

      await repo.updateSongTags(
        path: '/music/tag.mp3',
        title: 'New',
        artist: 'New Artist',
        album: 'New Album',
        genre: 'Pop',
        year: 2020,
        trackNumber: 3,
      );

      final song = (await repo.getSongById(9)).getOrElse((_) => null);
      expect(song!.title, 'New');
      expect(song.genre, 'Pop');
      expect(song.year, 2020);
      expect(song.trackNumber, 3);
      final album = (await repo.getAlbumById(7)).getOrElse((_) => null);
      expect(album!.title, 'New Album');
      final artist = (await repo.getArtistById(8)).getOrElse((_) => null);
      expect(artist!.name, 'New Artist');
    });

    test('updateAudioQuality spreads across rows sharing a path', () async {
      await insertSong(id: 1, title: 'C1', path: '/music/disc.flac',
          cueStartMs: 0);
      await insertSong(id: 2, title: 'C2', path: '/music/disc.flac',
          cueStartMs: 30000);

      await repo.updateAudioQuality(
          songId: 1,
          sampleRate: 96000,
          bitDepth: 24,
          bitrateKbps: 2304,
          codec: 'FLAC',
          loudnessRange: 8.5);

      final rows = await db.select(db.songsTable).get();
      expect(rows.every((r) => r.codec == 'FLAC'), isTrue);
      expect(rows.every((r) => r.sampleRate == 96000), isTrue);
    });
  });

  group('cleanup / delete', () {
    test('cleanupOrphanedSongs marks content: reappeared and keeps files',
        () async {
      final temp = Directory.systemTemp.createTempSync('repo_cleanup');
      addTearDown(() => temp.deleteSync(recursive: true));
      final existing = File('${temp.path}${Platform.pathSeparator}live.mp3')
        ..writeAsStringSync('x');

      await insertSong(id: 1, title: 'Existing', path: existing.path);
      await insertSong(id: 2, title: 'Content', path: 'content://media/x');
      await insertSong(id: 3, title: 'Gone', path: '${temp.path}/gone.mp3');

      final marked =
          (await repo.cleanupOrphanedSongs({})).fold((_) => -1, (r) => r);
      // empty scan guard: nothing marked
      expect(marked, 0);

      final res = await repo.cleanupOrphanedSongs({1});
      expect(res.isRight(), isTrue);
      final gone = (await repo.getSongById(3)).getOrElse((_) => null);
      expect(gone!.isMissing, isTrue);
      final content = (await repo.getSongById(2)).getOrElse((_) => null);
      expect(content!.isMissing, isFalse);
    });

    test('hardDeleteMissingSongs removes missing local rows', () async {
      await insertSong(id: 1, title: 'Keep', path: '/music/keep.mp3');
      await insertSong(id: 2, title: 'Missing', path: '/music/gone.mp3',
          isMissing: true);
      await insertSong(
          id: 3,
          title: 'MissingYt',
          path: 'ytmusic://x',
          source: SongSource.youtube,
          isMissing: true);

      final deleted = (await repo.hardDeleteMissingSongs()).getOrElse((_) => -1);
      expect(deleted, 1);
      final survivors = await db.select(db.songsTable).get();
      expect(survivors.map((s) => s.id), containsAll([1, 3]));
    });

    test('deleteSongsWithReport returns affected playlist ids', () async {
      await insertSong(id: 1, title: 'D1', path: '/music/d1.mp3');
      await insertSong(id: 2, title: 'D2', path: '/music/d2.mp3');
      final plId = (await repo.createPlaylist('List')).getOrElse((_) => -1);
      await repo.addSongsToPlaylist(plId, [1, 2]);

      final affected = (await repo.deleteSongsWithReport([1]))
          .getOrElse((_) => <int>[]);
      expect(affected, [plId]);
      expect((await repo.getSongById(1)).getOrElse((_) => null), isNull);

      // deleteSongs delegates to the report variant.
      final res = await repo.deleteSongs([2]);
      expect(res.isRight(), isTrue);
      expect((await repo.getSongById(2)).getOrElse((_) => null), isNull);
      expect((await repo.deleteSongsWithReport(const [])).getOrElse((_) => <int>[]),
          isEmpty);
    });
  });

  group('CUE expansion', () {
    test('cueVirtualSongId is deterministic and negative', () {
      final a = MusicRepository.cueVirtualSongId('/music/a.flac', 1);
      final b = MusicRepository.cueVirtualSongId('/music/a.flac', 1);
      final c = MusicRepository.cueVirtualSongId('/music/a.flac', 2);
      expect(a, b);
      expect(a, isNot(c));
      expect(a, lessThan(0));
    });

    test('buildCueExpansion maps chapters to virtual companions', () async {
      await insertSong(id: 1, title: 'Container', path: '/music/album.flac',
          durationMs: 600000, artist: 'Band', album: 'Disc');
      final container = (await repo.getSongById(1)).getOrElse((_) => null)!;

      final companions = MusicRepository.buildCueExpansion(
        container: container,
        chapters: const [
          ChapterInfo(index: 1, title: 'One', start: Duration.zero,
              end: Duration(minutes: 3)),
          ChapterInfo(index: 2, title: 'Two', start: Duration(minutes: 3)),
        ],
        cuePath: '/music/album.cue',
      );

      expect(companions.length, 2);
      expect(companions.first.title.value, 'One');
      expect(companions.first.cueStartMs.value, 0);
      expect(companions.first.cueEndMs.value, 180000);
      expect(companions.last.cueEndMs.value, isNull);
      expect(companions.first.source.value, SongSource.local);
    });

    test('expandCueSheets creates and later drops virtual rows', () async {
      final temp = Directory.systemTemp.createTempSync('repo_cue');
      addTearDown(() => temp.deleteSync(recursive: true));
      final flac = File('${temp.path}${Platform.pathSeparator}album.flac')
        ..writeAsStringSync('not-really-audio');
      final cue = File('${temp.path}${Platform.pathSeparator}album.cue')
        ..writeAsStringSync(
            'PERFORMER "Band"\nTITLE "Disc"\nFILE "album.flac" WAVE\n'
            '  TRACK 01 AUDIO\n    TITLE "One"\n    INDEX 01 00:00:00\n'
            '  TRACK 02 AUDIO\n    TITLE "Two"\n    INDEX 01 03:00:00\n');

      await insertSong(id: 1, title: 'Container', path: flac.path,
          durationMs: 600000);

      final expanded = (await repo.expandCueSheets()).getOrElse((_) => -1);
      expect(expanded, 2);

      final all = await db.select(db.songsTable).get();
      expect(all.where((s) => s.cueStartMs != null).length, 2);
      final container = all.firstWhere((s) => s.id == 1);
      expect(container.cueFile, isNotNull);

      // Idempotent second run.
      expect((await repo.expandCueSheets()).getOrElse((_) => -1), 2);

      // Removing the cue drops the virtual rows and clears the marker.
      cue.deleteSync();
      expect((await repo.expandCueSheets()).getOrElse((_) => -1), 0);
      final after = await db.select(db.songsTable).get();
      expect(after.where((s) => s.cueStartMs != null), isEmpty);
    });
  });

  group('watchAllSongs search fallback', () {
    test('like fallback runs when the query has no usable tokens', () async {
      await insertSong(id: 1, title: 'Needle', path: '/music/needle.mp3');
      final res = await repo.watchAllSongs(searchQuery: '!!!').first;
      expect(res.isRight(), isTrue);
    });

    test('FTS search finds matching songs', () async {
      await insertSong(id: 1, title: 'Sunshine', path: '/music/sun.mp3');
      await insertSong(id: 2, title: 'Rainfall', path: '/music/rain.mp3');
      final res = await repo.watchAllSongs(searchQuery: 'sunshine').first;
      final songs = res.getOrElse((_) => []);
      expect(songs.map((s) => s.title), contains('Sunshine'));
    });
  });

  test('AudioFormats smoke: supportedExtensions has mp3', () {
    expect(AudioFormats.supportedExtensions.contains('mp3'), isTrue);
  });
}
