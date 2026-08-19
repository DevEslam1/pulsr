// lib/data/repositories/music_repository.dart
import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import '../../core/errors/failures.dart';
import '../db/app_database.dart';

class MusicRepository {
  final AppDatabase _db;

  MusicRepository(this._db);

  // --- SONGS ---
  Stream<List<SongsTableData>> watchAllSongs({
    String sortBy = 'title',
    bool ascending = true,
    int? limit,
    int? offset,
    String? searchQuery,
    List<String> excludedFolders = const [],
  }) {
    final query = _db.select(_db.songsTable);

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final pattern = '%${searchQuery.trim().toLowerCase()}%';
      query.where((t) => t.title.lower().like(pattern) | t.artist.lower().like(pattern) | t.album.lower().like(pattern));
    }

    if (excludedFolders.isNotEmpty) {
      for (final folder in excludedFolders) {
        query.where((t) => t.path.like('$folder%').not());
      }
    }

    if (sortBy == 'title') {
      query.orderBy([(t) => OrderingTerm(expression: t.title, mode: ascending ? OrderingMode.asc : OrderingMode.desc)]);
    } else if (sortBy == 'artist') {
      query.orderBy([(t) => OrderingTerm(expression: t.artist, mode: ascending ? OrderingMode.asc : OrderingMode.desc)]);
    } else if (sortBy == 'dateAdded') {
      query.orderBy([(t) => OrderingTerm(expression: t.dateAdded, mode: ascending ? OrderingMode.asc : OrderingMode.desc)]);
    } else if (sortBy == 'duration') {
      query.orderBy([(t) => OrderingTerm(expression: t.durationMs, mode: ascending ? OrderingMode.asc : OrderingMode.desc)]);
    }

    if (limit != null) {
      query.limit(limit, offset: offset);
    }

