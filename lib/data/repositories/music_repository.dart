// lib/data/repositories/music_repository.dart
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';
import '../../core/errors/failures.dart';
import '../../domain/models/genre_item.dart';
import '../../domain/models/year_item.dart';
import '../../domain/models/ytm_track.dart';
import '../../domain/repositories/music_repository_interface.dart';
import '../db/app_database.dart';

@Singleton(as: IMusicRepository)
class MusicRepository implements IMusicRepository {
  final AppDatabase _db;

  MusicRepository(this._db);

  // --- SONGS ---
  @override
  Stream<Result<List<SongsTableData>>> watchAllSongs({
    String sortBy = 'title',
    bool ascending = true,
    int? limit,
    int? offset,
    String? searchQuery,
    List<String> excludedFolders = const [],
  }) {
    try {
      final query = _db.select(_db.songsTable)
        ..where((t) =>
            t.isMissing.equals(false) &
            t.source.equals(SongSource.local) &
            t.path.like('ytmusic://%').not());

      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        final pattern = '%${searchQuery.trim().toLowerCase()}%';
        query.where((t) => t.title.lower().like(pattern) | t.artist.lower().like(pattern) | t.album.lower().like(pattern));
      }

      if (excludedFolders.isNotEmpty) {
        for (final folder in excludedFolders) {
          final prefix = folder.endsWith(Platform.pathSeparator) ? folder : '$folder${Platform.pathSeparator}';
          query.where((t) => t.path.like('$prefix%').not());
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

  @override
  Future<Result<List<SongsTableData>>> getAllSongs({
    String sortBy = 'title',
    bool ascending = true,
    int? limit,
    int? offset,
  }) async {
    try {
      final query = _db.select(_db.songsTable)
        ..where((t) =>
            t.isMissing.equals(false) &
            t.source.equals(SongSource.local) &
            t.path.like('ytmusic://%').not());
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

  @override
  Future<Result<SongsTableData?>> getSongById(int id) async {
    try {
      final song = await (_db.select(_db.songsTable)..where((t) => t.id.equals(id))).getSingleOrNull();
      return Right(song);
    } catch (e) {
      return Left(DatabaseFailure('Failed to fetch song by id', e));
    }
  }

  @override
  Future<Result<SongsTableData?>> getSongByPath(String path) async {
    try {
      final song = await (_db.select(_db.songsTable)..where((t) => t.path.equals(path))).getSingleOrNull();
      return Right(song);
    } catch (e) {
      return Left(DatabaseFailure('Failed to fetch song by path', e));
    }
  }

  @override
  Future<Result<SongsTableData?>> getSongByUri(String uri) async {
    try {
      final song = await (_db.select(_db.songsTable)..where((t) => t.uri.equals(uri) | t.path.equals(uri))).getSingleOrNull();
      return Right(song);
    } catch (e) {
      return Left(DatabaseFailure('Failed to fetch song by uri', e));
    }
  }

  @override
  Future<Result<SongsTableData?>> getSongByRemoteId(String remoteId) async {
    if (remoteId.isEmpty) return const Right(null);
    try {
      final song = await (_db.select(_db.songsTable)
            ..where((t) => t.remoteId.equals(remoteId) & t.source.equals(SongSource.local) & t.isMissing.equals(false))
            ..limit(1))
          .getSingleOrNull();
      return Right(song);
    } catch (e) {
      return Left(DatabaseFailure('Failed to fetch song by remoteId', e));
    }
  }

  @override
  Future<Result<SongsTableData?>> findMatchingLocalSong({String? remoteId, String? title, String? artist}) async {
    try {
      // 1. Try matching by remoteId first
      if (remoteId != null && remoteId.isNotEmpty) {
        final byRemoteId = await (_db.select(_db.songsTable)
              ..where((t) => t.remoteId.equals(remoteId) & t.source.equals(SongSource.local) & t.isMissing.equals(false))
              ..limit(1))
            .getSingleOrNull();
        if (byRemoteId != null) return Right(byRemoteId);
      }

      // 2. Try matching by title & artist on local rows
      if (title != null && title.trim().isNotEmpty && artist != null && artist.trim().isNotEmpty) {
        final byMeta = await (_db.select(_db.songsTable)
              ..where((t) =>
                  t.source.equals(SongSource.local) &
                  t.isMissing.equals(false) &
                  t.title.lower().equals(title.trim().toLowerCase()) &
                  t.artist.lower().equals(artist.trim().toLowerCase()))
              ..limit(1))
            .getSingleOrNull();
        if (byMeta != null) return Right(byMeta);
      }

      return const Right(null);
    } catch (e) {
      return Left(DatabaseFailure('Failed to find matching local song', e));
    }
  }

  @override
  Future<Result<List<SongsTableData>>> getSongsByIds(List<int> ids) async {
    if (ids.isEmpty) return const Right([]);
    try {
      final songs = await (_db.select(_db.songsTable)..where((t) => t.id.isIn(ids))).get();
      return Right(songs);
    } catch (e) {
      return Left(DatabaseFailure('Failed to fetch songs by ids', e));
    }
  }

  @override
  Stream<Result<List<SongsTableData>>> watchFavorites() {
    try {
      return (_db.select(_db.songsTable)
            ..where((t) =>
                t.isFavorite.equals(true) &
                t.isMissing.equals(false) &
                t.source.equals(SongSource.local) &
                t.path.like('ytmusic://%').not())
            ..orderBy([(t) => OrderingTerm(expression: t.title)]))
          .watch()
          .map((songs) => Right<AppFailure, List<SongsTableData>>(songs))
          .handleError((e) => Left<AppFailure, List<SongsTableData>>(DatabaseFailure('Failed to watch favorites', e)));
    } catch (e) {
      return Stream.value(Left(DatabaseFailure('Failed to watch favorites', e)));
    }
  }

  @override
  Future<Result<List<SongsTableData>>> getFavorites() async {
    try {
      final songs = await (_db.select(_db.songsTable)
            ..where((t) =>
                t.isFavorite.equals(true) &
                t.isMissing.equals(false) &
                t.source.equals(SongSource.local) &
                t.path.like('ytmusic://%').not())
            ..orderBy([(t) => OrderingTerm(expression: t.title)]))
          .get();
      return Right(songs);
    } catch (e) {
      return Left(DatabaseFailure('Failed to fetch favorites', e));
    }
  }

  @override
  Future<Result<int>> importOnlineTracksAsFavorites(List<YtmTrack> tracks) async {
    try {
      int count = 0;
      for (final track in tracks) {
        final songData = track.toSongData();
        final existing = await (_db.select(_db.songsTable)
              ..where((t) => t.remoteId.equals(track.videoId))
              ..limit(1))
            .getSingleOrNull();

        if (existing != null) {
          await (_db.update(_db.songsTable)..where((t) => t.id.equals(existing.id)))
              .write(const SongsTableCompanion(isFavorite: Value(true)));
          count++;
        } else {
          await _db.into(_db.songsTable).insert(
                SongsTableCompanion(
                  id: Value(songData.id),
                  title: Value(songData.title),
                  artist: Value(songData.artist),
                  album: Value(songData.album),
                  durationMs: Value(songData.durationMs),
                  path: Value(songData.path),
                  source: const Value(SongSource.youtube),
                  remoteId: Value(track.videoId),
                  remoteArtworkUrl: Value(track.artworkUrl),
                  isFavorite: const Value(true),
                  dateAdded: Value(DateTime.now().millisecondsSinceEpoch),
                ),
                mode: InsertMode.insertOrReplace,
              );
          count++;
        }
      }
      return Right(count);
    } catch (e) {
      return Left(DatabaseFailure('Failed to import online tracks as favorites', e));
    }
  }

  @override
  Stream<Result<List<SongsTableData>>> watchRecentlyPlayed({int limit = 20}) {
    try {
      return (_db.select(_db.songsTable)
            ..where((t) =>
                t.lastPlayed.isNotNull() &
                t.isMissing.equals(false) &
                t.source.equals(SongSource.local) &
                t.path.like('ytmusic://%').not())
            ..orderBy([(t) => OrderingTerm(expression: t.lastPlayed, mode: OrderingMode.desc)])
            ..limit(limit))
          .watch()
          .map((songs) => Right<AppFailure, List<SongsTableData>>(songs))
          .handleError((e) => Left<AppFailure, List<SongsTableData>>(DatabaseFailure('Failed to watch recently played', e)));
    } catch (e) {
      return Stream.value(Left(DatabaseFailure('Failed to watch recently played', e)));
    }
  }

  @override
  Future<Result<List<SongsTableData>>> getRecentlyPlayed({int limit = 20}) async {
    try {
      final songs = await (_db.select(_db.songsTable)
            ..where((t) =>
                t.lastPlayed.isNotNull() &
                t.isMissing.equals(false) &
                t.source.equals(SongSource.local) &
                t.path.like('ytmusic://%').not())
            ..orderBy([(t) => OrderingTerm(expression: t.lastPlayed, mode: OrderingMode.desc)])
            ..limit(limit))
          .get();
      return Right(songs);
    } catch (e) {
      return Left(DatabaseFailure('Failed to fetch recently played songs', e));
    }
  }

  @override
  Stream<Result<List<SongsTableData>>> watchRecentlyAdded({int limit = 20}) {
    try {
      return (_db.select(_db.songsTable)
            ..where((t) =>
                t.isMissing.equals(false) &
                t.source.equals(SongSource.local) &
                t.path.like('ytmusic://%').not())
            ..orderBy([(t) => OrderingTerm(expression: t.dateAdded, mode: OrderingMode.desc)])
            ..limit(limit))
          .watch()
          .map((songs) => Right<AppFailure, List<SongsTableData>>(songs))
          .handleError((e) => Left<AppFailure, List<SongsTableData>>(DatabaseFailure('Failed to watch recently added', e)));
    } catch (e) {
      return Stream.value(Left(DatabaseFailure('Failed to watch recently added', e)));
    }
  }

  @override
  Stream<Result<List<SongsTableData>>> watchTopPlayed({int limit = 30}) {
    try {
      return (_db.select(_db.songsTable)
            ..where((t) =>
                t.playCount.isBiggerThanValue(0) &
                t.isMissing.equals(false) &
                t.source.equals(SongSource.local) &
                t.path.like('ytmusic://%').not())
            ..orderBy([(t) => OrderingTerm(expression: t.playCount, mode: OrderingMode.desc)])
            ..limit(limit))
          .watch()
          .map((songs) => Right<AppFailure, List<SongsTableData>>(songs))
          .handleError((e) => Left<AppFailure, List<SongsTableData>>(DatabaseFailure('Failed to watch top played', e)));
    } catch (e) {
      return Stream.value(Left(DatabaseFailure('Failed to watch top played', e)));
    }
  }

  int? _lastRecordedSongId;
  DateTime? _lastRecordedTime;

  @override
  Future<Result<bool>> toggleFavorite(int songId) async {
    try {
      final updatedVal = await _db.transaction(() async {
        final song = await (_db.select(_db.songsTable)..where((t) => t.id.equals(songId))).getSingleOrNull();
        if (song == null) return null;
        final nextVal = !song.isFavorite;
        await (_db.update(_db.songsTable)..where((t) => t.id.equals(songId)))
            .write(SongsTableCompanion(isFavorite: Value(nextVal)));
        return nextVal;
      });
      if (updatedVal != null) {
        return Right(updatedVal);
      }
      return const Left(DatabaseFailure('Song not found'));
    } catch (e) {
      return Left(DatabaseFailure('Failed to toggle favorite', e));
    }
  }

  @override
  Future<Result<void>> recordPlayHistory(int songId, {bool completed = false}) async {
    try {
      final now = DateTime.now();
      if (_lastRecordedSongId == songId && _lastRecordedTime != null && now.difference(_lastRecordedTime!).inMilliseconds < 1500) {
        return const Right(null);
      }
      _lastRecordedSongId = songId;
      _lastRecordedTime = now;
      final nowMs = now.millisecondsSinceEpoch;
      await _db.transaction(() async {
        final song = await (_db.select(_db.songsTable)..where((t) => t.id.equals(songId))).getSingleOrNull();
        if (song != null) {
          await (_db.update(_db.songsTable)..where((t) => t.id.equals(songId))).write(
            SongsTableCompanion(
              playCount: Value(song.playCount + 1),
              lastPlayed: Value(nowMs),
            ),
          );
          await _db.into(_db.playHistoryTable).insert(
            PlayHistoryTableCompanion.insert(
              songId: songId,
              completed: Value(completed),
            ),
          );
        }
      });
      return const Right(null);
    } catch (e) {
      return Left(DatabaseFailure('Failed to record play history', e));
    }
  }

  @override
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
  @override
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

  @override
  Stream<Result<List<SongsTableData>>> watchAlbumSongs(int albumId) {
    try {
      return (_db.select(_db.songsTable)
            ..where((t) =>
                t.albumId.equals(albumId) &
                t.isMissing.equals(false) &
                t.source.equals(SongSource.local) &
                t.path.like('ytmusic://%').not())
            ..orderBy([(t) => OrderingTerm(expression: t.trackNumber)]))
          .watch()
          .map((songs) => Right<AppFailure, List<SongsTableData>>(songs))
          .handleError((e) => Left<AppFailure, List<SongsTableData>>(DatabaseFailure('Failed to watch album songs', e)));
    } catch (e) {
      return Stream.value(Left(DatabaseFailure('Failed to watch album songs', e)));
    }
  }

  @override
  Future<Result<List<AlbumsTableData>>> getAlbums() async {
    try {
      final albums = await (_db.select(_db.albumsTable)
            ..where((t) => t.songCount.isBiggerThanValue(0))
            ..orderBy([(t) => OrderingTerm(expression: t.title)]))
          .get();
      return Right(albums);
    } catch (e) {
      return Left(DatabaseFailure('Failed to fetch albums', e));
    }
  }

  @override
  Future<Result<List<SongsTableData>>> getAlbumSongs(int albumId) async {
    try {
      final songs = await (_db.select(_db.songsTable)
            ..where((t) =>
                t.albumId.equals(albumId) &
                t.isMissing.equals(false) &
                t.source.equals(SongSource.local) &
                t.path.like('ytmusic://%').not())
            ..orderBy([(t) => OrderingTerm(expression: t.trackNumber)]))
          .get();
      return Right(songs);
    } catch (e) {
      return Left(DatabaseFailure('Failed to fetch album songs', e));
    }
  }

  // --- ARTISTS ---
  @override
  Stream<Result<List<ArtistsTableData>>> watchArtists() {
    try {
      return (_db.select(_db.artistsTable)
            ..where((t) => t.songCount.isBiggerThanValue(0))
            ..orderBy([(t) => OrderingTerm(expression: t.name)]))
          .watch()
          .map((artists) => Right<AppFailure, List<ArtistsTableData>>(artists))
          .handleError((e) => Left<AppFailure, List<ArtistsTableData>>(DatabaseFailure('Failed to watch artists', e)));
    } catch (e) {
      return Stream.value(Left(DatabaseFailure('Failed to watch artists', e)));
    }
  }

  @override
  Stream<Result<List<SongsTableData>>> watchArtistSongs(int artistId) {
    try {
      return (_db.select(_db.songsTable)
            ..where((t) =>
                t.artistId.equals(artistId) &
                t.isMissing.equals(false) &
                t.source.equals(SongSource.local) &
                t.path.like('ytmusic://%').not()))
          .watch()
          .map((songs) => Right<AppFailure, List<SongsTableData>>(songs))
          .handleError((e) => Left<AppFailure, List<SongsTableData>>(DatabaseFailure('Failed to watch artist songs', e)));
    } catch (e) {
      return Stream.value(Left(DatabaseFailure('Failed to watch artist songs', e)));
    }
  }

  @override
  Future<Result<List<ArtistsTableData>>> getArtists() async {
    try {
      final artists = await (_db.select(_db.artistsTable)
            ..where((t) => t.songCount.isBiggerThanValue(0))
            ..orderBy([(t) => OrderingTerm(expression: t.name)]))
          .get();
      return Right(artists);
    } catch (e) {
      return Left(DatabaseFailure('Failed to fetch artists', e));
    }
  }

  @override
  Future<Result<List<SongsTableData>>> getArtistSongs(int artistId) async {
    try {
      final songs = await (_db.select(_db.songsTable)
            ..where((t) =>
                t.artistId.equals(artistId) &
                t.isMissing.equals(false) &
                t.source.equals(SongSource.local) &
                t.path.like('ytmusic://%').not()))
          .get();
      return Right(songs);
    } catch (e) {
      return Left(DatabaseFailure('Failed to fetch artist songs', e));
    }
  }

  @override
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
  @override
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

  @override
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

  @override
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

  @override
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

  @override
  Future<Result<void>> deletePlaylist(int playlistId) async {
    try {
      await (_db.delete(_db.playlistsTable)..where((t) => t.id.equals(playlistId))).go();
      return const Right(null);
    } catch (e) {
      return Left(DatabaseFailure('Failed to delete playlist', e));
    }
  }

  @override
  Future<Result<List<PlaylistsTableData>>> getPlaylists() async {
    try {
      final playlists = await (_db.select(_db.playlistsTable)..orderBy([(t) => OrderingTerm(expression: t.name)]))
          .get();
      return Right(playlists);
    } catch (e) {
      return Left(DatabaseFailure('Failed to fetch playlists', e));
    }
  }

  @override
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

  @override
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

  @override
  Future<Result<void>> addSongToPlaylist(int playlistId, int songId) async {
    try {
      final existing = await (_db.select(_db.playlistEntriesTable)
            ..where((t) => t.playlistId.equals(playlistId) & t.songId.equals(songId)))
          .getSingleOrNull();
      if (existing != null) {
        return const Right(null); // Already present, avoid duplication
      }

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

  @override
  Future<Result<void>> addSongsToPlaylist(int playlistId, List<int> songIds) async {
    try {
      final existingRows = await (_db.select(_db.playlistEntriesTable)
            ..where((t) => t.playlistId.equals(playlistId)))
          .get();
      final existingSongIds = existingRows.map((r) => r.songId).toSet();
      int count = existingRows.length;

      await _db.transaction(() async {
        for (final songId in songIds) {
          if (!existingSongIds.contains(songId)) {
            existingSongIds.add(songId);
            await _db.into(_db.playlistEntriesTable).insert(
              PlaylistEntriesTableCompanion.insert(
                playlistId: playlistId,
                songId: songId,
                orderIndex: count++,
              ),
            );
          }
        }
      });
      return const Right(null);
    } catch (e) {
      return Left(DatabaseFailure('Failed to add songs to playlist', e));
    }
  }

  @override
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
  @override
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

  @override
  Future<Result<List<String>>> getExcludedFolderPaths() async {
    try {
      final rows = await _db.select(_db.excludedFoldersTable).get();
      return Right(rows.map((r) => r.folderPath).toList());
    } catch (e) {
      return Left(DatabaseFailure('Failed to fetch excluded folder paths', e));
    }
  }

  @override
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
  @override
  Future<Result<void>> saveQueue(List<int> songIds, int currentIndex, int positionMs) async {
    try {
      await _db.transaction(() async {
        await _db.delete(_db.queueItemsTable).go();
        await _db.batch((batch) {
          for (int i = 0; i < songIds.length; i++) {
            batch.insert(
              _db.queueItemsTable,
              QueueItemsTableCompanion.insert(
                songId: songIds[i],
                orderIndex: i,
                isCurrent: Value(i == currentIndex),
                positionMs: Value(i == currentIndex ? positionMs : 0),
              ),
            );
          }
        });
      });
      return const Right(null);
    } catch (e) {
      return Left(DatabaseFailure('Failed to save queue', e));
    }
  }

  @override
  Future<Result<List<QueueItemsTableData>>> getSavedQueue() async {
    try {
      final items = await (_db.select(_db.queueItemsTable)..orderBy([(t) => OrderingTerm(expression: t.orderIndex)])).get();
      return Right(items);
    } catch (e) {
      return Left(DatabaseFailure('Failed to get saved queue', e));
    }
  }

  // --- BATCH INSERT / SYNC FROM SCANNER & ORPHAN CLEANUP ---
  @override
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

  @override
  Future<Result<int>> cleanupOrphanedSongs(Set<int> scannedSongIds) async {
    try {
      // NEVER delete or mark missing on an empty scan result (protect against unmounted SD cards, OS indexing, permission drops)
      if (scannedSongIds.isEmpty) {
        return const Right(0);
      }

      int markedMissingCount = 0;
      await _db.transaction(() async {
        // Soft delete: mark missing songs instead of hard deleting to preserve playlist entries, play history & favorites.
        // Non-local rows or pending local downloads without MediaStore IDs must not be flagged missing.
        markedMissingCount = await (_db.update(_db.songsTable)
              ..where((t) =>
                  t.id.isNotIn(scannedSongIds) &
                  t.id.isBiggerThanValue(0) &
                  t.source.equals(SongSource.local)))
            .write(
          const SongsTableCompanion(isMissing: Value(true)),
        );

        // Ensure newly/currently scanned songs are marked active (not missing)
        await (_db.update(_db.songsTable)..where((t) => t.id.isIn(scannedSongIds))).write(
          const SongsTableCompanion(isMissing: Value(false)),
        );

        // Recalculate song counts using active (non-missing) local songs
        final albumCounts = await (_db.selectOnly(_db.songsTable)
              ..addColumns([_db.songsTable.albumId, _db.songsTable.id.count()])
              ..where(_db.songsTable.albumId.isNotNull() &
                  _db.songsTable.isMissing.equals(false) &
                  _db.songsTable.source.equals(SongSource.local) &
                  _db.songsTable.path.like('ytmusic://%').not())
              ..groupBy([_db.songsTable.albumId]))
            .get();

        final artistCounts = await (_db.selectOnly(_db.songsTable)
              ..addColumns([_db.songsTable.artistId, _db.songsTable.id.count()])
              ..where(_db.songsTable.artistId.isNotNull() &
                  _db.songsTable.isMissing.equals(false) &
                  _db.songsTable.source.equals(SongSource.local) &
                  _db.songsTable.path.like('ytmusic://%').not())
              ..groupBy([_db.songsTable.artistId]))
            .get();

        await _db.batch((batch) {
          for (final row in albumCounts) {
            final albumId = row.read(_db.songsTable.albumId);
            final count = row.read(_db.songsTable.id.count());
            if (albumId != null && count != null) {
              batch.update(
                _db.albumsTable,
                AlbumsTableCompanion(songCount: Value(count)),
                where: (t) => t.id.equals(albumId),
              );
            }
          }
          for (final row in artistCounts) {
            final artistId = row.read(_db.songsTable.artistId);
            final count = row.read(_db.songsTable.id.count());
            if (artistId != null && count != null) {
              batch.update(
                _db.artistsTable,
                ArtistsTableCompanion(songCount: Value(count)),
                where: (t) => t.id.equals(artistId),
              );
            }
          }
        });
      });

      return Right(markedMissingCount);
    } catch (e) {
      return Left(DatabaseFailure('Failed to cleanup orphaned items', e));
    }
  }

  @override
  Future<Result<int>> hardDeleteMissingSongs() async {
    try {
      final deletedCount = await (_db.delete(_db.songsTable)
            ..where((t) => t.isMissing.equals(true) & t.source.equals(SongSource.local)))
          .go();

      // Reconcile and cleanup orphaned albums and artists in single SQL queries
      await _db.customStatement(
        'DELETE FROM albums WHERE id NOT IN (SELECT DISTINCT album_id FROM songs WHERE album_id IS NOT NULL);',
      );
      await _db.customStatement(
        'DELETE FROM artists WHERE id NOT IN (SELECT DISTINCT artist_id FROM songs WHERE artist_id IS NOT NULL);',
      );

      return Right(deletedCount);
    } catch (e) {
      return Left(DatabaseFailure('Failed to hard delete missing songs', e));
    }
  }

  @override
  Future<Result<int?>> reconcileDownloadedSong({
    required int oldId,
    required String newPath,
    SongsTableData? fallbackSong,
  }) async {
    try {
      int? survivingId;
      await _db.transaction(() async {
        final oldRow = await (_db.select(_db.songsTable)..where((t) => t.id.equals(oldId))).getSingleOrNull();

        // Find the row the scanner minted for the downloaded file. getSongByPath
        // is unusable here: getSingleOrNull() throws if MediaStore re-indexed
        // the same path under more than one id (there is no unique index on path).
        var newRow = await (_db.select(_db.songsTable)
              ..where((t) => t.path.equals(newPath) & t.id.isBiggerThanValue(0))
              ..orderBy([(t) => OrderingTerm(expression: t.dateAdded, mode: OrderingMode.desc)])
              ..limit(1))
            .getSingleOrNull();

        // Fallback: MediaStore may rename the file to dodge a collision, so the
        // path won't match. Match on normalized metadata instead.
        final matchMetadata = oldRow ?? fallbackSong;
        if (newRow == null && matchMetadata != null) {
          newRow = await (_db.select(_db.songsTable)
                ..where((t) =>
                    t.id.isBiggerThanValue(0) &
                    t.source.equals(SongSource.local) &
                    t.title.lower().equals(matchMetadata.title.toLowerCase()) &
                    t.artist.lower().equals(matchMetadata.artist.toLowerCase()) &
                    t.durationMs.isBetweenValues(matchMetadata.durationMs - 2000, matchMetadata.durationMs + 2000))
                ..orderBy([(t) => OrderingTerm(expression: t.dateAdded, mode: OrderingMode.desc)])
                ..limit(1))
              .getSingleOrNull();
        }

        if (newRow == null) {
          if (File(newPath).existsSync()) {
            final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
            if (oldRow != null) {
              await (_db.update(_db.songsTable)..where((t) => t.id.equals(oldId))).write(
                SongsTableCompanion(
                  path: Value(newPath),
                  source: const Value(SongSource.local),
                  isMissing: const Value(false),
                  isDownloaded: const Value(true),
                  dateAdded: Value((oldRow.dateAdded ?? 0) > 0 ? oldRow.dateAdded! : nowSec),
                  pendingDownloadPath: const Value(null),
                ),
              );
              survivingId = oldId;
            } else if (fallbackSong != null) {
              await _db.into(_db.songsTable).insert(
                SongsTableCompanion(
                  id: Value(oldId),
                  title: Value(fallbackSong.title),
                  artist: Value(fallbackSong.artist),
                  album: Value(fallbackSong.album.isNotEmpty ? fallbackSong.album : 'YouTube Music'),
                  durationMs: Value(fallbackSong.durationMs),
                  path: Value(newPath),
                  source: const Value(SongSource.local),
                  isMissing: const Value(false),
                  isDownloaded: const Value(true),
                  remoteId: Value(fallbackSong.remoteId),
                  remoteArtworkUrl: Value(fallbackSong.remoteArtworkUrl),
                  dateAdded: Value(nowSec),
                ),
                mode: InsertMode.insertOrReplace,
              );
              survivingId = oldId;
            }
          }
          return;
        }
        final targetId = newRow.id;
        survivingId = targetId;

        // Old row already gone (reconciled twice) or scanner reused the id: nothing to fold.
        if (oldRow == null || oldRow.id == targetId) return;

        // Re-point children off the negative id BEFORE deleting it so the FK
        // cascade finds nothing to remove. playlist_entries has no unique
        // (playlist_id, song_id) index, so dedupe first or membership doubles.
        await _db.customStatement(
          'DELETE FROM playlist_entries WHERE song_id = ? '
          'AND playlist_id IN (SELECT playlist_id FROM playlist_entries WHERE song_id = ?);',
          [oldId, targetId],
        );
        await _db.customStatement('UPDATE playlist_entries SET song_id = ? WHERE song_id = ?;', [targetId, oldId]);
        await _db.customStatement('UPDATE queue_items SET song_id = ? WHERE song_id = ?;', [targetId, oldId]);
        await _db.customStatement('UPDATE play_history SET song_id = ? WHERE song_id = ?;', [targetId, oldId]);

        // Delete the YT row BEFORE writing remoteId onto the new row: the
        // partial unique index on remote_id would otherwise see two rows.
        await _db.customStatement('DELETE FROM songs WHERE id = ?;', [oldId]);

        // Merge stats (don't clobber — the scanned row may predate the download).
        final int? mergedLastPlayed;
        if (oldRow.lastPlayed != null && newRow.lastPlayed != null) {
          mergedLastPlayed = oldRow.lastPlayed! > newRow.lastPlayed! ? oldRow.lastPlayed : newRow.lastPlayed;
        } else {
          mergedLastPlayed = oldRow.lastPlayed ?? newRow.lastPlayed;
        }
        final keepOldPosition = (oldRow.lastPlayed ?? 0) > (newRow.lastPlayed ?? 0);

        final String effectiveTitle = (oldRow.title.isNotEmpty && !oldRow.title.toLowerCase().startsWith('ytdl_'))
            ? oldRow.title
            : newRow.title;
        final String effectiveArtist = (oldRow.artist.isNotEmpty && oldRow.artist != '<unknown>' && oldRow.artist != 'Unknown')
            ? oldRow.artist
            : newRow.artist;
        final String effectiveAlbum = (oldRow.album.isNotEmpty && oldRow.album != '<unknown>' && oldRow.album != 'Unknown')
            ? oldRow.album
            : newRow.album;
        final String? effectiveRemoteArt = (oldRow.remoteArtworkUrl != null && oldRow.remoteArtworkUrl!.isNotEmpty)
            ? oldRow.remoteArtworkUrl
            : newRow.remoteArtworkUrl;

        await (_db.update(_db.songsTable)..where((t) => t.id.equals(targetId))).write(
          SongsTableCompanion(
            title: Value(effectiveTitle),
            artist: Value(effectiveArtist),
            album: Value(effectiveAlbum),
            genre: Value(oldRow.genre ?? newRow.genre),
            isFavorite: Value(oldRow.isFavorite || newRow.isFavorite),
            playCount: Value(oldRow.playCount + newRow.playCount),
            lastPlayed: Value(mergedLastPlayed),
            lastPositionMs: Value(keepOldPosition ? oldRow.lastPositionMs : newRow.lastPositionMs),
            // Carry the video id and online remoteArtworkUrl
            remoteId: Value(oldRow.remoteId ?? newRow.remoteId),
            remoteArtworkUrl: Value(effectiveRemoteArt),
            source: const Value(SongSource.local),
            isDownloaded: const Value(true),
            pendingDownloadPath: const Value(null),
          ),
        );
      });
      return Right(survivingId);
    } catch (e) {
      return Left(DatabaseFailure('Failed to reconcile downloaded song', e));
    }
  }

  @override
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
      final existing = await (_db.select(_db.songsTable)
            ..where((t) => t.path.equals(path) & t.source.equals(SongSource.local)))
          .getSingleOrNull();
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

  @override
  Future<Result<void>> updateAudioQuality({
    required int songId,
    int? sampleRate,
    int? bitDepth,
    int? bitrateKbps,
    String? codec,
    double? loudnessRange,
  }) async {
    try {
      await (_db.update(_db.songsTable)..where((t) => t.id.equals(songId))).write(
        SongsTableCompanion(
          sampleRate: Value(sampleRate),
          bitDepth: Value(bitDepth),
          bitrateKbps: Value(bitrateKbps),
          codec: Value(codec),
          loudnessRange: Value(loudnessRange),
        ),
      );
      return const Right(null);
    } catch (e) {
      return Left(DatabaseFailure('Failed to update audio quality', e));
    }
  }

  // --- GENRES ---
  @override
  Stream<Result<List<GenreItem>>> watchGenres() {
    try {
      final countExp = _db.songsTable.id.count();
      final query = _db.selectOnly(_db.songsTable)
        ..addColumns([_db.songsTable.genre, countExp])
        ..where(_db.songsTable.genre.isNotNull() &
            _db.songsTable.genre.equals('').not() &
            _db.songsTable.isMissing.equals(false) &
            _db.songsTable.source.equals(SongSource.local) &
            _db.songsTable.path.like('ytmusic://%').not())
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

  @override
  Future<Result<List<GenreItem>>> getGenres() async {
    try {
      final countExp = _db.songsTable.id.count();
      final query = _db.selectOnly(_db.songsTable)
        ..addColumns([_db.songsTable.genre, countExp])
        ..where(_db.songsTable.genre.isNotNull() &
            _db.songsTable.genre.equals('').not() &
            _db.songsTable.isMissing.equals(false) &
            _db.songsTable.source.equals(SongSource.local) &
            _db.songsTable.path.like('ytmusic://%').not())
        ..groupBy([_db.songsTable.genre])
        ..orderBy([OrderingTerm(expression: _db.songsTable.genre)]);

      final rows = await query.get();
      final list = rows.map((row) {
        final genreName = row.read(_db.songsTable.genre) ?? '';
        final count = row.read(countExp) ?? 0;
        return GenreItem(name: genreName, songCount: count);
      }).where((g) => g.name.isNotEmpty).toList();
      return Right(list);
    } catch (e) {
      return Left(DatabaseFailure('Failed to get genres', e));
    }
  }

  @override
  Stream<Result<List<SongsTableData>>> watchGenreSongs(String genre) {
    try {
      return (_db.select(_db.songsTable)
            ..where((t) =>
                t.genre.equals(genre) &
                t.isMissing.equals(false) &
                t.source.equals(SongSource.local) &
                t.path.like('ytmusic://%').not())
            ..orderBy([(t) => OrderingTerm(expression: t.title)]))
          .watch()
          .map((songs) => Right<AppFailure, List<SongsTableData>>(songs))
          .handleError((e) => Left<AppFailure, List<SongsTableData>>(DatabaseFailure('Failed to watch genre songs', e)));
    } catch (e) {
      return Stream.value(Left(DatabaseFailure('Failed to watch genre songs', e)));
    }
  }

  @override
  Future<Result<List<SongsTableData>>> getGenreSongs(String genre) async {
    try {
      final songs = await (_db.select(_db.songsTable)
            ..where((t) =>
                t.genre.equals(genre) &
                t.isMissing.equals(false) &
                t.source.equals(SongSource.local) &
                t.path.like('ytmusic://%').not())
            ..orderBy([(t) => OrderingTerm(expression: t.title)]))
          .get();
      return Right(songs);
    } catch (e) {
      return Left(DatabaseFailure('Failed to get genre songs', e));
    }
  }

  // --- YEARS ---
  @override
  Stream<Result<List<YearItem>>> watchYears() {
    try {
      final countExp = _db.songsTable.id.count();
      final query = _db.selectOnly(_db.songsTable)
        ..addColumns([_db.songsTable.year, countExp])
        ..where(_db.songsTable.year.isNotNull() &
            _db.songsTable.year.isBiggerThanValue(0) &
            _db.songsTable.isMissing.equals(false) &
            _db.songsTable.source.equals(SongSource.local) &
            _db.songsTable.path.like('ytmusic://%').not())
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

  @override
  Stream<Result<List<SongsTableData>>> watchYearSongs(int year) {
    try {
      return (_db.select(_db.songsTable)
            ..where((t) =>
                t.year.equals(year) &
                t.isMissing.equals(false) &
                t.source.equals(SongSource.local) &
                t.path.like('ytmusic://%').not())
            ..orderBy([(t) => OrderingTerm(expression: t.title)]))
          .watch()
          .map((songs) => Right<AppFailure, List<SongsTableData>>(songs))
          .handleError((e) => Left<AppFailure, List<SongsTableData>>(DatabaseFailure('Failed to watch year songs', e)));
    } catch (e) {
      return Stream.value(Left(DatabaseFailure('Failed to watch year songs', e)));
    }
  }
}

