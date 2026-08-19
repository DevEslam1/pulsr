// lib/data/repositories/music_repository.dart
import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';
import '../../core/errors/failures.dart';
import '../../domain/models/genre_item.dart';
import '../../domain/models/year_item.dart';
import '../db/app_database.dart';

@singleton
class MusicRepository {
  final AppDatabase _db;

  MusicRepository(this._db);

  // --- SONGS ---
  Stream<Result<List<SongsTableData>>> watchAllSongs({
    String sortBy = 'title',
    bool ascending = true,
    int? limit,
    int? offset,
    String? searchQuery,
    List<String> excludedFolders = const [],
  }) {
    try {
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

      return query.watch().map((songs) => Right<AppFailure, List<SongsTableData>>(songs)).handleError(
            (e) => Left<AppFailure, List<SongsTableData>>(DatabaseFailure('Failed to watch songs', e)),
          );
    } catch (e) {
      return Stream.value(Left(DatabaseFailure('Failed to watch songs', e)));
    }
  }

  Future<Result<List<SongsTableData>>> getAllSongs({
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

  Stream<Result<List<SongsTableData>>> watchFavorites() {
    try {
      return (_db.select(_db.songsTable)
            ..where((t) => t.isFavorite.equals(true))
            ..orderBy([(t) => OrderingTerm(expression: t.title)]))
          .watch()
          .map((songs) => Right<AppFailure, List<SongsTableData>>(songs))
          .handleError((e) => Left<AppFailure, List<SongsTableData>>(DatabaseFailure('Failed to watch favorites', e)));
    } catch (e) {
      return Stream.value(Left(DatabaseFailure('Failed to watch favorites', e)));
    }
  }

  Future<Result<List<SongsTableData>>> getFavorites() async {
    try {
      final songs = await (_db.select(_db.songsTable)
            ..where((t) => t.isFavorite.equals(true))
            ..orderBy([(t) => OrderingTerm(expression: t.title)]))
          .get();
      return Right(songs);
    } catch (e) {
      return Left(DatabaseFailure('Failed to fetch favorites', e));
    }
  }

  Stream<Result<List<SongsTableData>>> watchRecentlyPlayed({int limit = 20}) {
    try {
      return (_db.select(_db.songsTable)
            ..where((t) => t.lastPlayed.isNotNull())
            ..orderBy([(t) => OrderingTerm(expression: t.lastPlayed, mode: OrderingMode.desc)])
            ..limit(limit))
          .watch()
          .map((songs) => Right<AppFailure, List<SongsTableData>>(songs))
          .handleError((e) => Left<AppFailure, List<SongsTableData>>(DatabaseFailure('Failed to watch recently played', e)));
    } catch (e) {
      return Stream.value(Left(DatabaseFailure('Failed to watch recently played', e)));
    }
  }

  Future<Result<List<SongsTableData>>> getRecentlyPlayed({int limit = 20}) async {
    try {
      final songs = await (_db.select(_db.songsTable)
            ..where((t) => t.lastPlayed.isNotNull())
            ..orderBy([(t) => OrderingTerm(expression: t.lastPlayed, mode: OrderingMode.desc)])
            ..limit(limit))
          .get();
      return Right(songs);
    } catch (e) {
      return Left(DatabaseFailure('Failed to fetch recently played songs', e));
    }
  }

  Stream<Result<List<SongsTableData>>> watchRecentlyAdded({int limit = 20}) {
    try {
      return (_db.select(_db.songsTable)
            ..orderBy([(t) => OrderingTerm(expression: t.dateAdded, mode: OrderingMode.desc)])
            ..limit(limit))
          .watch()
          .map((songs) => Right<AppFailure, List<SongsTableData>>(songs))
          .handleError((e) => Left<AppFailure, List<SongsTableData>>(DatabaseFailure('Failed to watch recently added', e)));
    } catch (e) {
      return Stream.value(Left(DatabaseFailure('Failed to watch recently added', e)));
    }
  }

  Stream<Result<List<SongsTableData>>> watchTopPlayed({int limit = 30}) {
    try {
      return (_db.select(_db.songsTable)
            ..where((t) => t.playCount.isBiggerThanValue(0))
            ..orderBy([(t) => OrderingTerm(expression: t.playCount, mode: OrderingMode.desc)])
            ..limit(limit))
          .watch()
          .map((songs) => Right<AppFailure, List<SongsTableData>>(songs))
          .handleError((e) => Left<AppFailure, List<SongsTableData>>(DatabaseFailure('Failed to watch top played', e)));
    } catch (e) {
      return Stream.value(Left(DatabaseFailure('Failed to watch top played', e)));
    }
  }

  Future<Result<bool>> toggleFavorite(int songId) async {
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

  Future<Result<void>> recordPlayHistory(int songId, {bool completed = false}) async {
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
      return const Right(null);
    } catch (e) {
      return Left(DatabaseFailure('Failed to record play history', e));
    }
  }

  Future<Result<void>> updateLastPosition(int songId, int positionMs) async {
    try {
      await (_db.update(_db.songsTable)..where((t) => t.id.equals(songId))).write(
        SongsTableCompanion(lastPositionMs: Value(positionMs)),
      );
      return const Right(null);
    } catch (e) {
      return Left(DatabaseFailure('Failed to update last position', e));
    }
  }

  // --- ALBUMS ---
  Stream<Result<List<AlbumsTableData>>> watchAlbums() {
    try {
      return (_db.select(_db.albumsTable)..orderBy([(t) => OrderingTerm(expression: t.title)]))
          .watch()
          .map((albums) => Right<AppFailure, List<AlbumsTableData>>(albums))
          .handleError((e) => Left<AppFailure, List<AlbumsTableData>>(DatabaseFailure('Failed to watch albums', e)));
    } catch (e) {
      return Stream.value(Left(DatabaseFailure('Failed to watch albums', e)));
    }
  }

  Stream<Result<List<SongsTableData>>> watchAlbumSongs(int albumId) {
    try {
      return (_db.select(_db.songsTable)
            ..where((t) => t.albumId.equals(albumId))
            ..orderBy([(t) => OrderingTerm(expression: t.trackNumber)]))
          .watch()
          .map((songs) => Right<AppFailure, List<SongsTableData>>(songs))
          .handleError((e) => Left<AppFailure, List<SongsTableData>>(DatabaseFailure('Failed to watch album songs', e)));
    } catch (e) {
      return Stream.value(Left(DatabaseFailure('Failed to watch album songs', e)));
    }
  }

  Future<Result<List<AlbumsTableData>>> getAlbums() async {
    try {
      final albums = await (_db.select(_db.albumsTable)
            ..orderBy([(t) => OrderingTerm(expression: t.title)]))
          .get();
      return Right(albums);
    } catch (e) {
      return Left(DatabaseFailure('Failed to fetch albums', e));
    }
  }

  Future<Result<List<SongsTableData>>> getAlbumSongs(int albumId) async {
    try {
      final songs = await (_db.select(_db.songsTable)
            ..where((t) => t.albumId.equals(albumId))
            ..orderBy([(t) => OrderingTerm(expression: t.trackNumber)]))
          .get();
      return Right(songs);
    } catch (e) {
      return Left(DatabaseFailure('Failed to fetch album songs', e));
    }
  }

  // --- ARTISTS ---
  Stream<Result<List<ArtistsTableData>>> watchArtists() {
    try {
      return (_db.select(_db.artistsTable)..orderBy([(t) => OrderingTerm(expression: t.name)]))
          .watch()
          .map((artists) => Right<AppFailure, List<ArtistsTableData>>(artists))
          .handleError((e) => Left<AppFailure, List<ArtistsTableData>>(DatabaseFailure('Failed to watch artists', e)));
    } catch (e) {
      return Stream.value(Left(DatabaseFailure('Failed to watch artists', e)));
    }
  }

  Stream<Result<List<SongsTableData>>> watchArtistSongs(int artistId) {
    try {
      return (_db.select(_db.songsTable)..where((t) => t.artistId.equals(artistId)))
          .watch()
          .map((songs) => Right<AppFailure, List<SongsTableData>>(songs))
          .handleError((e) => Left<AppFailure, List<SongsTableData>>(DatabaseFailure('Failed to watch artist songs', e)));
    } catch (e) {
      return Stream.value(Left(DatabaseFailure('Failed to watch artist songs', e)));
    }
  }

  Future<Result<List<ArtistsTableData>>> getArtists() async {
    try {
      final artists = await (_db.select(_db.artistsTable)..orderBy([(t) => OrderingTerm(expression: t.name)]))
          .get();
      return Right(artists);
    } catch (e) {
      return Left(DatabaseFailure('Failed to fetch artists', e));
    }
  }

  Future<Result<List<SongsTableData>>> getArtistSongs(int artistId) async {
    try {
      final songs = await (_db.select(_db.songsTable)..where((t) => t.artistId.equals(artistId)))
          .get();
      return Right(songs);
    } catch (e) {
      return Left(DatabaseFailure('Failed to fetch artist songs', e));
    }
  }

  Stream<Result<List<AlbumsTableData>>> watchArtistAlbums(int artistId) {
    try {
      return (_db.select(_db.albumsTable)..where((t) => t.artistId.equals(artistId)))
          .watch()
          .map((albums) => Right<AppFailure, List<AlbumsTableData>>(albums))
          .handleError((e) => Left<AppFailure, List<AlbumsTableData>>(DatabaseFailure('Failed to watch artist albums', e)));
    } catch (e) {
      return Stream.value(Left(DatabaseFailure('Failed to watch artist albums', e)));
    }
  }

  // --- PLAYLISTS ---
  Stream<Result<List<PlaylistsTableData>>> watchPlaylists() {
    try {
      return (_db.select(_db.playlistsTable)..orderBy([(t) => OrderingTerm(expression: t.name)]))
          .watch()
          .map((playlists) => Right<AppFailure, List<PlaylistsTableData>>(playlists))
          .handleError((e) => Left<AppFailure, List<PlaylistsTableData>>(DatabaseFailure('Failed to watch playlists', e)));
    } catch (e) {
      return Stream.value(Left(DatabaseFailure('Failed to watch playlists', e)));
    }
  }

  Future<Result<int>> createPlaylist(String name, {bool isSmart = false, String? smartCriteria}) async {
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

  Future<Result<void>> renamePlaylist(int playlistId, String newName) async {
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

  Future<Result<void>> updateSmartPlaylist(int playlistId, String name, String smartCriteria) async {
    try {
      await (_db.update(_db.playlistsTable)..where((t) => t.id.equals(playlistId))).write(
        PlaylistsTableCompanion(
          name: Value(name),
          smartCriteria: Value(smartCriteria),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return const Right(null);
    } catch (e) {
      return Left(DatabaseFailure('Failed to update smart playlist', e));
    }
  }

  Future<Result<void>> deletePlaylist(int playlistId) async {
    try {
      await (_db.delete(_db.playlistsTable)..where((t) => t.id.equals(playlistId))).go();
      return const Right(null);
    } catch (e) {
      return Left(DatabaseFailure('Failed to delete playlist', e));
    }
  }

  Future<Result<List<PlaylistsTableData>>> getPlaylists() async {
    try {
      final playlists = await (_db.select(_db.playlistsTable)..orderBy([(t) => OrderingTerm(expression: t.name)]))
          .get();
      return Right(playlists);
    } catch (e) {
      return Left(DatabaseFailure('Failed to fetch playlists', e));
    }
  }

  Stream<Result<List<SongsTableData>>> watchPlaylistSongs(int playlistId) {
    try {
      final query = _db.select(_db.playlistEntriesTable).join([
        innerJoin(_db.songsTable, _db.songsTable.id.equalsExp(_db.playlistEntriesTable.songId)),
      ])
        ..where(_db.playlistEntriesTable.playlistId.equals(playlistId))
        ..orderBy([OrderingTerm(expression: _db.playlistEntriesTable.orderIndex)]);

      return query
          .watch()
          .map((rows) => Right<AppFailure, List<SongsTableData>>(rows.map((row) => row.readTable(_db.songsTable)).toList()))
          .handleError((e) => Left<AppFailure, List<SongsTableData>>(DatabaseFailure('Failed to watch playlist songs', e)));
    } catch (e) {
      return Stream.value(Left(DatabaseFailure('Failed to watch playlist songs', e)));
    }
  }

  Future<Result<List<SongsTableData>>> getPlaylistSongs(int playlistId) async {
    try {
      final query = _db.select(_db.playlistEntriesTable).join([
        innerJoin(_db.songsTable, _db.songsTable.id.equalsExp(_db.playlistEntriesTable.songId)),
      ])
        ..where(_db.playlistEntriesTable.playlistId.equals(playlistId))
        ..orderBy([OrderingTerm(expression: _db.playlistEntriesTable.orderIndex)]);

      final rows = await query.get();
      final songs = rows.map((row) => row.readTable(_db.songsTable)).toList();
      return Right(songs);
    } catch (e) {
      return Left(DatabaseFailure('Failed to fetch playlist songs', e));
    }
  }

  Future<Result<void>> addSongToPlaylist(int playlistId, int songId) async {
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

  Future<Result<void>> addSongsToPlaylist(int playlistId, List<int> songIds) async {
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

  Future<Result<void>> removeSongFromPlaylist(int playlistId, int songId) async {
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
  Stream<Result<List<ExcludedFoldersTableData>>> watchExcludedFolders() {
    try {
      return _db
          .select(_db.excludedFoldersTable)
          .watch()
          .map((folders) => Right<AppFailure, List<ExcludedFoldersTableData>>(folders))
          .handleError((e) => Left<AppFailure, List<ExcludedFoldersTableData>>(DatabaseFailure('Failed to watch excluded folders', e)));
    } catch (e) {
      return Stream.value(Left(DatabaseFailure('Failed to watch excluded folders', e)));
    }
  }

  Future<Result<List<String>>> getExcludedFolderPaths() async {
    try {
      final rows = await _db.select(_db.excludedFoldersTable).get();
      return Right(rows.map((r) => r.folderPath).toList());
    } catch (e) {
      return Left(DatabaseFailure('Failed to fetch excluded folder paths', e));
    }
  }

  Future<Result<void>> toggleFolderExclusion(String folderPath) async {
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
  Future<Result<void>> saveQueue(List<int> songIds, int currentIndex, int positionMs) async {
    try {
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
      return const Right(null);
    } catch (e) {
      return Left(DatabaseFailure('Failed to save queue', e));
    }
  }

  Future<Result<List<QueueItemsTableData>>> getSavedQueue() async {
    try {
      final items = await (_db.select(_db.queueItemsTable)..orderBy([(t) => OrderingTerm(expression: t.orderIndex)])).get();
      return Right(items);
    } catch (e) {
      return Left(DatabaseFailure('Failed to get saved queue', e));
    }
  }

  // --- BATCH INSERT / SYNC FROM SCANNER & ORPHAN CLEANUP ---
  Future<Result<void>> syncScannedMusic({
    required List<SongsTableCompanion> songs,
    required List<AlbumsTableCompanion> albums,
    required List<ArtistsTableCompanion> artists,
  }) async {
    try {
      await _db.transaction(() async {
        await _db.batch((batch) {
          batch.insertAllOnConflictUpdate(_db.songsTable, songs);
          batch.insertAllOnConflictUpdate(_db.albumsTable, albums);
          batch.insertAllOnConflictUpdate(_db.artistsTable, artists);
        });
      });
      return const Right(null);
    } catch (e) {
      return Left(DatabaseFailure('Failed to sync scanned music', e));
    }
  }

  Future<Result<int>> cleanupOrphanedSongs(Set<int> scannedSongIds) async {
    try {
      final allSongs = await _db.select(_db.songsTable).get();
      final orphanedIds = allSongs.where((s) => !scannedSongIds.contains(s.id)).map((s) => s.id).toList();
      if (orphanedIds.isNotEmpty) {
        await (_db.delete(_db.songsTable)..where((t) => t.id.isIn(orphanedIds))).go();
      }
      return Right(orphanedIds.length);
    } catch (e) {
      return Left(DatabaseFailure('Failed to cleanup orphaned songs', e));
    }
  }

  Future<Result<void>> updateSongTags({
    required String path,
    required String title,
    required String artist,
    required String album,
    String? genre,
    int? year,
    int? trackNumber,
  }) async {
    try {
      final existing = await (_db.select(_db.songsTable)..where((t) => t.path.equals(path))).getSingleOrNull();
      if (existing != null) {
        await (_db.update(_db.songsTable)..where((t) => t.id.equals(existing.id))).write(
          SongsTableCompanion(
            title: Value(title),
            artist: Value(artist),
            album: Value(album),
            genre: Value(genre),
            year: Value(year),
            trackNumber: Value(trackNumber),
          ),
        );
      }
      return const Right(null);
    } catch (e) {
      return Left(DatabaseFailure('Failed to update song tags', e));
    }
  }

  // --- GENRES ---
  Stream<Result<List<GenreItem>>> watchGenres() {
    try {
      final countExp = _db.songsTable.id.count();
      final query = _db.selectOnly(_db.songsTable)
        ..addColumns([_db.songsTable.genre, countExp])
        ..where(_db.songsTable.genre.isNotNull() & _db.songsTable.genre.equals('').not())
        ..groupBy([_db.songsTable.genre])
        ..orderBy([OrderingTerm(expression: _db.songsTable.genre)]);

      return query.watch().map((rows) {
        final list = rows.map((row) {
          final genreName = row.read(_db.songsTable.genre) ?? '';
          final count = row.read(countExp) ?? 0;
          return GenreItem(name: genreName, songCount: count);
        }).where((g) => g.name.isNotEmpty).toList();
        return Right<AppFailure, List<GenreItem>>(list);
      }).handleError((e) => Left<AppFailure, List<GenreItem>>(DatabaseFailure('Failed to watch genres', e)));
    } catch (e) {
      return Stream.value(Left(DatabaseFailure('Failed to watch genres', e)));
    }
  }

  Stream<Result<List<SongsTableData>>> watchGenreSongs(String genre) {
    try {
      return (_db.select(_db.songsTable)
            ..where((t) => t.genre.equals(genre))
            ..orderBy([(t) => OrderingTerm(expression: t.title)]))
          .watch()
          .map((songs) => Right<AppFailure, List<SongsTableData>>(songs))
          .handleError((e) => Left<AppFailure, List<SongsTableData>>(DatabaseFailure('Failed to watch genre songs', e)));
    } catch (e) {
      return Stream.value(Left(DatabaseFailure('Failed to watch genre songs', e)));
    }
  }

  // --- YEARS ---
  Stream<Result<List<YearItem>>> watchYears() {
    try {
      final countExp = _db.songsTable.id.count();
      final query = _db.selectOnly(_db.songsTable)
        ..addColumns([_db.songsTable.year, countExp])
        ..where(_db.songsTable.year.isNotNull() & _db.songsTable.year.isBiggerThanValue(0))
        ..groupBy([_db.songsTable.year])
        ..orderBy([OrderingTerm(expression: _db.songsTable.year, mode: OrderingMode.desc)]);

      return query.watch().map((rows) {
        final list = rows.map((row) {
          final yr = row.read(_db.songsTable.year) ?? 0;
          final count = row.read(countExp) ?? 0;
          return YearItem(year: yr, songCount: count);
        }).where((y) => y.year > 0).toList();
        return Right<AppFailure, List<YearItem>>(list);
      }).handleError((e) => Left<AppFailure, List<YearItem>>(DatabaseFailure('Failed to watch years', e)));
    } catch (e) {
      return Stream.value(Left(DatabaseFailure('Failed to watch years', e)));
    }
  }

  Stream<Result<List<SongsTableData>>> watchYearSongs(int year) {
    try {
      return (_db.select(_db.songsTable)
            ..where((t) => t.year.equals(year))
            ..orderBy([(t) => OrderingTerm(expression: t.title)]))
          .watch()
          .map((songs) => Right<AppFailure, List<SongsTableData>>(songs))
          .handleError((e) => Left<AppFailure, List<SongsTableData>>(DatabaseFailure('Failed to watch year songs', e)));
    } catch (e) {
      return Stream.value(Left(DatabaseFailure('Failed to watch year songs', e)));
    }
  }
}

