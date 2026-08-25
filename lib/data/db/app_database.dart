// lib/data/db/app_database.dart
import 'package:drift/drift.dart';
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
  int get schemaVersion => 7;

  static Future<void> _createIndexes(Future<void> Function(String) executeSql) async {
    await executeSql('CREATE INDEX IF NOT EXISTS idx_songs_title ON songs (title);');
    await executeSql('CREATE INDEX IF NOT EXISTS idx_songs_artist ON songs (artist);');
    await executeSql('CREATE INDEX IF NOT EXISTS idx_songs_album_id ON songs (album_id);');
    await executeSql('CREATE INDEX IF NOT EXISTS idx_songs_artist_id ON songs (artist_id);');
    await executeSql('CREATE INDEX IF NOT EXISTS idx_songs_path ON songs (path);');
    await executeSql('CREATE INDEX IF NOT EXISTS idx_songs_genre ON songs (genre);');
    await executeSql('CREATE INDEX IF NOT EXISTS idx_songs_year ON songs (year);');
    await executeSql('CREATE INDEX IF NOT EXISTS idx_songs_is_favorite ON songs (is_favorite);');
    await executeSql('CREATE INDEX IF NOT EXISTS idx_songs_is_missing ON songs (is_missing);');
    await executeSql('CREATE INDEX IF NOT EXISTS idx_songs_is_downloaded ON songs (is_downloaded);');
    await executeSql('CREATE INDEX IF NOT EXISTS idx_songs_last_played ON songs (last_played);');
    await executeSql('CREATE INDEX IF NOT EXISTS idx_songs_date_added ON songs (date_added);');
    await executeSql('CREATE INDEX IF NOT EXISTS idx_songs_play_count ON songs (play_count);');
    await executeSql('CREATE INDEX IF NOT EXISTS idx_playlist_entries_song_id ON playlist_entries (song_id);');
    await executeSql('CREATE INDEX IF NOT EXISTS idx_playlist_entries_playlist_id ON playlist_entries (playlist_id);');
    await executeSql('CREATE INDEX IF NOT EXISTS idx_play_history_song_id ON play_history (song_id);');
    await executeSql('CREATE INDEX IF NOT EXISTS idx_play_history_played_at ON play_history (played_at);');
    await executeSql('CREATE INDEX IF NOT EXISTS idx_queue_items_song_id ON queue_items (song_id);');
    await executeSql('CREATE INDEX IF NOT EXISTS idx_queue_items_order_index ON queue_items (order_index);');
  }

  static Future<void> _createRemoteSourceIndexes(Future<void> Function(String) executeSql) async {
    await executeSql('CREATE INDEX IF NOT EXISTS idx_songs_source ON songs (source);');
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
      if (from < 7) {
        await m.addColumn(songsTable, songsTable.replayGainTrack);
        await m.addColumn(songsTable, songsTable.replayGainAlbum);
        await m.addColumn(songsTable, songsTable.replayGainTrackPeak);
        await m.addColumn(songsTable, songsTable.replayGainAlbumPeak);
        try {
          await m.addColumn(songsTable, songsTable.isDownloaded);
        } catch (_) {}
        try {
          await customStatement('UPDATE songs SET replay_gain_track = replay_gain WHERE replay_gain IS NOT NULL;');
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
    },
  );
}