    return query.watch();
  }

  Future<Either<AppFailure, List<SongsTableData>>> getAllSongs({
    String sortBy = 'title',
    bool ascending = true,
    int? limit,
    int? offset,
  }) async {
    try {
      final query = _db.select(_db.songsTable);
      if (sortBy == 'title') {
        query.orderBy([(t) => OrderingTerm(expression: t.title, mode: ascending ? OrderingMode.asc : OrderingMode.desc)]);
      } else if (sortBy == 'artist') {
        query.orderBy([(t) => OrderingTerm(expression: t.artist, mode: ascending ? OrderingMode.asc : OrderingMode.desc)]);
      }
      if (limit != null) {
        query.limit(limit, offset: offset);
      }
      final songs = await query.get();
      return Right(songs);
    } catch (e) {
      return Left(DatabaseFailure('Failed to fetch songs from database', e));
    }
  }

  Stream<List<SongsTableData>> watchFavorites() {
    return (_db.select(_db.songsTable)
          ..where((t) => t.isFavorite.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.title)]))
        .watch();
  }

  Stream<List<SongsTableData>> watchRecentlyPlayed({int limit = 20}) {
    return (_db.select(_db.songsTable)
          ..where((t) => t.lastPlayed.isNotNull())
          ..orderBy([(t) => OrderingTerm(expression: t.lastPlayed, mode: OrderingMode.desc)])
          ..limit(limit))
        .watch();
  }

  Stream<List<SongsTableData>> watchRecentlyAdded({int limit = 20}) {
    return (_db.select(_db.songsTable)
          ..orderBy([(t) => OrderingTerm(expression: t.dateAdded, mode: OrderingMode.desc)])
          ..limit(limit))
        .watch();
  }

  Stream<List<SongsTableData>> watchTopPlayed({int limit = 30}) {
    return (_db.select(_db.songsTable)
          ..where((t) => t.playCount.isBiggerThanValue(0))
          ..orderBy([(t) => OrderingTerm(expression: t.playCount, mode: OrderingMode.desc)])
          ..limit(limit))
        .watch();
  }

  Future<Either<AppFailure, bool>> toggleFavorite(int songId) async {
    try {
      final song = await (_db.select(_db.songsTable)..where((t) => t.id.equals(songId))).getSingleOrNull();
      if (song != null) {
        final nextVal = !song.isFavorite;
        await (_db.update(_db.songsTable)..where((t) => t.id.equals(songId)))
            .write(SongsTableCompanion(isFavorite: Value(nextVal)));
        return Right(nextVal);
      }
      return const Left(DatabaseFailure('Song not found'));
    } catch (e) {
      return Left(DatabaseFailure('Failed to toggle favorite', e));
    }
  }

  Future<void> recordPlayHistory(int songId, {bool completed = false}) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final song = await (_db.select(_db.songsTable)..where((t) => t.id.equals(songId))).getSingleOrNull();
      if (song != null) {
        await (_db.update(_db.songsTable)..where((t) => t.id.equals(songId))).write(
          SongsTableCompanion(
            playCount: Value(song.playCount + 1),
            lastPlayed: Value(now),
          ),
        );
        await _db.into(_db.playHistoryTable).insert(
          PlayHistoryTableCompanion.insert(
            songId: songId,
            completed: Value(completed),
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> updateLastPosition(int songId, int positionMs) async {
    try {
      await (_db.update(_db.songsTable)..where((t) => t.id.equals(songId))).write(
        SongsTableCompanion(lastPositionMs: Value(positionMs)),
      );
    } catch (_) {}
  }

  // --- ALBUMS ---
  Stream<List<AlbumsTableData>> watchAlbums() {
    return (_db.select(_db.albumsTable)..orderBy([(t) => OrderingTerm(expression: t.title)])).watch();
  }

  Stream<List<SongsTableData>> watchAlbumSongs(int albumId) {
    return (_db.select(_db.songsTable)
          ..where((t) => t.albumId.equals(albumId))
          ..orderBy([(t) => OrderingTerm(expression: t.trackNumber)]))
        .watch();
  }

  // --- ARTISTS ---
  Stream<List<ArtistsTableData>> watchArtists() {
    return (_db.select(_db.artistsTable)..orderBy([(t) => OrderingTerm(expression: t.name)])).watch();
  }

  Stream<List<SongsTableData>> watchArtistSongs(int artistId) {
    return (_db.select(_db.songsTable)..where((t) => t.artistId.equals(artistId))).watch();
  }

  Stream<List<AlbumsTableData>> watchArtistAlbums(int artistId) {
    return (_db.select(_db.albumsTable)..where((t) => t.artistId.equals(artistId))).watch();
  }

  // --- PLAYLISTS ---
  Stream<List<PlaylistsTableData>> watchPlaylists() {
    return (_db.select(_db.playlistsTable)..orderBy([(t) => OrderingTerm(expression: t.name)])).watch();
  }

  Future<Either<AppFailure, int>> createPlaylist(String name, {bool isSmart = false, String? smartCriteria}) async {
    try {
      final id = await _db.into(_db.playlistsTable).insert(
        PlaylistsTableCompanion.insert(
          name: name,
          isSmart: Value(isSmart),
          smartCriteria: Value(smartCriteria),
        ),
      );
      return Right(id);
    } catch (e) {
      return Left(DatabaseFailure('Failed to create playlist', e));
    }
  }

  Future<Either<AppFailure, void>> renamePlaylist(int playlistId, String newName) async {
    try {
      await (_db.update(_db.playlistsTable)..where((t) => t.id.equals(playlistId))).write(
        PlaylistsTableCompanion(
          name: Value(newName),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return const Right(null);
    } catch (e) {
      return Left(DatabaseFailure('Failed to rename playlist', e));
    }
  }

  Future<Either<AppFailure, void>> deletePlaylist(int playlistId) async {
    try {
      await (_db.delete(_db.playlistsTable)..where((t) => t.id.equals(playlistId))).go();
      return const Right(null);
    } catch (e) {
      return Left(DatabaseFailure('Failed to delete playlist', e));
    }
  }

  Stream<List<SongsTableData>> watchPlaylistSongs(int playlistId) {
    final query = _db.select(_db.playlistEntriesTable).join([
      innerJoin(_db.songsTable, _db.songsTable.id.equalsExp(_db.playlistEntriesTable.songId)),
    ])
      ..where(_db.playlistEntriesTable.playlistId.equals(playlistId))
      ..orderBy([OrderingTerm(expression: _db.playlistEntriesTable.orderIndex)]);

    return query.watch().map((rows) {
      return rows.map((row) => row.readTable(_db.songsTable)).toList();
    });
  }

  Future<Either<AppFailure, void>> addSongToPlaylist(int playlistId, int songId) async {
    try {
      final countExp = _db.playlistEntriesTable.id.count();
      final query = _db.selectOnly(_db.playlistEntriesTable)
        ..where(_db.playlistEntriesTable.playlistId.equals(playlistId))
        ..addColumns([countExp]);
      final count = await query.map((row) => row.read(countExp)).getSingle() ?? 0;

      await _db.into(_db.playlistEntriesTable).insert(
        PlaylistEntriesTableCompanion.insert(
          playlistId: playlistId,
          songId: songId,
          orderIndex: count,
        ),
      );
      return const Right(null);
    } catch (e) {
      return Left(DatabaseFailure('Failed to add song to playlist', e));
    }
  }

  Future<Either<AppFailure, void>> addSongsToPlaylist(int playlistId, List<int> songIds) async {
    try {
      final countExp = _db.playlistEntriesTable.id.count();
      final query = _db.selectOnly(_db.playlistEntriesTable)
        ..where(_db.playlistEntriesTable.playlistId.equals(playlistId))
        ..addColumns([countExp]);
      int count = await query.map((row) => row.read(countExp)).getSingle() ?? 0;

      await _db.transaction(() async {
        for (final songId in songIds) {
          await _db.into(_db.playlistEntriesTable).insert(
            PlaylistEntriesTableCompanion.insert(
              playlistId: playlistId,
              songId: songId,
              orderIndex: count++,
            ),
          );
        }
      });
      return const Right(null);
    } catch (e) {
      return Left(DatabaseFailure('Failed to add songs to playlist', e));
    }
  }

  Future<Either<AppFailure, void>> removeSongFromPlaylist(int playlistId, int songId) async {
    try {
      await (_db.delete(_db.playlistEntriesTable)
            ..where((t) => t.playlistId.equals(playlistId) & t.songId.equals(songId)))
          .go();
      return const Right(null);
    } catch (e) {
      return Left(DatabaseFailure('Failed to remove song from playlist', e));
    }
  }

  // --- EXCLUDED FOLDERS ---
  Stream<List<ExcludedFoldersTableData>> watchExcludedFolders() {
    return _db.select(_db.excludedFoldersTable).watch();
  }

  Future<List<String>> getExcludedFolderPaths() async {
    final rows = await _db.select(_db.excludedFoldersTable).get();
    return rows.map((r) => r.folderPath).toList();
  }

  Future<Either<AppFailure, void>> toggleFolderExclusion(String folderPath) async {
    try {
      final existing = await (_db.select(_db.excludedFoldersTable)
            ..where((t) => t.folderPath.equals(folderPath)))
          .getSingleOrNull();
      if (existing != null) {
        await (_db.delete(_db.excludedFoldersTable)..where((t) => t.id.equals(existing.id))).go();
      } else {
        await _db.into(_db.excludedFoldersTable).insert(
          ExcludedFoldersTableCompanion.insert(folderPath: folderPath),
        );
      }
      return const Right(null);
    } catch (e) {
      return Left(DatabaseFailure('Failed to toggle folder exclusion', e));
    }
  }

  // --- QUEUE PERSISTENCE ---
  Future<void> saveQueue(List<int> songIds, int currentIndex, int positionMs) async {
    await _db.transaction(() async {
      await _db.delete(_db.queueItemsTable).go();
      for (int i = 0; i < songIds.length; i++) {
        await _db.into(_db.queueItemsTable).insert(
          QueueItemsTableCompanion.insert(
            songId: songIds[i],
            orderIndex: i,
            isCurrent: Value(i == currentIndex),
            positionMs: Value(i == currentIndex ? positionMs : 0),
          ),
        );
      }
    });
  }

  Future<List<QueueItemsTableData>> getSavedQueue() {
    return (_db.select(_db.queueItemsTable)..orderBy([(t) => OrderingTerm(expression: t.orderIndex)])).get();
  }

  // --- BATCH INSERT / SYNC FROM SCANNER & ORPHAN CLEANUP ---
  Future<void> syncScannedMusic({
    required List<SongsTableCompanion> songs,
    required List<AlbumsTableCompanion> albums,
    required List<ArtistsTableCompanion> artists,
  }) async {
    await _db.transaction(() async {
      await _db.batch((batch) {
        batch.insertAllOnConflictUpdate(_db.songsTable, songs);
        batch.insertAllOnConflictUpdate(_db.albumsTable, albums);
        batch.insertAllOnConflictUpdate(_db.artistsTable, artists);
      });
    });
  }

  Future<int> cleanupOrphanedSongs(Set<int> scannedSongIds) async {
    final allSongs = await _db.select(_db.songsTable).get();
    final orphanedIds = allSongs.where((s) => !scannedSongIds.contains(s.id)).map((s) => s.id).toList();
    if (orphanedIds.isNotEmpty) {
      await (_db.delete(_db.songsTable)..where((t) => t.id.isIn(orphanedIds))).go();
    }
    return orphanedIds.length;
  }
}
