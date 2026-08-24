// test/db/legacy_schema.dart
//
// Hand-written DDL for historical `songs` schemas. drift has no generated
// snapshot of older versions, so testing `onUpgrade` requires seeding a raw
// database that looks the way a real user's file does before the migration.
//
// Column names and defaults must match what drift generated at that version --
// if they drift apart, the migration tests stop being representative.
import 'package:drift/native.dart';
import 'package:pulsr/data/db/app_database.dart';

String _songsDdl({required bool withV4Columns}) => '''
CREATE TABLE songs (
  id INTEGER NOT NULL,
  title TEXT NOT NULL,
  artist TEXT NOT NULL DEFAULT 'Unknown Artist',
  artist_id INTEGER,
  album TEXT NOT NULL DEFAULT 'Unknown Album',
  album_id INTEGER,
  duration_ms INTEGER NOT NULL DEFAULT 0,
  path TEXT NOT NULL,
  uri TEXT,
  track_number INTEGER,
  disc_number INTEGER,
  year INTEGER,
  date_added INTEGER,
  genre TEXT,
  is_favorite INTEGER NOT NULL DEFAULT 0,
  ${withV4Columns ? 'is_missing INTEGER NOT NULL DEFAULT 0,\n  replay_gain REAL,' : ''}
  play_count INTEGER NOT NULL DEFAULT 0,
  last_played INTEGER,
  last_position_ms INTEGER NOT NULL DEFAULT 0,
  artwork_uri TEXT,
  file_size INTEGER,
  PRIMARY KEY (id)
);
''';

const _otherTablesDdl = <String>[
  '''
CREATE TABLE albums (
  id INTEGER NOT NULL,
  title TEXT NOT NULL,
  artist TEXT NOT NULL DEFAULT 'Unknown Artist',
  artist_id INTEGER,
  song_count INTEGER NOT NULL DEFAULT 0,
  artwork_uri TEXT,
  year INTEGER,
  PRIMARY KEY (id)
);
''',
  '''
CREATE TABLE artists (
  id INTEGER NOT NULL,
  name TEXT NOT NULL,
  song_count INTEGER NOT NULL DEFAULT 0,
  album_count INTEGER NOT NULL DEFAULT 0,
  artwork_uri TEXT,
  PRIMARY KEY (id)
);
''',
  '''
CREATE TABLE playlists (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  is_smart INTEGER NOT NULL DEFAULT 0,
  smart_criteria TEXT
);
''',
  '''
CREATE TABLE playlist_entries (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  playlist_id INTEGER NOT NULL REFERENCES playlists (id) ON DELETE CASCADE,
  song_id INTEGER NOT NULL REFERENCES songs (id) ON DELETE CASCADE,
  order_index INTEGER NOT NULL,
  added_at INTEGER NOT NULL
);
''',
  '''
CREATE TABLE play_history (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  song_id INTEGER NOT NULL REFERENCES songs (id) ON DELETE CASCADE,
  played_at INTEGER NOT NULL,
  completed INTEGER NOT NULL DEFAULT 0
);
''',
  '''
CREATE TABLE queue_items (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  song_id INTEGER NOT NULL REFERENCES songs (id) ON DELETE CASCADE,
  order_index INTEGER NOT NULL,
  is_current INTEGER NOT NULL DEFAULT 0,
  position_ms INTEGER NOT NULL DEFAULT 0
);
''',
];

const _excludedFoldersDdl = '''
CREATE TABLE excluded_folders (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  folder_path TEXT NOT NULL UNIQUE,
  added_at INTEGER NOT NULL
);
''';

/// Opens an [AppDatabase] over an in-memory database pre-seeded with the schema
/// as of [version], so drift runs `onUpgrade(from: version, to: schemaVersion)`.
///
/// Seeds one song plus a playlist containing it, so a migration that drops or
/// recreates `songs` is caught as data loss rather than passing silently.
AppDatabase openLegacyDatabase(int version) {
  return AppDatabase.forTesting(
    NativeDatabase.memory(
      setup: (raw) {
        raw.execute(_songsDdl(withV4Columns: version >= 4));
        for (final ddl in _otherTablesDdl) {
          raw.execute(ddl);
        }
        // excluded_folders arrived in v2, so a v1 database must not have it.
        if (version >= 2) raw.execute(_excludedFoldersDdl);

        raw.execute(
          "INSERT INTO songs (id, title, artist, album, duration_ms, path, play_count) "
          "VALUES (77, 'Legacy Track', 'Legacy Artist', 'Legacy Album', 210000, '/music/legacy.mp3', 9);",
        );
        raw.execute(
          "INSERT INTO playlists (id, name, created_at, updated_at) VALUES (1, 'Legacy Mix', 0, 0);",
        );
        raw.execute(
          'INSERT INTO playlist_entries (playlist_id, song_id, order_index, added_at) VALUES (1, 77, 0, 0);',
        );

        raw.execute('PRAGMA user_version = $version;');
      },
    ),
  );
}
