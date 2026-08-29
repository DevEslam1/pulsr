// lib/data/db/app_database.dart
import 'package:drift/drift.dart';
import '../../core/utils/error_logger.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:injectable/injectable.dart';
import 'tables.dart';

export 'tables.dart' show SongSource;

part 'app_database.g.dart';

@singleton
@DriftDatabase(tables: [
  SongsTable,
  AlbumsTable,
  ArtistsTable,
  PlaylistsTable,
  PlaylistEntriesTable,
  PlayHistoryTable,
  QueueItemsTable,
  ExcludedFoldersTable,
])
class AppDatabase extends _$AppDatabase {
  @factoryMethod
  AppDatabase() : super(driftDatabase(name: 'pulsr_music_db'));

  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 10;

  static Future<void> _createFtsTable(
      Future<void> Function(String) executeSql) async {
    await executeSql(
        "CREATE VIRTUAL TABLE IF NOT EXISTS songs_fts USING fts5(title, artist, album, content='songs', content_rowid='id', tokenize='unicode61 remove_diacritics 1');");
    await executeSql(
        "CREATE TRIGGER IF NOT EXISTS songs_fts_insert AFTER INSERT ON songs BEGIN INSERT INTO songs_fts(rowid, title, artist, album) VALUES (new.id, new.title, new.artist, new.album); END;");
    await executeSql(
        "CREATE TRIGGER IF NOT EXISTS songs_fts_delete AFTER DELETE ON songs BEGIN INSERT INTO songs_fts(songs_fts, rowid, title, artist, album) VALUES('delete', old.id, old.title, old.artist, old.album); END;");
    await executeSql(
        "CREATE TRIGGER IF NOT EXISTS songs_fts_update AFTER UPDATE OF title, artist, album ON songs BEGIN INSERT INTO songs_fts(songs_fts, rowid, title, artist, album) VALUES('delete', old.id, old.title, old.artist, old.album); INSERT INTO songs_fts(rowid, title, artist, album) VALUES (new.id, new.title, new.artist, new.album); END;");
  }

  static Future<void> _createIndexes(
      Future<void> Function(String) executeSql) async {
    await executeSql(
        'CREATE INDEX IF NOT EXISTS idx_songs_title ON songs (title);');
    await executeSql(
        'CREATE INDEX IF NOT EXISTS idx_songs_artist ON songs (artist);');
    await executeSql(
        'CREATE INDEX IF NOT EXISTS idx_songs_album_id ON songs (album_id);');
    await executeSql(
        'CREATE INDEX IF NOT EXISTS idx_songs_artist_id ON songs (artist_id);');
    await executeSql(
        'CREATE INDEX IF NOT EXISTS idx_songs_path ON songs (path);');
    await executeSql(
        "CREATE INDEX IF NOT EXISTS idx_songs_path_nocase ON songs (path COLLATE NOCASE) WHERE path != '' AND path NOT LIKE 'ytmusic://%';");
    await executeSql(
        'CREATE INDEX IF NOT EXISTS idx_songs_genre ON songs (genre);');
    await executeSql(
        'CREATE INDEX IF NOT EXISTS idx_songs_year ON songs (year);');
    await executeSql(
        'CREATE INDEX IF NOT EXISTS idx_songs_is_favorite ON songs (is_favorite);');
    await executeSql(
        'CREATE INDEX IF NOT EXISTS idx_songs_is_missing ON songs (is_missing);');
    await executeSql(
        'CREATE INDEX IF NOT EXISTS idx_songs_is_downloaded ON songs (is_downloaded);');
    await executeSql(
        'CREATE INDEX IF NOT EXISTS idx_songs_last_played ON songs (last_played);');
    await executeSql(
        'CREATE INDEX IF NOT EXISTS idx_songs_date_added ON songs (date_added);');
    await executeSql(
        'CREATE INDEX IF NOT EXISTS idx_songs_play_count ON songs (play_count);');
    await executeSql(
        'CREATE INDEX IF NOT EXISTS idx_playlist_entries_song_id ON playlist_entries (song_id);');
    await executeSql(
        'CREATE INDEX IF NOT EXISTS idx_playlist_entries_playlist_id ON playlist_entries (playlist_id);');
    await executeSql(
        'CREATE INDEX IF NOT EXISTS idx_play_history_song_id ON play_history (song_id);');
    await executeSql(
        'CREATE INDEX IF NOT EXISTS idx_play_history_played_at ON play_history (played_at);');
    await executeSql(
        'CREATE INDEX IF NOT EXISTS idx_queue_items_song_id ON queue_items (song_id);');
    await executeSql(
        'CREATE INDEX IF NOT EXISTS idx_queue_items_order_index ON queue_items (order_index);');
  }

