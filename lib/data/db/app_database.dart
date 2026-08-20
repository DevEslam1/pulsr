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
  int get schemaVersion => 3;

  static Future<void> _createIndexes(Future<void> Function(String) executeSql) async {
    await executeSql('CREATE INDEX IF NOT EXISTS idx_songs_title ON songs (title);');
    await executeSql('CREATE INDEX IF NOT EXISTS idx_songs_artist ON songs (artist);');
    await executeSql('CREATE INDEX IF NOT EXISTS idx_songs_album_id ON songs (album_id);');
    await executeSql('CREATE INDEX IF NOT EXISTS idx_songs_is_favorite ON songs (is_favorite);');
    await executeSql('CREATE INDEX IF NOT EXISTS idx_playlist_entries_song_id ON playlist_entries (song_id);');
    await executeSql('CREATE INDEX IF NOT EXISTS idx_play_history_song_id ON play_history (song_id);');
    await executeSql('CREATE INDEX IF NOT EXISTS idx_queue_items_song_id ON queue_items (song_id);');
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
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

