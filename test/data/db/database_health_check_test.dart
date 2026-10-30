// test/data/db/database_health_check_test.dart
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';

void main() {
  group('DatabaseHealthCheck', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('fresh in-memory database reports healthy', () async {
      final report = await DatabaseHealthCheck(db).checkHealth();

      expect(report.isHealthy, isTrue);
      expect(report.integrityIssues, isEmpty);
      expect(report.foreignKeyViolations, isEmpty);
      expect(report.totalSongs, 0);
      expect(report.totalPlaylists, 0);
      expect(report.totalHistoryEntries, 0);
      expect(report.databaseSizeBytes, greaterThan(0));
      expect(report.ftsHealthy, isTrue);
    });

    test('counts persisted songs and keeps integrity clean', () async {
      await db.into(db.songsTable).insert(SongsTableCompanion.insert(
            id: const Value(1),
            title: 'Health Check Song',
            path: '/music/health.mp3',
          ));
      await db.into(db.songsTable).insert(SongsTableCompanion.insert(
            id: const Value(2),
            title: 'Second Song',
            path: '/music/second.mp3',
          ));

      final report = await DatabaseHealthCheck(db).checkHealth();

      expect(report.isHealthy, isTrue);
      expect(report.totalSongs, 2);
      expect(report.integrityIssues, isEmpty);
    });

    test('report.toMap exposes every diagnostic field', () async {
      final report = await DatabaseHealthCheck(db).checkHealth();
      final map = report.toMap();

      expect(
          map.keys,
          containsAll(<String>[
            'isHealthy',
            'integrityIssues',
            'foreignKeyViolations',
            'totalSongs',
            'totalPlaylists',
            'totalHistoryEntries',
            'databaseSizeBytes',
            'ftsHealthy',
          ]));
    });

    test('detects an index that drifted from the content table', () async {
      // Simulate the classic FTS drift: rows written while the sync trigger is
      // missing (e.g. a partial migration). COUNT(*) reads the content table
      // and stays green; the integrity-check is what notices.
      await db.customStatement('DROP TRIGGER songs_fts_insert;');
      await db.into(db.songsTable).insert(SongsTableCompanion.insert(
            id: const Value(1),
            title: 'Unindexed Song',
            path: '/music/unindexed.mp3',
          ));

      final report = await DatabaseHealthCheck(db).checkHealth();

      expect(report.totalSongs, 1,
          reason: 'the content table still counts the row');
      expect(report.ftsHealthy, isFalse,
          reason: 'an index missing a row must not be reported as healthy');
    });
  });

  group('DatabaseMigrationValidator', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('fresh schema validates with no missing tables/columns/indexes',
        () async {
      final result = await DatabaseMigrationValidator(db).validateSchema();

      expect(result.missingTables, isEmpty);
      expect(result.missingColumns, isEmpty);
      expect(result.missingIndexes, isEmpty);
      expect(result.currentVersion, result.expectedVersion);
      expect(result.isValid, isTrue);
    });

    test('required tables cover the v12 online-playlist schema', () {
      expect(
        DatabaseMigrationValidator.requiredTables,
        containsAll(<String>['online_playlists', 'online_playlist_entries']),
      );
    });
  });
}
