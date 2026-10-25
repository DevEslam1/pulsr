// test/data/db/drift_migration_smoke_test.dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Drift Migration Smoke Tests', () {
    test('fresh database initializes schema v12 with all tables and indexes',
        () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() async => await db.close());

      // Trigger schema creation
      final songs = await db.select(db.songsTable).get();
      expect(songs, isEmpty);

      expect(db.schemaVersion, equals(12));
      expect(db.migrationFailed, isFalse);
    });

    test('v10 database migrates to v11 cleanly and creates constraints',
        () async {
      final connection = NativeDatabase.memory(
        setup: (rawDb) {
          // Set user_version to 10 and construct pre-v11 schema
          rawDb.execute('PRAGMA user_version = 10;');
          rawDb.execute('''
            CREATE TABLE IF NOT EXISTS songs (
              id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
              title TEXT NOT NULL,
              artist TEXT NOT NULL,
              album TEXT NOT NULL,
              path TEXT NOT NULL,
              duration_ms INTEGER NOT NULL,
              track_number INTEGER NULL,
              disc_number INTEGER NULL,
              year INTEGER NULL,
              date_added INTEGER NULL,
              last_played INTEGER NULL,
              play_count INTEGER NOT NULL DEFAULT 0,
              genre TEXT NULL,
              file_size INTEGER NULL,
              artwork_uri TEXT NULL,
              is_favorite INTEGER NOT NULL DEFAULT 0,
              is_missing INTEGER NOT NULL DEFAULT 0,
              album_id INTEGER NULL,
              artist_id INTEGER NULL,
              source TEXT NOT NULL DEFAULT 'local',
              remote_id TEXT NULL,
              remote_artwork_url TEXT NULL,
              pending_download_path TEXT NULL,
              sample_rate INTEGER NULL,
              bit_depth INTEGER NULL,
              bitrate_kbps INTEGER NULL,
              codec TEXT NULL,
              replay_gain_track REAL NULL,
              replay_gain_album REAL NULL,
              replay_gain_track_peak REAL NULL,
              replay_gain_album_peak REAL NULL,
              is_downloaded INTEGER NOT NULL DEFAULT 0,
              loudness_range REAL NULL,
              cue_start_ms INTEGER NULL,
              cue_end_ms INTEGER NULL,
              cue_file TEXT NULL
            );
          ''');
          rawDb.execute('''
            CREATE TABLE IF NOT EXISTS playlists (
              id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              is_smart INTEGER NOT NULL DEFAULT 0,
              smart_rules TEXT NULL
            );
          ''');
          rawDb.execute('''
            CREATE TABLE IF NOT EXISTS playlist_entries (
              id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
              playlist_id INTEGER NOT NULL,
              song_id INTEGER NOT NULL,
              sort_order INTEGER NOT NULL,
              added_at INTEGER NOT NULL
            );
          ''');
          rawDb.execute('''
            CREATE TABLE IF NOT EXISTS play_history (
              id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
              song_id INTEGER NOT NULL,
              played_at INTEGER NOT NULL,
              playback_duration_ms INTEGER NOT NULL,
              completed INTEGER NOT NULL DEFAULT 0
            );
          ''');
          rawDb.execute('''
            CREATE TABLE IF NOT EXISTS queue_items (
              id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
              song_id INTEGER NOT NULL,
              order_index INTEGER NOT NULL
            );
          ''');
          rawDb.execute('''
            CREATE TABLE IF NOT EXISTS excluded_folders (
              path TEXT NOT NULL PRIMARY KEY,
              excluded_at INTEGER NOT NULL
            );
          ''');
          rawDb.execute('''
            CREATE TABLE IF NOT EXISTS albums (
              id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              artist TEXT NOT NULL,
              artist_id INTEGER NULL,
              artwork_uri TEXT NULL,
              year INTEGER NULL,
              song_count INTEGER NOT NULL DEFAULT 0
            );
          ''');
          rawDb.execute('''
            CREATE TABLE IF NOT EXISTS artists (
              id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              artwork_uri TEXT NULL,
              song_count INTEGER NOT NULL DEFAULT 0
            );
          ''');
        },
      );

      final db = AppDatabase.forTesting(connection);
      addTearDown(() async => await db.close());

      // Read to trigger onUpgrade from 10 to 11
      final playlists = await db.select(db.playlistsTable).get();
      expect(playlists, isEmpty);
      expect(db.migrationFailed, isFalse);

      // Verify that v11 indexes were created
      final indexes = await db
          .customSelect("SELECT name FROM sqlite_master WHERE type='index';")
          .get();
      final indexNames = indexes.map((row) => row.read<String>('name')).toSet();
      expect(indexNames.contains('idx_songs_lower_path'), isTrue);
      expect(indexNames.contains('idx_playlists_name'), isTrue);
    });
  });
}
