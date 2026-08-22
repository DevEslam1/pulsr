import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';

void main() {
  group('Drift Schema Migration Tests', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('Fresh database opens at schemaVersion 4 and has all indexes', () async {
      expect(db.schemaVersion, equals(4));

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
}
