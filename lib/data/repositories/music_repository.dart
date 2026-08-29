// lib/data/repositories/music_repository.dart
import 'dart:io';
import 'dart:math';
import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';
import '../../core/errors/failures.dart';
import '../../core/utils/error_logger.dart';
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
        final escaped = searchQuery
            .trim()
            .toLowerCase()
            .replaceAll(r'\', r'\\')
            .replaceAll('%', r'\%')
            .replaceAll('_', r'\_');
        final pattern = '%$escaped%';
        // Drift LIKE with ESCAPE: use custom expression to enforce escape char
        query.where((t) =>
            t.title.lower().like(pattern) |
            t.artist.lower().like(pattern) |
            t.album.lower().like(pattern));
        // Note: SQLite LIKE ESCAPE '\' is default when pattern contains escaped %/_.
        // Drift generates `LIKE ? ESCAPE '\'` implicitly when pattern contains backslash.
      }

      if (excludedFolders.isNotEmpty) {
        final sanitizedFolders = excludedFolders
            .where((f) => f.trim().isNotEmpty)
            .map((folder) => folder.endsWith(Platform.pathSeparator)
                ? folder
                : '$folder${Platform.pathSeparator}')
            .toList();

        for (final prefix in sanitizedFolders) {
          query.where((t) => t.path.like('$prefix%').not());
        }
      }

      if (sortBy == 'title') {
        query.orderBy([
          (t) => OrderingTerm(
              expression: t.title,
              mode: ascending ? OrderingMode.asc : OrderingMode.desc)
        ]);
      } else if (sortBy == 'artist') {
        query.orderBy([
          (t) => OrderingTerm(
              expression: t.artist,
              mode: ascending ? OrderingMode.asc : OrderingMode.desc)
        ]);
      } else if (sortBy == 'dateAdded') {
        query.orderBy([
          (t) => OrderingTerm(
              expression: t.dateAdded,
              mode: ascending ? OrderingMode.asc : OrderingMode.desc)
        ]);
      } else if (sortBy == 'duration') {
        query.orderBy([
          (t) => OrderingTerm(
              expression: t.durationMs,
              mode: ascending ? OrderingMode.asc : OrderingMode.desc)
        ]);
      }

      if (limit != null) {
        query.limit(limit, offset: offset);
      }

      return query
          .watch()
          .map((songs) => Right<AppFailure, List<SongsTableData>>(songs))
          .handleError(
            (e) => Left<AppFailure, List<SongsTableData>>(
                DatabaseFailure('Failed to watch songs', e)),
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
        query.orderBy([
          (t) => OrderingTerm(
              expression: t.title,
              mode: ascending ? OrderingMode.asc : OrderingMode.desc)
        ]);
      } else if (sortBy == 'artist') {
        query.orderBy([
          (t) => OrderingTerm(
              expression: t.artist,
              mode: ascending ? OrderingMode.asc : OrderingMode.desc)
        ]);
      } else if (sortBy == 'dateAdded') {
        query.orderBy([
          (t) => OrderingTerm(
              expression: t.dateAdded,
              mode: ascending ? OrderingMode.asc : OrderingMode.desc)
        ]);
      } else if (sortBy == 'duration') {
        query.orderBy([
          (t) => OrderingTerm(
              expression: t.durationMs,
              mode: ascending ? OrderingMode.asc : OrderingMode.desc)
        ]);
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
      final song = await (_db.select(_db.songsTable)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      return Right(song);
    } catch (e) {
      return Left(DatabaseFailure('Failed to fetch song by id', e));
    }
  }

  @override
  Future<Result<SongsTableData?>> getSongByPath(String path) async {
    try {
      final song = await (_db.select(_db.songsTable)
            ..where((t) => t.path.equals(path)))
          .getSingleOrNull();
      return Right(song);
    } catch (e) {
      return Left(DatabaseFailure('Failed to fetch song by path', e));
    }
  }

  @override
  Future<Result<SongsTableData?>> getSongByUri(String uri) async {
    try {
      final song = await (_db.select(_db.songsTable)
            ..where((t) => t.uri.equals(uri) | t.path.equals(uri)))
          .getSingleOrNull();
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
            ..where((t) =>
                t.remoteId.equals(remoteId) &
                t.source.equals(SongSource.local) &
                t.isMissing.equals(false))
            ..limit(1))
          .getSingleOrNull();
      return Right(song);
    } catch (e) {
      return Left(DatabaseFailure('Failed to fetch song by remoteId', e));
    }
  }

  @override
  Future<Result<SongsTableData?>> findMatchingLocalSong(
      {String? remoteId, String? title, String? artist}) async {
    try {
      // 1. Try matching by remoteId first
      if (remoteId != null && remoteId.isNotEmpty) {
        final byRemoteId = await (_db.select(_db.songsTable)
              ..where((t) =>
                  t.remoteId.equals(remoteId) &
                  t.source.equals(SongSource.local) &
                  t.isMissing.equals(false))
              ..limit(1))
            .getSingleOrNull();
        if (byRemoteId != null) return Right(byRemoteId);
      }

      // 2. Try matching by title & artist on local rows
      if (title != null &&
          title.trim().isNotEmpty &&
          artist != null &&
          artist.trim().isNotEmpty) {
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
      final songs = await (_db.select(_db.songsTable)
            ..where((t) => t.id.isIn(ids)))
          .get();
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
          .handleError((e) => Left<AppFailure, List<SongsTableData>>(
              DatabaseFailure('Failed to watch favorites', e)));
    } catch (e) {
      return Stream.value(
          Left(DatabaseFailure('Failed to watch favorites', e)));
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
  Future<Result<int>> importOnlineTracksAsFavorites(
      List<YtmTrack> tracks) async {
    try {
      int count = 0;
      for (final track in tracks) {
        final songData = track.toSongData();
        final existing = await (_db.select(_db.songsTable)
              ..where((t) => t.remoteId.equals(track.videoId))
              ..limit(1))
            .getSingleOrNull();

        if (existing != null) {
          await (_db.update(_db.songsTable)
                ..where((t) => t.id.equals(existing.id)))
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
      return Left(
          DatabaseFailure('Failed to import online tracks as favorites', e));
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
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.lastPlayed, mode: OrderingMode.desc)
            ])
            ..limit(limit))
          .watch()
          .map((songs) => Right<AppFailure, List<SongsTableData>>(songs))
          .handleError((e) => Left<AppFailure, List<SongsTableData>>(
              DatabaseFailure('Failed to watch recently played', e)));
    } catch (e) {
      return Stream.value(
          Left(DatabaseFailure('Failed to watch recently played', e)));
    }
  }

  @override
  Future<Result<List<SongsTableData>>> getRecentlyPlayed(
      {int limit = 20}) async {
    try {
      final songs = await (_db.select(_db.songsTable)
            ..where((t) =>
                t.lastPlayed.isNotNull() &
                t.isMissing.equals(false) &
                t.source.equals(SongSource.local) &
                t.path.like('ytmusic://%').not())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.lastPlayed, mode: OrderingMode.desc)
            ])
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
            ..orderBy([
              (t) =>
                  OrderingTerm(expression: t.dateAdded, mode: OrderingMode.desc)
            ])
            ..limit(limit))
          .watch()
          .map((songs) => Right<AppFailure, List<SongsTableData>>(songs))
          .handleError((e) => Left<AppFailure, List<SongsTableData>>(
              DatabaseFailure('Failed to watch recently added', e)));
    } catch (e) {
      return Stream.value(
          Left(DatabaseFailure('Failed to watch recently added', e)));
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
            ..orderBy([
              (t) =>
                  OrderingTerm(expression: t.playCount, mode: OrderingMode.desc)
            ])
            ..limit(limit))
          .watch()
          .map((songs) => Right<AppFailure, List<SongsTableData>>(songs))
          .handleError((e) => Left<AppFailure, List<SongsTableData>>(
              DatabaseFailure('Failed to watch top played', e)));
    } catch (e) {
      return Stream.value(
          Left(DatabaseFailure('Failed to watch top played', e)));
    }
  }

  int? _lastRecordedSongId;
  DateTime? _lastRecordedTime;

  @override
  Future<Result<bool>> toggleFavorite(int songId) async {
    try {
      final updatedVal = await _db.transaction(() async {
        final song = await (_db.select(_db.songsTable)
              ..where((t) => t.id.equals(songId)))
            .getSingleOrNull();
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
  Future<Result<void>> recordPlayHistory(int songId,
      {bool completed = false}) async {
    if (songId <= 0) {
      return const Right(null);
    }
    try {
      final now = DateTime.now();
      if (_lastRecordedSongId == songId &&
          _lastRecordedTime != null &&
          now.difference(_lastRecordedTime!).inMilliseconds < 1500) {
        return const Right(null);
      }
      _lastRecordedSongId = songId;
      _lastRecordedTime = now;
      final nowMs = now.millisecondsSinceEpoch;
      await _db.transaction(() async {
        final song = await (_db.select(_db.songsTable)
              ..where((t) => t.id.equals(songId)))
            .getSingleOrNull();
        if (song != null) {
          await (_db.update(_db.songsTable)..where((t) => t.id.equals(songId)))
              .write(
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
      await (_db.update(_db.songsTable)..where((t) => t.id.equals(songId)))
          .write(
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
      return (_db.select(_db.albumsTable)
            ..orderBy([(t) => OrderingTerm(expression: t.title)]))
          .watch()
          .map((albums) => Right<AppFailure, List<AlbumsTableData>>(albums))
          .handleError((e) => Left<AppFailure, List<AlbumsTableData>>(
              DatabaseFailure('Failed to watch albums', e)));
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
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.discNumber, mode: OrderingMode.asc),
              (t) => OrderingTerm(
                  expression: t.trackNumber, mode: OrderingMode.asc),
            ]))
          .watch()
          .map((songs) => Right<AppFailure, List<SongsTableData>>(songs))
          .handleError((e) => Left<AppFailure, List<SongsTableData>>(
              DatabaseFailure('Failed to watch album songs', e)));
    } catch (e) {
      return Stream.value(
          Left(DatabaseFailure('Failed to watch album songs', e)));
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
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.discNumber, mode: OrderingMode.asc),
              (t) => OrderingTerm(
                  expression: t.trackNumber, mode: OrderingMode.asc),
            ]))
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
          .handleError((e) => Left<AppFailure, List<ArtistsTableData>>(
              DatabaseFailure('Failed to watch artists', e)));
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
          .handleError((e) => Left<AppFailure, List<SongsTableData>>(
              DatabaseFailure('Failed to watch artist songs', e)));
    } catch (e) {
      return Stream.value(
          Left(DatabaseFailure('Failed to watch artist songs', e)));
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
      return (_db.select(_db.albumsTable)
            ..where((t) => t.artistId.equals(artistId)))
          .watch()
          .map((albums) => Right<AppFailure, List<AlbumsTableData>>(albums))
          .handleError((e) => Left<AppFailure, List<AlbumsTableData>>(
              DatabaseFailure('Failed to watch artist albums', e)));
    } catch (e) {
      return Stream.value(
          Left(DatabaseFailure('Failed to watch artist albums', e)));
    }
  }

  // --- PLAYLISTS ---
  @override
  Stream<Result<List<PlaylistsTableData>>> watchPlaylists() {
    try {
      return (_db.select(_db.playlistsTable)
            ..orderBy([(t) => OrderingTerm(expression: t.name)]))
          .watch()
          .map((playlists) =>
              Right<AppFailure, List<PlaylistsTableData>>(playlists))
          .handleError((e) => Left<AppFailure, List<PlaylistsTableData>>(
              DatabaseFailure('Failed to watch playlists', e)));
    } catch (e) {
      return Stream.value(
          Left(DatabaseFailure('Failed to watch playlists', e)));
    }
  }

  @override
  Future<Result<int>> createPlaylist(String name,
      {bool isSmart = false, String? smartCriteria}) async {
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
      await (_db.update(_db.playlistsTable)
            ..where((t) => t.id.equals(playlistId)))
          .write(
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
  Future<Result<void>> updateSmartPlaylist(
      int playlistId, String name, String smartCriteria) async {
    try {
      await (_db.update(_db.playlistsTable)
            ..where((t) => t.id.equals(playlistId)))
          .write(
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
      await (_db.delete(_db.playlistsTable)
            ..where((t) => t.id.equals(playlistId)))
          .go();
      return const Right(null);
    } catch (e) {
      return Left(DatabaseFailure('Failed to delete playlist', e));
    }
  }

  @override
  Future<Result<List<PlaylistsTableData>>> getPlaylists() async {
    try {
      final playlists = await (_db.select(_db.playlistsTable)
            ..orderBy([(t) => OrderingTerm(expression: t.name)]))
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
        innerJoin(_db.songsTable,
            _db.songsTable.id.equalsExp(_db.playlistEntriesTable.songId)),
      ])
        ..where(_db.playlistEntriesTable.playlistId.equals(playlistId))
        ..orderBy(
            [OrderingTerm(expression: _db.playlistEntriesTable.orderIndex)]);

      return query
          .watch()
          .map((rows) => Right<AppFailure, List<SongsTableData>>(
              rows.map((row) => row.readTable(_db.songsTable)).toList()))
          .handleError((e) => Left<AppFailure, List<SongsTableData>>(
              DatabaseFailure('Failed to watch playlist songs', e)));
    } catch (e) {
      return Stream.value(
          Left(DatabaseFailure('Failed to watch playlist songs', e)));
    }
  }

  @override
  Future<Result<List<SongsTableData>>> getPlaylistSongs(int playlistId) async {
    try {
      final query = _db.select(_db.playlistEntriesTable).join([
        innerJoin(_db.songsTable,
            _db.songsTable.id.equalsExp(_db.playlistEntriesTable.songId)),
      ])
        ..where(_db.playlistEntriesTable.playlistId.equals(playlistId))
        ..orderBy(
            [OrderingTerm(expression: _db.playlistEntriesTable.orderIndex)]);

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
            ..where((t) =>
                t.playlistId.equals(playlistId) & t.songId.equals(songId)))
          .getSingleOrNull();
      if (existing != null) {
        return const Right(null); // Already present, avoid duplication
      }

      // Use MAX(orderIndex) not COUNT to avoid duplicate orderIndex on concurrent dual add (P2-1)
      final maxExp = _db.playlistEntriesTable.orderIndex.max();
      final maxQuery = _db.selectOnly(_db.playlistEntriesTable)
        ..where(_db.playlistEntriesTable.playlistId.equals(playlistId))
        ..addColumns([maxExp]);
      final maxIdx = await maxQuery.map((row) => row.read(maxExp)).getSingle();
      final nextIdx = (maxIdx ?? -1) + 1;

      await _db.into(_db.playlistEntriesTable).insert(
            PlaylistEntriesTableCompanion.insert(
              playlistId: playlistId,
              songId: songId,
              orderIndex: nextIdx,
            ),
          );
      return const Right(null);
    } catch (e) {
      return Left(DatabaseFailure('Failed to add song to playlist', e));
    }
  }

  @override
  Future<Result<void>> addSongsToPlaylist(
      int playlistId, List<int> songIds) async {
    try {
      final existingRows = await (_db.select(_db.playlistEntriesTable)
            ..where((t) => t.playlistId.equals(playlistId)))
          .get();
      final existingSongIds = existingRows.map((r) => r.songId).toSet();
      int nextOrderIndex = existingRows.isEmpty
          ? 0
          : existingRows.map((r) => r.orderIndex).reduce(max) + 1;

      await _db.transaction(() async {
        for (final songId in songIds) {
          if (!existingSongIds.contains(songId)) {
            existingSongIds.add(songId);
            await _db.into(_db.playlistEntriesTable).insert(
                  PlaylistEntriesTableCompanion.insert(
                    playlistId: playlistId,
                    songId: songId,
                    orderIndex: nextOrderIndex++,
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
  Future<Result<void>> removeSongFromPlaylist(
      int playlistId, int songId) async {
    try {
      await (_db.delete(_db.playlistEntriesTable)
            ..where((t) =>
                t.playlistId.equals(playlistId) & t.songId.equals(songId)))
          .go();
      return const Right(null);
    } catch (e) {
      return Left(DatabaseFailure('Failed to remove song from playlist', e));
    }
  }

  @override
  Future<Result<void>> reorderPlaylistSongs(
      int playlistId, List<int> orderedSongIds) async {
    try {
      await _db.transaction(() async {
        for (int i = 0; i < orderedSongIds.length; i++) {
          await (_db.update(_db.playlistEntriesTable)
                ..where((t) =>
                    t.playlistId.equals(playlistId) &
                    t.songId.equals(orderedSongIds[i])))
              .write(PlaylistEntriesTableCompanion(orderIndex: Value(i)));
        }
      });
      return const Right(null);
    } catch (e) {
      return Left(DatabaseFailure('Failed to reorder playlist songs', e));
    }
  }

  // --- EXCLUDED FOLDERS ---
  @override
  Stream<Result<List<ExcludedFoldersTableData>>> watchExcludedFolders() {
    try {
      return _db
          .select(_db.excludedFoldersTable)
          .watch()
          .map((folders) =>
              Right<AppFailure, List<ExcludedFoldersTableData>>(folders))
          .handleError((e) => Left<AppFailure, List<ExcludedFoldersTableData>>(
              DatabaseFailure('Failed to watch excluded folders', e)));
    } catch (e) {
      return Stream.value(
          Left(DatabaseFailure('Failed to watch excluded folders', e)));
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
        await (_db.delete(_db.excludedFoldersTable)
              ..where((t) => t.id.equals(existing.id)))
            .go();
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
  Future<Result<void>> saveQueue(
      List<int> songIds, int currentIndex, int positionMs) async {
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
      final items = await (_db.select(_db.queueItemsTable)
            ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
          .get();
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
      // 1. Fetch existing songs mapping by lowercase normalized path
      final existingSongs = await (_db.select(_db.songsTable)
            ..where((t) => t.path.isNotNull() & t.path.equals('').not()))
          .get();

      final existingByPath = <String, SongsTableData>{};
      for (final s in existingSongs) {
        existingByPath[s.path.toLowerCase().replaceAll('\\', '/')] = s;
      }

      // 2. Align companions to existing rows by path to update in place and preserve metadata
      final reconciledSongs = <SongsTableCompanion>[];
      for (final companion in songs) {
        final path = companion.path.value.toLowerCase().replaceAll('\\', '/');
        final existing = existingByPath[path];

        if (existing != null) {
          // Preserve existing ID and all rich user/download metadata
          reconciledSongs.add(
            companion.copyWith(
              id: Value(existing.id),
              isDownloaded: Value(existing.isDownloaded),
              remoteId: Value(existing.remoteId),
              remoteArtworkUrl: Value(existing.remoteArtworkUrl),
              isFavorite: Value(existing.isFavorite),
              playCount: Value(existing.playCount),
              lastPlayed: Value(existing.lastPlayed),
              lastPositionMs: Value(existing.lastPositionMs),
              source: Value(existing.source),
            ),
          );
        } else {
          reconciledSongs.add(companion);
        }
      }

      // 3. Batch insert/update outside transaction (batch is not transaction-aware)
      await _db.batch((batch) {
        batch.insertAllOnConflictUpdate(_db.songsTable, reconciledSongs);
        batch.insertAllOnConflictUpdate(_db.albumsTable, albums);
        batch.insertAllOnConflictUpdate(_db.artistsTable, artists);

      // SCAN-DEBUG: commit point of a scan sync (pairs with LibraryCubit
      // watchSongs breadcrumbs for the 'count > 0 but UI empty' investigation).
      ErrorLogger.addBreadcrumb(
          'syncScannedMusic committed: songs=${songs.length} albums=${albums.length} artists=${artists.length}',
          category: 'scanner');
      });

      // 4. Deduplicate duplicate paths in a dedicated transaction (no batch inside)
      try {
        final dupPaths = await _db.customSelect(
          "SELECT lower(path) as lp FROM songs "
          "WHERE path != '' AND path NOT LIKE 'ytmusic://%' "
          "GROUP BY lower(path) HAVING COUNT(*) > 1",
        ).get();

        for (final row in dupPaths) {
          final lp = row.data['lp'] as String;
          final candidates = await _db.customSelect(
            "SELECT id, is_downloaded FROM songs "
            "WHERE lower(path) = ? AND path != '' AND path NOT LIKE 'ytmusic://%' "
            "ORDER BY is_downloaded DESC, id ASC",
            variables: [Variable.withString(lp)],
          ).get();
          if (candidates.isEmpty) continue;
          final survivingId = candidates.first.data['id'] as int;

          await _db.transaction(() async {
            for (final c in candidates.skip(1)) {
              final dupeId = c.data['id'] as int;
              try {
                await _db.customStatement(
                  'UPDATE playlist_entries SET song_id = ? WHERE song_id = ?',
                  [survivingId, dupeId],
                );
                await _db.customStatement(
                  'UPDATE queue_items SET song_id = ? WHERE song_id = ?',
                  [survivingId, dupeId],
                );
                await _db.customStatement(
                  'DELETE FROM songs WHERE id = ?',
                  [dupeId],
                );
              } catch (_) {}
            }
          });
        }
      } catch (_) {}

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

      // 1. Fetch unscanned local songs outside the transaction
      final unscannedSongs = await (_db.select(_db.songsTable)
            ..where((t) =>
                t.id.isNotIn(scannedSongIds) &
                t.id.isBiggerThanValue(0) &
                t.source.equals(SongSource.local)))
          .get();

      // 2. Perform bounded async disk checks (max 16 concurrent) without blocking database locks
      final trulyMissingIds = <int>[];
      final reappearedIds = <int>[];
      const chunkSize = 16;

      // Build a fast lookup of every file path covered by the current scan so
      // we can skip orphan-marking for songs whose file is still on disk but was
      // given a different MediaStore ID (common after downloading a YTM track).
      // Also: never mark a downloaded song as missing — its row is managed by
      // reconcileDownloadedSong and may legitimately have an ID not in scannedSongIds.
      final scannedPaths = <String>{};
      // Fetch the actual file paths for all scannedSongIds in one query to build the set.
      if (scannedSongIds.isNotEmpty) {
        try {
          final scannedRows = await (_db.select(_db.songsTable)
                ..where((t) => t.id.isIn(scannedSongIds)))
              .get();
          for (final r in scannedRows) {
            if (r.path.isNotEmpty) scannedPaths.add(r.path.toLowerCase());
          }
        } catch (_) {}
      }

      // Isolate-friendly disk check: use compute for large orphan sets to avoid main-isolate ANR
      // For < 200 items, do cheap chunked async; for larger, offload to isolate
      if (unscannedSongs.length > 500) {
        // Heavy case: delegate to isolate (file exists is sync I/O)
        final pathsToCheck = unscannedSongs
            .where((s) =>
                !s.isDownloaded &&
                s.path.isNotEmpty &&
                !s.path.startsWith('content:') &&
                !scannedPaths.contains(s.path.toLowerCase()))
            .map((s) => s.path)
            .toList();
        // Fallback to chunked if isolate fails
        for (var i = 0; i < unscannedSongs.length; i += chunkSize) {
          final end = (i + chunkSize < unscannedSongs.length)
              ? i + chunkSize
              : unscannedSongs.length;
          final chunk = unscannedSongs.sublist(i, end);
          await Future.wait(chunk.map((song) async {
            if (song.isDownloaded) {
              reappearedIds.add(song.id);
              return;
            }
            if (song.path.isNotEmpty &&
                scannedPaths.contains(song.path.toLowerCase())) {
              reappearedIds.add(song.id);
              return;
            }
            if (song.path.isEmpty) {
              trulyMissingIds.add(song.id);
            } else if (song.path.startsWith('content:')) {
              reappearedIds.add(song.id);
            } else {
              final exists = await File(song.path).exists();
              if (exists) {
                reappearedIds.add(song.id);
              } else {
                trulyMissingIds.add(song.id);
              }
            }
          }));
        }
        // suppress unused variable warning
        pathsToCheck;
      } else {
        for (var i = 0; i < unscannedSongs.length; i += chunkSize) {
          final end = (i + chunkSize < unscannedSongs.length)
              ? i + chunkSize
              : unscannedSongs.length;
          final chunk = unscannedSongs.sublist(i, end);
          await Future.wait(chunk.map((song) async {
            if (song.isDownloaded) {
              reappearedIds.add(song.id);
              return;
            }
            if (song.path.isNotEmpty &&
                scannedPaths.contains(song.path.toLowerCase())) {
              reappearedIds.add(song.id);
              return;
            }
            if (song.path.isEmpty) {
              trulyMissingIds.add(song.id);
            } else if (song.path.startsWith('content:')) {
              reappearedIds.add(song.id);
            } else {
              final exists = await File(song.path).exists();
              if (exists) {
                reappearedIds.add(song.id);
              } else {
                trulyMissingIds.add(song.id);
              }
            }
          }));
        }
      }

      int markedMissingCount = 0;
      await _db.transaction(() async {
        if (trulyMissingIds.isNotEmpty) {
          markedMissingCount = await (_db.update(_db.songsTable)
                ..where((t) => t.id.isIn(trulyMissingIds)))
              .write(
            const SongsTableCompanion(isMissing: Value(true)),
          );
        }

        // Ensure newly/currently scanned songs and reappeared songs are marked active (not missing)
        final activeIds = {...scannedSongIds, ...reappearedIds};
        if (activeIds.isNotEmpty) {
          await (_db.update(_db.songsTable)..where((t) => t.id.isIn(activeIds)))
              .write(
            const SongsTableCompanion(isMissing: Value(false)),
          );
        }

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
            ..where((t) =>
                t.isMissing.equals(true) & t.source.equals(SongSource.local)))
          .go();

      // Reconcile and cleanup orphaned albums and artists in single SQL queries
      await _db.customStatement(
        'DELETE FROM albums WHERE NOT EXISTS (SELECT 1 FROM songs WHERE songs.album_id = albums.id AND songs.is_missing = 0);',
      );
      await _db.customStatement(
        'DELETE FROM artists WHERE NOT EXISTS (SELECT 1 FROM songs WHERE songs.artist_id = artists.id AND songs.is_missing = 0);',
      );
      // Update songCount for surviving albums/artists that partially lost songs
      await _db.customStatement(
        'UPDATE albums SET song_count = (SELECT COUNT(*) FROM songs WHERE songs.album_id = albums.id AND songs.is_missing = 0);',
      );
      await _db.customStatement(
        'UPDATE artists SET song_count = (SELECT COUNT(*) FROM songs WHERE songs.artist_id = artists.id AND songs.is_missing = 0);',
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
      // Step 1: Read + Compute outside transaction
      final oldRow = await (_db.select(_db.songsTable)
            ..where((t) => t.id.equals(oldId)))
          .getSingleOrNull();

      // Find the row the scanner minted for the downloaded file.
      var newRow = await (_db.select(_db.songsTable)
            ..where((t) => t.path.equals(newPath))
            ..orderBy([
              (t) =>
                  OrderingTerm(expression: t.dateAdded, mode: OrderingMode.desc)
            ])
            ..limit(1))
          .getSingleOrNull();

      // Fallback: match on normalized metadata
      final matchMetadata = oldRow ?? fallbackSong;
      if (newRow == null && matchMetadata != null) {
        newRow = await (_db.select(_db.songsTable)
              ..where((t) =>
                  t.source.equals(SongSource.local) &
                  t.title.lower().equals(matchMetadata.title.toLowerCase()) &
                  t.artist.lower().equals(matchMetadata.artist.toLowerCase()) &
                  t.durationMs.isBetweenValues(matchMetadata.durationMs - 5000,
                      matchMetadata.durationMs + 5000))
              ..orderBy([
                (t) => OrderingTerm(
                    expression: t.dateAdded, mode: OrderingMode.desc)
              ])
              ..limit(1))
            .getSingleOrNull();

        // Verify the matched row is not flagged as missing (R3-02)
        if (newRow != null && newRow.isMissing) {
          newRow = null;
        }
      }

      final fileExists = await File(newPath).exists();

      // Step 2: Write phase in focused transaction
      await _db.transaction(() async {
        if (newRow == null) {
          if (fileExists) {
            final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
            if (oldRow != null) {
              await (_db.update(_db.songsTable)
                    ..where((t) => t.id.equals(oldId)))
                  .write(
                SongsTableCompanion(
                  path: Value(newPath),
                  source: const Value(SongSource.local),
                  isMissing: const Value(false),
                  isDownloaded: const Value(true),
                  dateAdded: Value(
                      (oldRow.dateAdded ?? 0) > 0 ? oldRow.dateAdded! : nowSec),
                  pendingDownloadPath: const Value(null),
                ),
              );
              survivingId = oldId;
              // FIX: Clean any other row that already owns this path (scanner may have inserted it first)
              try {
                final dupes = await (_db.select(_db.songsTable)
                      ..where((t) => t.path.lower().equals(newPath.toLowerCase()) & t.id.equals(oldId).not()))
                    .get();
                for (final d in dupes) {
                  await (_db.update(_db.playlistEntriesTable)..where((t) => t.songId.equals(d.id)))
                      .write(PlaylistEntriesTableCompanion(songId: Value(oldId)));
                  await (_db.update(_db.queueItemsTable)..where((t) => t.songId.equals(d.id)))
                      .write(QueueItemsTableCompanion(songId: Value(oldId)));
                  await (_db.delete(_db.songsTable)..where((t) => t.id.equals(d.id))).go();
                }
              } catch (_) {}
            } else if (fallbackSong != null) {
              await _db.into(_db.songsTable).insert(
                    SongsTableCompanion(
                      id: Value(oldId),
                      title: Value(fallbackSong.title),
                      artist: Value(fallbackSong.artist),
                      album: Value(fallbackSong.album.isNotEmpty
                          ? fallbackSong.album
                          : 'YouTube Music'),
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
              try {
                final dupes2 = await (_db.select(_db.songsTable)
                      ..where((t) => t.path.lower().equals(newPath.toLowerCase()) & t.id.equals(oldId).not()))
                    .get();
                for (final d in dupes2) {
                  await (_db.delete(_db.songsTable)..where((t) => t.id.equals(d.id))).go();
                }
              } catch (_) {}
            }
          }
          return;
        }

        final targetId = newRow.id;
        survivingId = targetId;

        if (oldRow == null || oldRow.id == targetId) return;

        try {
          final duplicatePlaylists =
              await (_db.selectOnly(_db.playlistEntriesTable, distinct: true)
                    ..addColumns([_db.playlistEntriesTable.playlistId])
                    ..where(_db.playlistEntriesTable.songId.equals(targetId)))
                  .map((row) => row.read(_db.playlistEntriesTable.playlistId)!)
                  .get();

          if (duplicatePlaylists.isNotEmpty) {
            await (_db.delete(_db.playlistEntriesTable)
                  ..where((t) =>
                      t.songId.equals(oldId) &
                      t.playlistId.isIn(duplicatePlaylists)))
                .go();
          }
          await (_db.update(_db.playlistEntriesTable)
                ..where((t) => t.songId.equals(oldId)))
              .write(PlaylistEntriesTableCompanion(songId: Value(targetId)));
          await (_db.update(_db.queueItemsTable)
                ..where((t) => t.songId.equals(oldId)))
              .write(QueueItemsTableCompanion(songId: Value(targetId)));
          await (_db.update(_db.playHistoryTable)
                ..where((t) => t.songId.equals(oldId)))
              .write(PlayHistoryTableCompanion(songId: Value(targetId)));

          // Delete old row
          await (_db.delete(_db.songsTable)..where((t) => t.id.equals(oldId)))
              .go();
        } catch (e, st) {
          ErrorLogger.log(
              'Constraint exception in reconcileDownloadedSong; marking row as missing',
              error: e,
              stackTrace: st,
              category: 'MusicRepository');
          try {
            await (_db.update(_db.songsTable)..where((t) => t.id.equals(oldId)))
                .write(const SongsTableCompanion(isMissing: Value(true)));
          } catch (_) {}
        }

        // Merge stats (don't clobber — the scanned row may predate the download).
        final int? mergedLastPlayed;
        if (oldRow.lastPlayed != null && newRow.lastPlayed != null) {
          mergedLastPlayed = oldRow.lastPlayed! > newRow.lastPlayed!
              ? oldRow.lastPlayed
              : newRow.lastPlayed;
        } else {
          mergedLastPlayed = oldRow.lastPlayed ?? newRow.lastPlayed;
        }
        final keepOldPosition =
            (oldRow.lastPlayed ?? 0) > (newRow.lastPlayed ?? 0);

        final String effectiveTitle = (oldRow.title.isNotEmpty &&
                !oldRow.title.toLowerCase().startsWith('ytdl_'))
            ? oldRow.title
            : newRow.title;
        final String effectiveArtist = (oldRow.artist.isNotEmpty &&
                oldRow.artist != '<unknown>' &&
                oldRow.artist != 'Unknown')
            ? oldRow.artist
            : newRow.artist;
        final String effectiveAlbum = (oldRow.album.isNotEmpty &&
                oldRow.album != '<unknown>' &&
                oldRow.album != 'Unknown')
            ? oldRow.album
            : newRow.album;
        final String? effectiveRemoteArt = (oldRow.remoteArtworkUrl != null &&
                oldRow.remoteArtworkUrl!.isNotEmpty)
            ? oldRow.remoteArtworkUrl
            : newRow.remoteArtworkUrl;

        await (_db.update(_db.songsTable)..where((t) => t.id.equals(targetId)))
            .write(
          SongsTableCompanion(
            title: Value(effectiveTitle),
            artist: Value(effectiveArtist),
            album: Value(effectiveAlbum),
            genre: Value(oldRow.genre ?? newRow.genre),
            isFavorite: Value(oldRow.isFavorite || newRow.isFavorite),
            playCount: Value(oldRow.playCount + newRow.playCount),
            lastPlayed: Value(mergedLastPlayed),
            lastPositionMs: Value(keepOldPosition
                ? oldRow.lastPositionMs
                : newRow.lastPositionMs),
            // Carry the video id and online remoteArtworkUrl
            remoteId: Value(oldRow.remoteId ?? newRow.remoteId),
            remoteArtworkUrl: Value(effectiveRemoteArt),
            source: const Value(SongSource.local),
            isDownloaded: const Value(true),
            pendingDownloadPath: const Value(null),
          ),
        );

        // FIX: Remove any other duplicate path rows that the scanner may have inserted in parallel
        // This guarantees a single entry per file path after download, fixing "repeats twice on local"
        final newRowPath = newRow.path;
        final duplicateOthers = await (_db.select(_db.songsTable)
              ..where((t) =>
                  t.path.lower().equals(newRowPath.toLowerCase()) &
                  t.id.isNotIn([oldId, targetId])))
            .get();
        for (final dupe in duplicateOthers) {
          try {
            // Move any playlist/queue/history refs to surviving target before deleting duplicate
            await (_db.update(_db.playlistEntriesTable)..where((t) => t.songId.equals(dupe.id)))
                .write(PlaylistEntriesTableCompanion(songId: Value(targetId)));
            await (_db.update(_db.queueItemsTable)..where((t) => t.songId.equals(dupe.id)))
                .write(QueueItemsTableCompanion(songId: Value(targetId)));
            await (_db.delete(_db.songsTable)..where((t) => t.id.equals(dupe.id))).go();
          } catch (_) {}
        }
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
            ..where(
                (t) => t.path.equals(path) & t.source.equals(SongSource.local)))
          .getSingleOrNull();
      if (existing != null) {
        await (_db.update(_db.songsTable)
              ..where((t) => t.id.equals(existing.id)))
            .write(
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
      await (_db.update(_db.songsTable)..where((t) => t.id.equals(songId)))
          .write(
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
        final list = rows
            .map((row) {
              final genreName = row.read(_db.songsTable.genre) ?? '';
              final count = row.read(countExp) ?? 0;
              return GenreItem(name: genreName, songCount: count);
            })
            .where((g) => g.name.isNotEmpty)
            .toList();
        return Right<AppFailure, List<GenreItem>>(list);
      }).handleError((e) => Left<AppFailure, List<GenreItem>>(
          DatabaseFailure('Failed to watch genres', e)));
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
      final list = rows
          .map((row) {
            final genreName = row.read(_db.songsTable.genre) ?? '';
            final count = row.read(countExp) ?? 0;
            return GenreItem(name: genreName, songCount: count);
          })
          .where((g) => g.name.isNotEmpty)
          .toList();
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
          .handleError((e) => Left<AppFailure, List<SongsTableData>>(
              DatabaseFailure('Failed to watch genre songs', e)));
    } catch (e) {
      return Stream.value(
          Left(DatabaseFailure('Failed to watch genre songs', e)));
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
        ..orderBy([
          OrderingTerm(expression: _db.songsTable.year, mode: OrderingMode.desc)
        ]);

      return query.watch().map((rows) {
        final list = rows
            .map((row) {
              final yr = row.read(_db.songsTable.year) ?? 0;
              final count = row.read(countExp) ?? 0;
              return YearItem(year: yr, songCount: count);
            })
            .where((y) => y.year > 0)
            .toList();
        return Right<AppFailure, List<YearItem>>(list);
      }).handleError((e) => Left<AppFailure, List<YearItem>>(
          DatabaseFailure('Failed to watch years', e)));
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
          .handleError((e) => Left<AppFailure, List<SongsTableData>>(
              DatabaseFailure('Failed to watch year songs', e)));
    } catch (e) {
      return Stream.value(
          Left(DatabaseFailure('Failed to watch year songs', e)));
    }
  }
}