  static Future<void> _createRemoteSourceIndexes(
      Future<void> Function(String) executeSql) async {
    await executeSql(
        'CREATE INDEX IF NOT EXISTS idx_songs_source ON songs (source);');
    await executeSql(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_songs_remote_id ON songs (remote_id) WHERE remote_id IS NOT NULL;',
    );
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
          await _createIndexes(customStatement);
          await _createRemoteSourceIndexes(customStatement);
          await _createFtsTable(customStatement);
        },
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            await m.createTable(excludedFoldersTable);
          }
          if (from < 4) {
            await m.addColumn(songsTable, songsTable.isMissing);
          }
          if (from < 5) {
            await m.addColumn(songsTable, songsTable.source);
            await m.addColumn(songsTable, songsTable.remoteId);
            await m.addColumn(songsTable, songsTable.remoteArtworkUrl);
            await m.addColumn(songsTable, songsTable.pendingDownloadPath);
          }
          if (from < 6) {
            await m.addColumn(songsTable, songsTable.sampleRate);
            await m.addColumn(songsTable, songsTable.bitDepth);
            await m.addColumn(songsTable, songsTable.bitrateKbps);
            await m.addColumn(songsTable, songsTable.codec);
          }
          Future<bool> hasColumn(String table, String column) async {
            try {
              final rows =
                  await customSelect('PRAGMA table_info($table);').get();
              return rows.any((r) => r.data['name'] == column);
            } catch (_) {
              return false; // Table doesn't exist yet
            }
          }

          if (from < 7) {
            if (!await hasColumn('songs', 'replay_gain_track')) {
              await m.addColumn(songsTable, songsTable.replayGainTrack);
            }
            if (!await hasColumn('songs', 'replay_gain_album')) {
              await m.addColumn(songsTable, songsTable.replayGainAlbum);
            }
            if (!await hasColumn('songs', 'replay_gain_track_peak')) {
              await m.addColumn(songsTable, songsTable.replayGainTrackPeak);
            }
            if (!await hasColumn('songs', 'replay_gain_album_peak')) {
              await m.addColumn(songsTable, songsTable.replayGainAlbumPeak);
            }
            if (!await hasColumn('songs', 'is_downloaded')) {
              await m.addColumn(songsTable, songsTable.isDownloaded);
            }
            try {
              if (await hasColumn('songs', 'replay_gain')) {
                await customStatement(
                    'UPDATE songs SET replay_gain_track = replay_gain WHERE replay_gain IS NOT NULL;');
              }
            } catch (_) {}
          }
          if (from < 8) {
            if (!await hasColumn('songs', 'loudness_range')) {
              await m.addColumn(songsTable, songsTable.loudnessRange);
            }
          }
          if (from < 9) {
            await _createFtsTable(customStatement);
            try {
              await customStatement(
                  "INSERT INTO songs_fts(songs_fts) VALUES('rebuild');");
            } catch (_) {}
          }
          if (from < 10) {
            // Add NOCASE path index for duplicate prevention (10/10 hardening)
            try {
              await customStatement(
                  "CREATE INDEX IF NOT EXISTS idx_songs_path_nocase ON songs (path COLLATE NOCASE) WHERE path != '' AND path NOT LIKE 'ytmusic://%';");
            } catch (_) {}
            // FTS rebuild is cheap and fixes any corrupt trigger from v9
            try {
              await customStatement(
                  "INSERT INTO songs_fts(songs_fts) VALUES('rebuild');");
            } catch (_) {}
          }
          await _createIndexes(customStatement);
          await _createRemoteSourceIndexes(customStatement);
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON;');
          await customStatement('PRAGMA journal_mode = WAL;');
          await customStatement('PRAGMA synchronous = NORMAL;');
          await customStatement('PRAGMA case_sensitive_like = OFF;');
          // SELF-HEAL: re-assert indexes on every open. All statements are
          // CREATE ... IF NOT EXISTS (near-zero cost), and this guarantees
          // installs created before the idx_songs_path_nocase SQL fix gain
          // the corrected index without a schema bump.
          try {
            await _createIndexes(customStatement);
            await _createRemoteSourceIndexes(customStatement);
          } catch (e, st) {
            ErrorLogger.log('Index self-heal failed',
                error: e, stackTrace: st, category: 'Database');
          }
        },
      );
}
