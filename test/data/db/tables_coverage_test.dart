// test/data/db/tables_coverage_test.dart
//
// Complementary drift coverage for lib/data/db/tables.dart. The sibling
// tables_test.dart already round-trips every column; this file targets the
// remaining branches: nullable-column defaults on the supporting tables, the
// playlist -> entries cascade, and the primary-key/table-name declarations.
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

  group('table declarations', () {
    test('each table reports its mapped SQL name', () {
      expect(db.songsTable.actualTableName, 'songs');
      expect(db.albumsTable.actualTableName, 'albums');
      expect(db.artistsTable.actualTableName, 'artists');
      expect(db.playlistsTable.actualTableName, 'playlists');
      expect(db.playlistEntriesTable.actualTableName, 'playlist_entries');
      expect(db.playHistoryTable.actualTableName, 'play_history');
      expect(db.queueItemsTable.actualTableName, 'queue_items');
      expect(db.excludedFoldersTable.actualTableName, 'excluded_folders');
    });

    test('primary keys are declared on the id columns', () {
      expect(db.songsTable.primaryKey.map((c) => c.name), contains('id'));
      expect(db.albumsTable.primaryKey.map((c) => c.name), contains('id'));
      expect(db.artistsTable.primaryKey.map((c) => c.name), contains('id'));
      expect(db.playlistsTable.primaryKey.map((c) => c.name), contains('id'));
      expect(db.playlistEntriesTable.primaryKey.map((c) => c.name),
          contains('id'));
    });
  });

  group('supporting-table defaults', () {
    test('albums keep nullable columns null and default the counts', () async {
      await db.into(db.albumsTable).insert(
            AlbumsTableCompanion.insert(id: const Value(1), title: 'A'),
          );
      final row = await db.select(db.albumsTable).getSingle();
      expect(row.artist, 'Unknown Artist');
      expect(row.songCount, 0);
      expect(row.artistId, isNull);
      expect(row.artworkUri, isNull);
      expect(row.year, isNull);
    });

    test('artists keep nullable columns null and default the counts',
        () async {
      await db.into(db.artistsTable).insert(
            ArtistsTableCompanion.insert(id: const Value(1), name: 'Ar'),
          );
      final row = await db.select(db.artistsTable).getSingle();
      expect(row.songCount, 0);
      expect(row.albumCount, 0);
      expect(row.artworkUri, isNull);
    });

    test('playlists default to a non-smart list with no criteria', () async {
      await db.into(db.playlistsTable).insert(
            PlaylistsTableCompanion.insert(name: 'Plain'),
          );
      final row = await db.select(db.playlistsTable).getSingle();
      expect(row.isSmart, isFalse);
      expect(row.smartCriteria, isNull);
      expect(row.createdAt, isNotNull);
      expect(row.updatedAt, isNotNull);
    });

    test('queue items and play history default their boolean/int columns',
        () async {
      await db.into(db.songsTable).insert(
            SongsTableCompanion.insert(
                id: const Value(1), title: 'S', path: '/s.mp3'),
          );
      await db.into(db.queueItemsTable).insert(
            QueueItemsTableCompanion.insert(songId: 1, orderIndex: 2),
          );
      final q = await db.select(db.queueItemsTable).getSingle();
      expect(q.isCurrent, isFalse);
      expect(q.positionMs, 0);

      await db.into(db.playHistoryTable).insert(
            PlayHistoryTableCompanion.insert(songId: 1),
          );
      final h = await db.select(db.playHistoryTable).getSingle();
      expect(h.completed, isFalse);
      expect(h.playedAt, isNotNull);
    });
  });

  group('cascades', () {
    test('deleting a playlist removes only its own entries', () async {
      await db.into(db.songsTable).insert(
            SongsTableCompanion.insert(
                id: const Value(1), title: 'S', path: '/s.mp3'),
          );
      final keep = await db.into(db.playlistsTable).insert(
            PlaylistsTableCompanion.insert(name: 'Keep'),
          );
      final drop = await db.into(db.playlistsTable).insert(
            PlaylistsTableCompanion.insert(name: 'Drop'),
          );
      await db.into(db.playlistEntriesTable).insert(
            PlaylistEntriesTableCompanion.insert(
                playlistId: keep, songId: 1, orderIndex: 0),
          );
      await db.into(db.playlistEntriesTable).insert(
            PlaylistEntriesTableCompanion.insert(
                playlistId: drop, songId: 1, orderIndex: 1),
          );

      await (db.delete(db.playlistsTable)..where((t) => t.id.equals(drop)))
          .go();

      final entries = await db.select(db.playlistEntriesTable).get();
      expect(entries, hasLength(1));
      expect(entries.single.playlistId, keep);
      expect(await db.select(db.songsTable).get(), hasLength(1));
    });
  });
}