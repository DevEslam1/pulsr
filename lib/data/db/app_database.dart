// lib/data/db/app_database.dart
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:injectable/injectable.dart';
import '../../core/utils/error_logger.dart';
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

  /// Set true when the FTS rebuild during migration failed, so the
  /// search index may be incomplete and tracks can be unfindable.
  /// Surfaced instead of only printed (defect 08-04 / 05-01).
  /// The search path calls [repairFtsIndex] once per session on FTS error.
  static bool ftsRebuildFailed = false;

  /// Best-effort FTS repair: recreates the index tables/triggers and
  /// rebuilds. Returns true on success. Safe when healthy. Once per session.
  static bool _ftsRepairAttempted = false;
  Future<bool> repairFtsIndex() async {
    if (_ftsRepairAttempted) return !ftsRebuildFailed;
    _ftsRepairAttempted = true;
    try {
      await _createFtsTable(customStatement);
      await customStatement(
          "INSERT INTO songs_fts(songs_fts) VALUES('rebuild');");
      ftsRebuildFailed = false;
      return true;
    } catch (_) {
      return false;
    }
  }
  @factoryMethod
  AppDatabase() : super(driftDatabase(name: 'pulsr_music_db'));

  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 11;

  static Future<void> _createFtsTable(
      Future<void> Function(String) executeSql) async {
    await executeSql(
        "CREATE VIRTUAL TABLE IF NOT EXISTS songs_fts USING fts5(title, artist, album, content='songs', content_rowid='id', tokenize='unicode61 remove_diacritics 1');");
    await executeSql(
        "CREATE TRIGGER IF NOT EXISTS songs_fts_insert AFTER INSERT ON songs BEGIN INSERT INTO songs_fts(rowid, title, artist, album) VALUES (new.id, new.title, new.artist, new.album); END;");
    await executeSql(
        "CREATE TRIGGER IF NOT EXISTS songs_fts_delete AFTER DELETE ON songs BEGIN INSERT INTO songs_fts(songs_fts, rowid, title, artist, album) VALUES('delete', old.id, old.title, old.artist, old.album); END;");
    await executeSql(
        "CREATE TRIGGER IF NOT EXISTS songs_fts_update AFTER UPDATE ON songs BEGIN INSERT INTO songs_fts(songs_fts, rowid, title, artist, album) VALUES('delete', old.id, old.title, old.artist, old.album); INSERT INTO songs_fts(rowid, title, artist, album) VALUES (new.id, new.title, new.artist, new.album); END;");
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

  /// Integrity + hot-path indexes (v11). All IF NOT EXISTS so re-runs are
  /// free. UNIQUEs enforce at the DB level what was previously only an
  /// app-side read-then-insert race (dup paths, dup playlist members).
  static Future<void> _createV11Constraints(
      Future<void> Function(String) executeSql) async {
    // The UNIQUE index below cannot be created over pre-existing duplicate
    // local rows (the very duplicates the scanner's dedup SQL removes) and a
    // failure here aborts the whole upgrade, leaving the DB unopenable. Sweep
    // duplicates — and any rows left dangling — before indexing.
    try {
      // Collapse duplicate local rows for the exact (path, cue window) the
      // UNIQUE index below covers. Grouping by lower(path) also dedups
      // case-variant paths. Runs before the index so a legacy duplicate can
      // never abort the upgrade and leave the database unopenable. Re-point
      // child rows to the surviving id first so no membership/history is lost.
      await executeSql(
        "UPDATE playlist_entries SET song_id = (SELECT MIN(s2.id) FROM songs s2 "
        "WHERE s2.source = 'local' AND s2.path != '' "
        "AND lower(s2.path) = lower((SELECT s.path FROM songs s WHERE s.id = playlist_entries.song_id)) "
        "AND ifnull(s2.cue_start_ms, -1) = ifnull((SELECT s.cue_start_ms FROM songs s WHERE s.id = playlist_entries.song_id), -1)) "
        "WHERE song_id IN (SELECT id FROM songs WHERE source = 'local' AND path != '') "
        "AND song_id NOT IN (SELECT MIN(id) FROM songs WHERE source = 'local' AND path != '' "
        "GROUP BY lower(path), ifnull(cue_start_ms, -1));",
      );
      await executeSql(
        "UPDATE queue_items SET song_id = (SELECT MIN(s2.id) FROM songs s2 "
        "WHERE s2.source = 'local' AND s2.path != '' "
        "AND lower(s2.path) = lower((SELECT s.path FROM songs s WHERE s.id = queue_items.song_id)) "
        "AND ifnull(s2.cue_start_ms, -1) = ifnull((SELECT s.cue_start_ms FROM songs s WHERE s.id = queue_items.song_id), -1)) "
        "WHERE song_id IN (SELECT id FROM songs WHERE source = 'local' AND path != '') "
        "AND song_id NOT IN (SELECT MIN(id) FROM songs WHERE source = 'local' AND path != '' "
        "GROUP BY lower(path), ifnull(cue_start_ms, -1));",
      );
      await executeSql(
        "UPDATE play_history SET song_id = (SELECT MIN(s2.id) FROM songs s2 "
        "WHERE s2.source = 'local' AND s2.path != '' "
        "AND lower(s2.path) = lower((SELECT s.path FROM songs s WHERE s.id = play_history.song_id)) "
        "AND ifnull(s2.cue_start_ms, -1) = ifnull((SELECT s.cue_start_ms FROM songs s WHERE s.id = play_history.song_id), -1)) "
        "WHERE song_id IN (SELECT id FROM songs WHERE source = 'local' AND path != '') "
        "AND song_id NOT IN (SELECT MIN(id) FROM songs WHERE source = 'local' AND path != '' "
        "GROUP BY lower(path), ifnull(cue_start_ms, -1));",
      );
      await executeSql(
        "DELETE FROM songs WHERE source = 'local' AND path != '' "
        "AND id NOT IN (SELECT MIN(id) FROM songs WHERE source = 'local' AND path != '' "
        "GROUP BY lower(path), ifnull(cue_start_ms, -1));",
      );
      // Duplicate memberships are the pre-v11 read-then-insert race; keep the
      // lowest id so the UNIQUE index can be created.
      await executeSql(
          'DELETE FROM playlist_entries WHERE id NOT IN ('
          'SELECT MIN(id) FROM playlist_entries GROUP BY playlist_id, song_id);');
      await executeSql(
          'DELETE FROM playlist_entries WHERE song_id NOT IN (SELECT id FROM songs);');
      await executeSql(
          'DELETE FROM queue_items WHERE song_id NOT IN (SELECT id FROM songs);');
      await executeSql(
          'DELETE FROM play_history WHERE song_id NOT IN (SELECT id FROM songs);');
    } catch (_) {}
    // Local file rows: one row per (lowercased path, cue window). YouTube
    // sentinel rows (ytmusic://) are excluded — many share a path prefix.
    await executeSql(
      "CREATE UNIQUE INDEX IF NOT EXISTS idx_songs_path_cue ON songs (path, ifnull(cue_start_ms, -1)) WHERE source = 'local';",
    );
    // One membership per (playlist, song); insertOrIgnore turns a race into
    // a no-op instead of a duplicate row.
    await executeSql(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_playlist_entries_unique ON playlist_entries (playlist_id, song_id);',
    );
    await executeSql(
        'CREATE INDEX IF NOT EXISTS idx_songs_uri ON songs (uri);');
    await executeSql(
        'CREATE INDEX IF NOT EXISTS idx_songs_cue ON songs (cue_file, cue_start_ms);');
    await executeSql(
        'CREATE INDEX IF NOT EXISTS idx_songs_pending_dl ON songs (pending_download_path);');
    await executeSql(
        'CREATE INDEX IF NOT EXISTS idx_playlists_name ON playlists (name);');
    await executeSql(
        'CREATE INDEX IF NOT EXISTS idx_songs_title_nocase ON songs (title COLLATE NOCASE);');
    await executeSql(
        'CREATE INDEX IF NOT EXISTS idx_songs_artist_nocase ON songs (artist COLLATE NOCASE);');
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
          await _createIndexes(customStatement);
          await _createRemoteSourceIndexes(customStatement);
          await _createV11Constraints(customStatement);
          await _createFtsTable(customStatement);
        },
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            await m.createTable(excludedFoldersTable);
          }
          // v3 shipped no schema change; explicit step so a future v3
          // column is never silently skipped by the ladder below.
          if (from < 3) {
            // No-op: reserved.
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
            // Backfill existing rows
            try {
              await customStatement(
                  "INSERT INTO songs_fts(songs_fts) VALUES('rebuild');");
            } catch (e, st) {
              // Migration must not fail the open, but silence hides an
              // empty search index. Logged for diagnostics.
              ftsRebuildFailed = true;
              ErrorLogger.log(
                'songs_fts rebuild failed during migration; the search index '
                'may be incomplete',
                error: e,
                stackTrace: st,
                category: 'Database',
              );
            }
          }
          if (from < 10) {
            if (!await hasColumn('songs', 'cue_start_ms')) {
              await m.addColumn(songsTable, songsTable.cueStartMs);
            }
            if (!await hasColumn('songs', 'cue_end_ms')) {
              await m.addColumn(songsTable, songsTable.cueEndMs);
            }
            if (!await hasColumn('songs', 'cue_file')) {
              await m.addColumn(songsTable, songsTable.cueFile);
            }
          }
          if (from < 11) {
            await _createV11Constraints(customStatement);
            // Legacy seeds/clients wrote epoch 0 into DateTime columns;
            // cloud sync compares these against server timestamps, so
            // backfill 1970 rows to now rather than syncing bogus dates.
            try {
              final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
              await customStatement(
                  'UPDATE playlists SET created_at = $now WHERE created_at <= 0;');
              await customStatement(
                  'UPDATE playlists SET updated_at = $now WHERE updated_at <= 0;');
              await customStatement(
                  'UPDATE playlist_entries SET added_at = $now WHERE added_at <= 0;');
            } catch (_) {}
          }
          // Must run after every addColumn above: several indexes cover columns a
          // later branch introduces, so creating them mid-ladder fails on an older
          // database. Every statement is IF NOT EXISTS, so re-running is free.
          await _createIndexes(customStatement);
          await _createRemoteSourceIndexes(customStatement);
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON;');
          await customStatement('PRAGMA journal_mode = WAL;');
          await customStatement('PRAGMA synchronous = NORMAL;');
          await customStatement('PRAGMA case_sensitive_like = OFF;');
        },
      );
}
