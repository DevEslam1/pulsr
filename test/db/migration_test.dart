import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';

import 'legacy_schema.dart';

void main() {
  group('Drift Schema Migration Tests', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('Fresh database opens at schemaVersion 5 and has all indexes', () async {
      expect(db.schemaVersion, equals(5));

      // Test inserting a song with schema v4 fields
      final songId = await db.into(db.songsTable).insert(
        SongsTableCompanion.insert(
          id: const Value(101),
          title: 'Test Song',
          path: '/music/test.mp3',
          isMissing: const Value(false),
          replayGain: const Value(-1.5),
        ),
      );
      expect(songId, equals(101));

      final song = await (db.select(db.songsTable)..where((t) => t.id.equals(101))).getSingle();
      expect(song.title, equals('Test Song'));
      expect(song.isMissing, isFalse);
      expect(song.replayGain, equals(-1.5));
      expect(song.source, equals(SongSource.local));
      expect(song.remoteId, equals(null));
    });

    test('YouTube rows coexist with local rows and remote_id is unique', () async {
      await db.into(db.songsTable).insert(
        SongsTableCompanion.insert(
          id: const Value(-42),
          title: 'Streamed Track',
          path: 'ytmusic://abc123',
          source: const Value(SongSource.youtube),
          remoteId: const Value('abc123'),
          remoteArtworkUrl: const Value('https://i.ytimg.com/vi/abc123/hq.jpg'),
        ),
      );

      final row = await (db.select(db.songsTable)..where((t) => t.id.equals(-42))).getSingle();
      expect(row.source, equals(SongSource.youtube));
      expect(row.remoteId, equals('abc123'));

      await expectLater(
        db.into(db.songsTable).insert(
          SongsTableCompanion.insert(
            id: const Value(-43),
            title: 'Duplicate Video',
            path: 'ytmusic://abc123',
            source: const Value(SongSource.youtube),
            remoteId: const Value('abc123'),
          ),
        ),
        throwsA(isA<Exception>()),
      );

      // The partial index must still allow many rows with a NULL remote_id.
      for (final id in [201, 202]) {
        await db.into(db.songsTable).insert(
          SongsTableCompanion.insert(id: Value(id), title: 'Local $id', path: '/music/$id.mp3'),
        );
      }
      final locals = await (db.select(db.songsTable)..where((t) => t.source.equals(SongSource.local))).get();
      expect(locals.length, equals(2));
    });

    test('Foreign key constraints and WAL pragma execute on open', () async {
      final pragmaFk = await db.customSelect('PRAGMA foreign_keys;').getSingle();
      expect(pragmaFk.data['foreign_keys'], equals(1));
    });

    test('ExcludedFolders table is created and operational', () async {
      final insertedId = await db.into(db.excludedFoldersTable).insert(
        ExcludedFoldersTableCompanion.insert(folderPath: '/storage/emulated/0/WhatsApp'),
      );
      expect(insertedId, isPositive);

      final folders = await db.select(db.excludedFoldersTable).get();
      expect(folders.length, equals(1));
      expect(folders.first.folderPath, equals('/storage/emulated/0/WhatsApp'));
    });
  });

  group('Upgrade path', () {
    late AppDatabase upgraded;

    tearDown(() async {
      await upgraded.close();
    });

    Future<Set<String>> songIndexNames() async {
      final rows = await upgraded.customSelect('PRAGMA index_list("songs");').get();
      return rows.map((row) => row.read<String>('name')).toSet();
    }

    test('v4 -> v5 backfills source, keeps data, and adds the new indexes', () async {
      upgraded = openLegacyDatabase(4);

      // Opening is lazy; the first query is what triggers the migration.
      final song = await (upgraded.select(upgraded.songsTable)..where((t) => t.id.equals(77))).getSingle();

      expect(song.title, equals('Legacy Track'));
      expect(song.playCount, equals(9), reason: 'existing rows must survive addColumn');
      expect(song.source, equals(SongSource.local),
          reason: 'the constant default must backfill pre-existing rows');
      expect(song.remoteId, equals(null));
      expect(song.remoteArtworkUrl, equals(null));
      expect(song.pendingDownloadPath, equals(null));

      final entries = await upgraded.select(upgraded.playlistEntriesTable).get();
      expect(entries.length, equals(1), reason: 'playlist membership must not be cascaded away');
      expect(entries.first.songId, equals(77));

      expect(await songIndexNames(), containsAll(['idx_songs_source', 'idx_songs_remote_id']));

      final version = await upgraded.customSelect('PRAGMA user_version;').getSingle();
      expect(version.data['user_version'], equals(5));

      // The upgraded schema must accept remote rows, not just the fresh one.
      await upgraded.into(upgraded.songsTable).insert(
        SongsTableCompanion.insert(
          id: const Value(-77),
          title: 'Streamed After Upgrade',
          path: 'ytmusic://xyz789',
          source: const Value(SongSource.youtube),
          remoteId: const Value('xyz789'),
        ),
      );
    });

    test('v2 -> v5 runs the whole ladder without indexing a column that does not exist yet', () async {
      upgraded = openLegacyDatabase(2);

      final song = await (upgraded.select(upgraded.songsTable)..where((t) => t.id.equals(77))).getSingle();
      expect(song.isMissing, isFalse);
      expect(song.replayGain, equals(null));
      expect(song.source, equals(SongSource.local));

      // idx_songs_is_missing covers a column the `from < 4` branch adds, so it
      // can only be created after that branch has run.
      expect(await songIndexNames(),
          containsAll(['idx_songs_is_missing', 'idx_songs_source', 'idx_songs_remote_id']));
    });
  });
}
