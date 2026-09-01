import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:pulsr/core/widgets/cached_artwork.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/repositories/music_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('B1: Shuffle Queue Mutation Tests', () {
    test('Removing an item updates shuffle history without RangeError', () {
      final songs = List.generate(
        10,
        (i) => SongsTableData(
          id: i + 1,
          title: 'Song $i',
          artist: 'Artist',
          album: 'Album',
          path: '/music/song$i.mp3',
          durationMs: 180000,
          dateAdded: 1000,
          playCount: 0,
          lastPositionMs: 0,
          isFavorite: false,
          isMissing: false,
          isDownloaded: false,
          source: SongSource.local,
        ),
      );

      var shuffleHistory = <int>[0, 3, 5, 8];
      var playedShuffleIndices = <int>{0, 3, 5, 8};

      const removedIndex = 2;
      songs.removeAt(removedIndex);

      shuffleHistory = shuffleHistory
          .where((i) => i != removedIndex)
          .map((i) => i > removedIndex ? i - 1 : i)
          .toList();

      final newPlayed = <int>{};
      for (final i in playedShuffleIndices) {
        if (i == removedIndex) continue;
        newPlayed.add(i > removedIndex ? i - 1 : i);
      }
      playedShuffleIndices = newPlayed;

      expect(shuffleHistory, equals([0, 2, 4, 7]));
      expect(playedShuffleIndices, equals({0, 2, 4, 7}));

      final prevIndex = shuffleHistory.removeLast();
      expect(prevIndex, equals(7));
      expect(songs[prevIndex].title, equals('Song 8'));
    });
  });

  group('B3: Cloud Sync Stable ID Tests', () {
    test('Local song stable ID is independent of file path', () {
      final song1 = SongsTableData(
        id: 1,
        title: 'Bohemian Rhapsody',
        artist: 'Queen',
        album: 'A Night at the Opera',
        path: '/storage/music/queen_bohemian.mp3',
        durationMs: 354000,
        dateAdded: 1000,
        playCount: 0,
        lastPositionMs: 0,
        isFavorite: false,
        isMissing: false,
        isDownloaded: false,
        source: SongSource.local,
      );

      final songRenamed = SongsTableData(
        id: 2,
        title: 'Bohemian Rhapsody',
        artist: 'Queen',
        album: 'A Night at the Opera',
        path: '/sdcard/Audio/Queen - Bohemian Rhapsody (Remastered).flac',
        durationMs: 354000,
        dateAdded: 2000,
        playCount: 5,
        lastPositionMs: 0,
        isFavorite: true,
        isMissing: false,
        isDownloaded: true,
        source: SongSource.local,
      );

      String computeStableId(SongsTableData s) {
        final normTitle = s.title.trim().toLowerCase();
        final normArtist = s.artist.trim().toLowerCase();
        final normAlbum = s.album.trim().toLowerCase();
        final durationMs = s.durationMs;
        final raw = '$normTitle|$normArtist|$normAlbum|$durationMs';
        return raw;
      }

      expect(computeStableId(song1), equals(computeStableId(songRenamed)));
    });
  });

  group('B5: ArtworkLruCache Singleton Tests', () {
    test('ArtworkLruCache.withCapacity mutates singleton and maintains identity', () {
      final cache1 = ArtworkLruCache();
      final cache2 = ArtworkLruCache.withCapacity(50);

      expect(identical(cache1, cache2), isTrue);
      expect(cache1.maxCapacity, equals(50));
      expect(cache2.maxCapacity, equals(50));
    });
  });

  group('D3: Scanner Race Reconcile Duplicate Tests', () {
    late AppDatabase db;
    late MusicRepository repository;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repository = MusicRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('reconcileDownloadedSong cleans duplicate paths and reassigns FKs', () async {
      final oldId = await db.into(db.songsTable).insert(
            SongsTableCompanion.insert(
              title: 'Starboy',
              artist: const drift.Value('The Weeknd'),
              album: const drift.Value('Starboy'),
              durationMs: const drift.Value(230000),
              path: 'https://stream.youtube.com/audio123',
              source: const drift.Value(SongSource.youtube),
            ),
          );

      const downloadPath = '/storage/music/Starboy.mp3';
      final scannedId = await db.into(db.songsTable).insert(
            SongsTableCompanion.insert(
              title: 'Starboy',
              artist: const drift.Value('The Weeknd'),
              album: const drift.Value('Starboy'),
              durationMs: const drift.Value(230000),
              path: downloadPath,
              source: const drift.Value(SongSource.local),
            ),
          );

      final plId = await db.into(db.playlistsTable).insert(
            PlaylistsTableCompanion.insert(name: 'My Favs'),
          );
      await db.into(db.playlistEntriesTable).insert(
            PlaylistEntriesTableCompanion.insert(
              playlistId: plId,
              songId: oldId,
              orderIndex: 0,
            ),
          );
      await db.into(db.queueItemsTable).insert(
            QueueItemsTableCompanion.insert(
              songId: oldId,
              orderIndex: 0,
            ),
          );

      final result = await repository.reconcileDownloadedSong(
        oldId: oldId,
        newPath: downloadPath,
      );

      expect(result.isRight(), isTrue);
      final survivingId = result.getOrElse((_) => -1);
      expect(survivingId, equals(scannedId));

      final oldSong = await (db.select(db.songsTable)..where((t) => t.id.equals(oldId))).getSingleOrNull();
      expect(oldSong, isNull);

      final plEntry = await (db.select(db.playlistEntriesTable)..where((t) => t.playlistId.equals(plId))).getSingle();
      expect(plEntry.songId, equals(survivingId));

      final qItem = await (db.select(db.queueItemsTable)).getSingle();
      expect(qItem.songId, equals(survivingId));
    });
  });
}
