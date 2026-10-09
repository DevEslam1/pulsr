// test/data/db/tables_test.dart
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('SongSource', () {
    test('exposes the documented sentinel values', () {
      expect(SongSource.local, 'local');
      expect(SongSource.youtube, 'youtube');
      expect(SongSource.radio, 'radio');
    });
  });

  group('SongsTable', () {
    test('minimal insert applies every column default', () async {
      await db.into(db.songsTable).insert(
            SongsTableCompanion.insert(
              id: const Value(1),
              title: 'Minimal',
              path: '/music/minimal.mp3',
            ),
          );

      final row = await (db.select(db.songsTable)
            ..where((t) => t.id.equals(1)))
          .getSingle();

      expect(row.title, 'Minimal');
      expect(row.artist, 'Unknown Artist');
      expect(row.album, 'Unknown Album');
      expect(row.durationMs, 0);
      expect(row.isFavorite, isFalse);
      expect(row.isMissing, isFalse);
      expect(row.playCount, 0);
      expect(row.lastPositionMs, 0);
      expect(row.source, SongSource.local);
      expect(row.isDownloaded, isFalse);
      // Nullable columns stay null until populated.
      expect(row.artistId, isNull);
      expect(row.albumId, isNull);
      expect(row.uri, isNull);
      expect(row.trackNumber, isNull);
      expect(row.discNumber, isNull);
      expect(row.year, isNull);
      expect(row.dateAdded, isNull);
      expect(row.genre, isNull);
      expect(row.replayGainTrack, isNull);
      expect(row.replayGainAlbum, isNull);
      expect(row.replayGainTrackPeak, isNull);
      expect(row.replayGainAlbumPeak, isNull);
      expect(row.loudnessRange, isNull);
      expect(row.lastPlayed, isNull);
      expect(row.artworkUri, isNull);
      expect(row.fileSize, isNull);
      expect(row.sampleRate, isNull);
      expect(row.bitDepth, isNull);
      expect(row.bitrateKbps, isNull);
      expect(row.codec, isNull);
      expect(row.remoteId, isNull);
      expect(row.remoteArtworkUrl, isNull);
      expect(row.pendingDownloadPath, isNull);
      expect(row.cueStartMs, isNull);
      expect(row.cueEndMs, isNull);
      expect(row.cueFile, isNull);
    });

    test('round-trips every column value', () async {
      await db.into(db.songsTable).insert(
            SongsTableCompanion.insert(
              id: const Value(100),
              title: 'Full',
              artist: const Value('Artist'),
              artistId: const Value(5),
              album: const Value('Album'),
              albumId: const Value(6),
              durationMs: const Value(12345),
              path: '/music/full.flac',
              uri: const Value('content://media/1'),
              trackNumber: const Value(2),
              discNumber: const Value(1),
              year: const Value(2024),
              dateAdded: const Value(1700000000),
              genre: const Value('Rock'),
              isFavorite: const Value(true),
              isMissing: const Value(true),
              replayGainTrack: const Value(-6.5),
              replayGainAlbum: const Value(-7.0),
              replayGainTrackPeak: const Value(0.99),
              replayGainAlbumPeak: const Value(1.0),
              loudnessRange: const Value(8.5),
              playCount: const Value(4),
              lastPlayed: const Value(1700000001),
              lastPositionMs: const Value(999),
              artworkUri: const Value('file:///art.jpg'),
              fileSize: const Value(1000),
              sampleRate: const Value(96000),
              bitDepth: const Value(24),
              bitrateKbps: const Value(2300),
              codec: const Value('FLAC'),
              source: const Value(SongSource.youtube),
              remoteId: const Value('vid1'),
              remoteArtworkUrl: const Value('https://cdn/art.jpg'),
              pendingDownloadPath: const Value('/pending/file.flac'),
              isDownloaded: const Value(true),
              cueStartMs: const Value(100),
              cueEndMs: const Value(200),
              cueFile: const Value('/music/full.cue'),
            ),
          );

      final row = await (db.select(db.songsTable)
            ..where((t) => t.id.equals(100)))
          .getSingle();

      expect(row.artist, 'Artist');
      expect(row.artistId, 5);
      expect(row.album, 'Album');
      expect(row.albumId, 6);
      expect(row.durationMs, 12345);
      expect(row.uri, 'content://media/1');
      expect(row.trackNumber, 2);
      expect(row.discNumber, 1);
      expect(row.year, 2024);
      expect(row.dateAdded, 1700000000);
      expect(row.genre, 'Rock');
      expect(row.isFavorite, isTrue);
      expect(row.isMissing, isTrue);
      expect(row.replayGainTrack, -6.5);
      expect(row.replayGainAlbum, -7.0);
      expect(row.replayGainTrackPeak, 0.99);
      expect(row.replayGainAlbumPeak, 1.0);
      expect(row.loudnessRange, 8.5);
      expect(row.playCount, 4);
      expect(row.lastPlayed, 1700000001);
      expect(row.lastPositionMs, 999);
      expect(row.artworkUri, 'file:///art.jpg');
      expect(row.fileSize, 1000);
      expect(row.sampleRate, 96000);
      expect(row.bitDepth, 24);
      expect(row.bitrateKbps, 2300);
      expect(row.codec, 'FLAC');
      expect(row.source, SongSource.youtube);
      expect(row.remoteId, 'vid1');
      expect(row.remoteArtworkUrl, 'https://cdn/art.jpg');
      expect(row.pendingDownloadPath, '/pending/file.flac');
      expect(row.isDownloaded, isTrue);
      expect(row.cueStartMs, 100);
      expect(row.cueEndMs, 200);
      expect(row.cueFile, '/music/full.cue');
    });
  });

  group('supporting tables', () {
    test('AlbumsTable stores rows', () async {
      await db.into(db.albumsTable).insert(
            AlbumsTableCompanion.insert(
              id: const Value(1),
              title: 'Album',
              artist: const Value('Artist'),
              songCount: const Value(3),
              year: const Value(2020),
              artworkUri: const Value('file:///a.jpg'),
            ),
          );
      final row = await db.select(db.albumsTable).getSingle();
      expect(row.title, 'Album');
      expect(row.artist, 'Artist');
      expect(row.songCount, 3);
      expect(row.year, 2020);
      expect(row.artworkUri, 'file:///a.jpg');
    });

    test('ArtistsTable stores rows', () async {
      await db.into(db.artistsTable).insert(
            ArtistsTableCompanion.insert(
              id: const Value(1),
              name: 'Artist',
              songCount: const Value(2),
              albumCount: const Value(1),
              artworkUri: const Value('file:///ar.jpg'),
            ),
          );
      final row = await db.select(db.artistsTable).getSingle();
      expect(row.name, 'Artist');
      expect(row.songCount, 2);
      expect(row.albumCount, 1);
      expect(row.artworkUri, 'file:///ar.jpg');
    });

    test('PlaylistsTable autoincrements and stores smart flags', () async {
      final id = await db.into(db.playlistsTable).insert(
            PlaylistsTableCompanion.insert(
              name: 'Smart',
              isSmart: const Value(true),
              smartCriteria: const Value('{"rules":[]}'),
            ),
          );
      expect(id, isPositive);
      final row = await db.select(db.playlistsTable).getSingle();
      expect(row.name, 'Smart');
      expect(row.isSmart, isTrue);
      expect(row.smartCriteria, '{"rules":[]}');
      expect(row.createdAt, isNotNull);
      expect(row.updatedAt, isNotNull);
    });

    test('PlaylistEntriesTable stores rows', () async {
      await db.into(db.songsTable).insert(
            SongsTableCompanion.insert(
                id: const Value(1), title: 'S', path: '/s.mp3'),
          );
      final playlistId = await db.into(db.playlistsTable).insert(
            PlaylistsTableCompanion.insert(name: 'P'),
          );
      await db.into(db.playlistEntriesTable).insert(
            PlaylistEntriesTableCompanion.insert(
              playlistId: playlistId,
              songId: 1,
              orderIndex: 0,
            ),
          );
      final row = await db.select(db.playlistEntriesTable).getSingle();
      expect(row.playlistId, playlistId);
      expect(row.songId, 1);
      expect(row.orderIndex, 0);
      expect(row.addedAt, isNotNull);
    });

    test('PlayHistoryTable stores rows', () async {
      await db.into(db.songsTable).insert(
            SongsTableCompanion.insert(
                id: const Value(1), title: 'S', path: '/s.mp3'),
          );
      await db.into(db.playHistoryTable).insert(
            PlayHistoryTableCompanion.insert(
              songId: 1,
              completed: const Value(true),
            ),
          );
      final row = await db.select(db.playHistoryTable).getSingle();
      expect(row.songId, 1);
      expect(row.completed, isTrue);
      expect(row.playedAt, isNotNull);
    });

    test('QueueItemsTable stores rows', () async {
      await db.into(db.songsTable).insert(
            SongsTableCompanion.insert(
                id: const Value(1), title: 'S', path: '/s.mp3'),
          );
      await db.into(db.queueItemsTable).insert(
            QueueItemsTableCompanion.insert(
              songId: 1,
              orderIndex: 0,
              isCurrent: const Value(true),
              positionMs: const Value(500),
            ),
          );
      final row = await db.select(db.queueItemsTable).getSingle();
      expect(row.songId, 1);
      expect(row.orderIndex, 0);
      expect(row.isCurrent, isTrue);
      expect(row.positionMs, 500);
    });

    test('ExcludedFoldersTable enforces unique folder paths', () async {
      await db.into(db.excludedFoldersTable).insert(
            ExcludedFoldersTableCompanion.insert(folderPath: '/skip'),
          );
      final row = await db.select(db.excludedFoldersTable).getSingle();
      expect(row.folderPath, '/skip');
      expect(row.addedAt, isNotNull);

      await expectLater(
        db.into(db.excludedFoldersTable).insert(
              ExcludedFoldersTableCompanion.insert(folderPath: '/skip'),
            ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('foreign key cascades', () {
    test('deleting a song removes its dependent rows', () async {
      await db.into(db.songsTable).insert(
            SongsTableCompanion.insert(
                id: const Value(1), title: 'S', path: '/s.mp3'),
          );
      final playlistId = await db.into(db.playlistsTable).insert(
            PlaylistsTableCompanion.insert(name: 'P'),
          );
      await db.into(db.playlistEntriesTable).insert(
            PlaylistEntriesTableCompanion.insert(
              playlistId: playlistId,
              songId: 1,
              orderIndex: 0,
            ),
          );
      await db.into(db.playHistoryTable).insert(
            PlayHistoryTableCompanion.insert(songId: 1),
          );
      await db.into(db.queueItemsTable).insert(
            QueueItemsTableCompanion.insert(
                songId: 1, orderIndex: 0),
          );

      await (db.delete(db.songsTable)..where((t) => t.id.equals(1))).go();

      expect(await db.select(db.playlistEntriesTable).get(), isEmpty);
      expect(await db.select(db.playHistoryTable).get(), isEmpty);
      expect(await db.select(db.queueItemsTable).get(), isEmpty);
      // The playlist itself survives; only the membership cascades.
      expect(await db.select(db.playlistsTable).get(), hasLength(1));
    });
  });
}
