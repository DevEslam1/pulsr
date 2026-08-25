// lib/data/db/tables.dart
import 'package:drift/drift.dart';

/// Allowed values for [SongsTable.source].
abstract final class SongSource {
  /// A file indexed by MediaStore. `path` points at the filesystem.
  static const String local = 'local';

  /// A YouTube track that has no local file yet. `path` holds a
  /// `ytmusic://<videoId>` sentinel, so any path-based feature must skip it.
  static const String youtube = 'youtube';
}

class SongsTable extends Table {
  @override
  String get tableName => 'songs';

  IntColumn get id => integer()();
  TextColumn get title => text()();
  TextColumn get artist => text().withDefault(const Constant('Unknown Artist'))();
  IntColumn get artistId => integer().nullable()();
  TextColumn get album => text().withDefault(const Constant('Unknown Album'))();
  IntColumn get albumId => integer().nullable()();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  TextColumn get path => text()();
  TextColumn get uri => text().nullable()();
  IntColumn get trackNumber => integer().nullable()();
  IntColumn get discNumber => integer().nullable()();
  IntColumn get year => integer().nullable()();
  /// Stored as timestamp (seconds or milliseconds since Unix epoch, consistent with MediaStore/on_audio_query).
  IntColumn get dateAdded => integer().nullable()();
  TextColumn get genre => text().nullable()();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  BoolColumn get isMissing => boolean().withDefault(const Constant(false))();
  RealColumn get replayGainTrack => real().nullable()();
  RealColumn get replayGainAlbum => real().nullable()();
  RealColumn get replayGainTrackPeak => real().nullable()();
  RealColumn get replayGainAlbumPeak => real().nullable()();
  IntColumn get playCount => integer().withDefault(const Constant(0))();
  IntColumn get lastPlayed => integer().nullable()();
  IntColumn get lastPositionMs => integer().withDefault(const Constant(0))();
  TextColumn get artworkUri => text().nullable()();
  IntColumn get fileSize => integer().nullable()();

  /// Real audio-header fields, read from the file via the tag channel and
  /// cached so the quality badge reflects actual metadata rather than a guess
  /// from the filename/extension. Null until a file has been enriched.
  IntColumn get sampleRate => integer().nullable()();
  IntColumn get bitDepth => integer().nullable()();
  IntColumn get bitrateKbps => integer().nullable()();
  /// Real container/codec from the header (e.g. FLAC, MP3, AAC, ALAC), used to
  /// gate lossless/Hi-Res so a renamed file cannot fake a higher tier.
  TextColumn get codec => text().nullable()();

  /// See [SongSource]. Rows that are not [SongSource.local] have no file on
  /// disk, so scanner cleanup and every path-derived query must exclude them.
  TextColumn get source => text().withDefault(const Constant(SongSource.local))();

  /// YouTube video id. Kept after a download completes so the same video is
  /// not fetched twice.
  TextColumn get remoteId => text().nullable()();
  TextColumn get remoteArtworkUrl => text().nullable()();

  /// Destination a download is writing to, used to match the row MediaStore
  /// creates once the file lands.
  TextColumn get pendingDownloadPath => text().nullable()();

  /// Explicit flag indicating whether this song was downloaded from YouTube Music / Online.
  BoolColumn get isDownloaded => boolean().withDefault(const Constant(false)).nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class AlbumsTable extends Table {
  @override
  String get tableName => 'albums';

  IntColumn get id => integer()();
  TextColumn get title => text()();
  TextColumn get artist => text().withDefault(const Constant('Unknown Artist'))();
  IntColumn get artistId => integer().nullable()();
  IntColumn get songCount => integer().withDefault(const Constant(0))();
  TextColumn get artworkUri => text().nullable()();
  IntColumn get year => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class ArtistsTable extends Table {
  @override
  String get tableName => 'artists';

  IntColumn get id => integer()();
  TextColumn get name => text()();
  IntColumn get songCount => integer().withDefault(const Constant(0))();
  IntColumn get albumCount => integer().withDefault(const Constant(0))();
  TextColumn get artworkUri => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class PlaylistsTable extends Table {
  @override
  String get tableName => 'playlists';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isSmart => boolean().withDefault(const Constant(false))();
  TextColumn get smartCriteria => text().nullable()();
}

class PlaylistEntriesTable extends Table {
  @override
  String get tableName => 'playlist_entries';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get playlistId => integer().references(PlaylistsTable, #id, onDelete: KeyAction.cascade)();
  IntColumn get songId => integer().references(SongsTable, #id, onDelete: KeyAction.cascade)();
  IntColumn get orderIndex => integer()();
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();
}

class PlayHistoryTable extends Table {
  @override
  String get tableName => 'play_history';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get songId => integer().references(SongsTable, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get playedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
}

class QueueItemsTable extends Table {
  @override
  String get tableName => 'queue_items';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get songId => integer().references(SongsTable, #id, onDelete: KeyAction.cascade)();
  IntColumn get orderIndex => integer()();
  BoolColumn get isCurrent => boolean().withDefault(const Constant(false))();
  IntColumn get positionMs => integer().withDefault(const Constant(0))();
}

class ExcludedFoldersTable extends Table {
  @override
  String get tableName => 'excluded_folders';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get folderPath => text().unique()();
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();
}

