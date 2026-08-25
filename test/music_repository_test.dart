// test/music_repository_test.dart
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/repositories/music_repository.dart';

void main() {
  late AppDatabase db;
  late MusicRepository repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = MusicRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('MusicRepository & AppDatabase Tests', () {
    test('AppDatabase schema migration to v7 creates indexes successfully', () async {
      expect(db.schemaVersion, equals(7));

      // Query pragma index_list for songs table
      final indexes = await db.customSelect('PRAGMA index_list("songs");').get();
      final indexNames = indexes.map((row) => row.read<String>('name')).toList();

      expect(indexNames, contains('idx_songs_title'));
      expect(indexNames, contains('idx_songs_artist'));
      expect(indexNames, contains('idx_songs_album_id'));
      expect(indexNames, contains('idx_songs_is_favorite'));
      expect(indexNames, contains('idx_songs_path'));
      expect(indexNames, contains('idx_songs_is_missing'));
      expect(indexNames, contains('idx_songs_source'));
      expect(indexNames, contains('idx_songs_remote_id'));
    });

    test('Empty scan does not wipe existing songs or playlists (Issue #1)', () async {
      final song = SongsTableCompanion.insert(
        id: const Value(10),
        title: 'Preserved Track',
        path: '/storage/music/preserved.mp3',
        isFavorite: const Value(true),
      );
      await db.into(db.songsTable).insert(song);

      // Run cleanup with empty scanned list (e.g. unmounted SD card or permission issue)
      final res = await repository.cleanupOrphanedSongs({});
      expect(res.isRight(), isTrue);

      final songsRes = await repository.getAllSongs();
      final songs = songsRes.getOrElse((_) => []);
      expect(songs.length, equals(1));
      expect(songs.first.id, equals(10));
    });

    test('Rescan does not mark YouTube rows missing or hard-delete them', () async {
      await db.into(db.songsTable).insert(
        SongsTableCompanion.insert(
          id: const Value(-7),
          title: 'Streamed Track',
          path: 'ytmusic://vid7',
          source: const Value(SongSource.youtube),
          remoteId: const Value('vid7'),
          isFavorite: const Value(true),
        ),
      );
      await db.into(db.songsTable).insert(
        SongsTableCompanion.insert(id: const Value(11), title: 'Gone Local', path: '/music/gone.mp3'),
      );
      await db.into(db.songsTable).insert(
        SongsTableCompanion.insert(id: const Value(12), title: 'Still Here', path: '/music/here.mp3'),
      );

      // MediaStore only ever reports positive local ids.
      final marked = await repository.cleanupOrphanedSongs({12});
      expect(marked.getOrElse((_) => -1), equals(1), reason: 'only the vanished local row');

      final yt = await (db.select(db.songsTable)..where((t) => t.id.equals(-7))).getSingle();
      expect(yt.isMissing, isFalse);

      await repository.hardDeleteMissingSongs();
      final survivors = await db.select(db.songsTable).get();
      expect(survivors.map((s) => s.id), containsAll([-7, 12]));
      expect(survivors.map((s) => s.id), isNot(contains(11)));
    });

    test('Insert and retrieve songs from repository', () async {
      final song = SongsTableCompanion.insert(
        id: const Value(1),
        title: 'Test Song',
        artist: const Value('Test Artist'),
        path: '/storage/music/test.mp3',
        isFavorite: const Value(true),
      );

      await db.into(db.songsTable).insert(song);

      final result = await repository.getAllSongs();
      final songs = result.getOrElse((_) => []);
      expect(songs.length, equals(1));
      expect(songs.first.title, equals('Test Song'));
      expect(songs.first.isFavorite, isTrue);

      final favResult = await repository.getFavorites();
      final favorites = favResult.getOrElse((_) => []);
      expect(favorites.length, equals(1));
      expect(favorites.first.id, equals(1));
    });

    test('Toggle favorite song', () async {
      final song = SongsTableCompanion.insert(
        id: const Value(2),
        title: 'Song 2',
        path: '/storage/music/song2.mp3',
        isFavorite: const Value(false),
      );

      await db.into(db.songsTable).insert(song);
      await repository.toggleFavorite(2);

      final favResult = await repository.getFavorites();
      final favorites = favResult.getOrElse((_) => []);
      expect(favorites.any((s) => s.id == 2), isTrue);
    });

    test('Record play history updates song count and lastPlayed', () async {
      final song = SongsTableCompanion.insert(
        id: const Value(3),
        title: 'Song 3',
        path: '/storage/music/song3.mp3',
      );

      await db.into(db.songsTable).insert(song);
      await repository.recordPlayHistory(3, completed: true);

      final recentResult = await repository.getRecentlyPlayed();
      final recent = recentResult.getOrElse((_) => []);
      expect(recent.length, equals(1));
      expect(recent.first.playCount, equals(1));
    });
  });

  group('reconcileDownloadedSong', () {
    Future<int> insertYtRow({
      int id = -100,
      String title = 'Downloaded',
      String artist = 'Artist',
      String remoteId = 'vid100',
      int durationMs = 200000,
      bool isFavorite = true,
      int playCount = 5,
      int? lastPlayed = 2000,
      int lastPositionMs = 30000,
    }) async {
      await db.into(db.songsTable).insert(SongsTableCompanion.insert(
            id: Value(id),
            title: title,
            artist: Value(artist),
            path: 'ytmusic://$remoteId',
            durationMs: Value(durationMs),
            source: const Value(SongSource.youtube),
            remoteId: Value(remoteId),
            remoteArtworkUrl: const Value('https://img/cover'),
            isFavorite: Value(isFavorite),
            playCount: Value(playCount),
            lastPlayed: Value(lastPlayed),
            lastPositionMs: Value(lastPositionMs),
          ));
      return id;
    }

    Future<int> insertScannedRow({
      int id = 500,
      String title = 'Downloaded',
      String artist = 'Artist',
      String path = '/storage/Music/Downloaded.m4a',
      int durationMs = 200000,
      bool isFavorite = false,
      int playCount = 3,
      int? lastPlayed = 1000,
    }) async {
      await db.into(db.songsTable).insert(SongsTableCompanion.insert(
            id: Value(id),
            title: title,
            artist: Value(artist),
            path: path,
            durationMs: Value(durationMs),
            source: const Value(SongSource.local),
            isFavorite: Value(isFavorite),
            playCount: Value(playCount),
            lastPlayed: Value(lastPlayed),
            dateAdded: const Value(9999),
          ));
      return id;
    }

    test('folds the YT row into the scanned row, merging stats and re-pointing children', () async {
      await insertYtRow();
      await insertScannedRow();
      final plId = (await repository.createPlaylist('My List')).getOrElse((_) => -1);
      await repository.addSongToPlaylist(plId, -100);
      await repository.saveQueue([-100], 0, 0);
      await db.into(db.playHistoryTable).insert(const PlayHistoryTableCompanion(songId: Value(-100)));

      final res = await repository.reconcileDownloadedSong(oldId: -100, newPath: '/storage/Music/Downloaded.m4a');
      expect(res.getOrElse((_) => null), equals(500));

      // YT row gone, scanned row survives as a local row carrying the video id.
      expect(await (db.select(db.songsTable)..where((t) => t.id.equals(-100))).getSingleOrNull(), isNull);
      final merged = await (db.select(db.songsTable)..where((t) => t.id.equals(500))).getSingle();
      expect(merged.source, equals(SongSource.local));
      expect(merged.remoteId, equals('vid100'));
      expect(merged.isFavorite, isTrue, reason: 'favorite OR');
      expect(merged.playCount, equals(8), reason: 'play counts summed');
      expect(merged.lastPlayed, equals(2000), reason: 'max lastPlayed');
      expect(merged.lastPositionMs, equals(30000), reason: 'position from the more-recently-played row');
      expect(merged.pendingDownloadPath, isNull);

      // Children now point at the positive id.
      final songs = (await repository.getPlaylistSongs(plId)).getOrElse((_) => []);
      expect(songs.map((s) => s.id), equals([500]));
      final queue = (await repository.getSavedQueue()).getOrElse((_) => []);
      expect(queue.single.songId, equals(500));
      final history = await db.select(db.playHistoryTable).get();
      expect(history.single.songId, equals(500));
    });

    test('dedupes shared playlist membership instead of doubling it', () async {
      await insertYtRow();
      await insertScannedRow();
      final plId = (await repository.createPlaylist('Both')).getOrElse((_) => -1);
      await repository.addSongToPlaylist(plId, -100);
      await repository.addSongToPlaylist(plId, 500);

      await repository.reconcileDownloadedSong(oldId: -100, newPath: '/storage/Music/Downloaded.m4a');

      final songs = (await repository.getPlaylistSongs(plId)).getOrElse((_) => []);
      expect(songs.length, equals(1), reason: 'no duplicate entry despite no unique index');
      expect(songs.single.id, equals(500));
    });

    test('is a no-op that keeps the YT row when no scanned row matches', () async {
      await insertYtRow();

      final res = await repository.reconcileDownloadedSong(oldId: -100, newPath: '/storage/Music/absent.m4a');
      expect(res.getOrElse((_) => 1), isNull);
      expect(await (db.select(db.songsTable)..where((t) => t.id.equals(-100))).getSingleOrNull(), isNotNull);
    });

    test('falls back to a metadata match when MediaStore renamed the file', () async {
      await insertYtRow();
      await insertScannedRow(path: '/storage/Music/Downloaded (1).m4a');

      final res = await repository.reconcileDownloadedSong(oldId: -100, newPath: '/storage/Music/Downloaded.m4a');
      expect(res.getOrElse((_) => null), equals(500));
      expect(await (db.select(db.songsTable)..where((t) => t.id.equals(-100))).getSingleOrNull(), isNull);
    });
  });
}
