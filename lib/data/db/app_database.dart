// lib/data/db/app_database.dart
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:injectable/injectable.dart';
import 'tables.dart';

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
  int get schemaVersion => 4;

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

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await _createIndexes(customStatement);
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        await m.createTable(excludedFoldersTable);
      }
      if (from < 3) {
        await _createIndexes(customStatement);
      }
      if (from < 4) {
        await m.addColumn(songsTable, songsTable.isMissing);
        await m.addColumn(songsTable, songsTable.replayGain);
        await _createIndexes(customStatement);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON;');
      await customStatement('PRAGMA journal_mode = WAL;');
      await customStatement('PRAGMA synchronous = NORMAL;');
    },
  );
}

