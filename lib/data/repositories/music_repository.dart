import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/prefs_keys.dart';
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
            t.path.like('ytmusic://%').not() &
            t.path.equals('').not());

      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        final sanitizedQuery = searchQuery
            .trim()
            .toLowerCase()
            .replaceAll(r'\', r'\\')
            .replaceAll('%', r'\%')
            .replaceAll('_', r'\_');
        final pattern = '%$sanitizedQuery%';
        query.where((t) =>
            t.title.lower().like(pattern) |
            t.artist.lower().like(pattern) |
            t.album.lower().like(pattern));
      }

      if (excludedFolders.isNotEmpty) {
        final sanitizedFolders = excludedFolders
            .where((f) => f.trim().isNotEmpty)
            .map((folder) => folder.endsWith(Platform.pathSeparator)
                ? folder
                : '$folder${Platform.pathSeparator}')
            .toList();

        for (final prefix in sanitizedFolders) {
          final escapedPrefix = prefix
              .replaceAll(r'\', r'\\')
              .replaceAll('%', r'\%')
              .replaceAll('_', r'\_');
          query.where((t) => t.path.like('$escapedPrefix%').not());
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
            (Object e) => Left<AppFailure, List<SongsTableData>>(
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
            t.path.like('ytmusic://%').not() &
            t.path.equals('').not());
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
      // FIX(BUG-16): Exclude remote ytmusic:// sentinels from local path queries
      final song = await (_db.select(_db.songsTable)
            ..where((t) => t.path.equals(path) & t.path.like('ytmusic://%').not()))
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
      // FIX(D1): Guard nullable params early before querying
      if ((remoteId == null || remoteId.isEmpty) &&
          (title == null ||
              title.trim().isEmpty ||
              artist == null ||
              artist.trim().isEmpty)) {
        return const Right(null);
      }

      // 1. Try matching by remoteId first
      if (remoteId != null && remoteId.isNotEmpty) {
        // FIX(BUG-16): Ensure local row query excludes ytmusic:// sentinels
        final byRemoteId = await (_db.select(_db.songsTable)
              ..where((t) =>
                  t.remoteId.equals(remoteId) &
                  t.source.equals(SongSource.local) &
                  t.isMissing.equals(false) &
                  t.path.like('ytmusic://%').not())
              ..limit(1))
            .getSingleOrNull();
        if (byRemoteId != null) return Right(byRemoteId);
      }

      // 2. Try matching by title & artist on local rows
      if (title != null &&
          title.trim().isNotEmpty &&
          artist != null &&
          artist.trim().isNotEmpty) {
        // FIX(BUG-16): Ensure local metadata match excludes ytmusic:// sentinels
        final byMeta = await (_db.select(_db.songsTable)
              ..where((t) =>
                  t.source.equals(SongSource.local) &
                  t.isMissing.equals(false) &
                  t.path.like('ytmusic://%').not() &
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
      // FIX: chunk to 500 (SQLite ~999 var limit), filter missing, restore
      // caller order (IN returns arbitrary order) so playlists/queues keep order.
      final ordered = <SongsTableData>[];
      for (var i = 0; i < ids.length; i += 500) {
        final chunk =
            ids.sublist(i, (i + 500 > ids.length) ? ids.length : i + 500);
        final songs = await (_db.select(_db.songsTable)
              ..where((t) => t.id.isIn(chunk) & t.isMissing.equals(false)))
            .get();
        final byId = {for (final s in songs) s.id: s};
        for (final id in chunk) {
          final s = byId[id];
          if (s != null) ordered.add(s);
        }
      }
      return Right(ordered);
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
          .handleError((Object e) => Left<AppFailure, List<SongsTableData>>(
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
                t.path.like('ytmusic://%').not())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.lastPlayed, mode: OrderingMode.desc)
            ])
            ..limit(limit))
          .watch()
          .map((songs) => Right<AppFailure, List<SongsTableData>>(songs))
          .handleError((Object e) => Left<AppFailure, List<SongsTableData>>(
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
          .handleError((Object e) => Left<AppFailure, List<SongsTableData>>(
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
          .handleError((Object e) => Left<AppFailure, List<SongsTableData>>(
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
      // FIX(BUG-27): Explicit failure with songId when not found
      return Left(DatabaseFailure('Song not found (id=$songId)'));
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
      final prefs = await SharedPreferences.getInstance();
      final lastSongId =
          _lastRecordedSongId ?? prefs.getInt(PrefsKeys.historyLastSongId);
      final lastTimeMs = _lastRecordedTime?.millisecondsSinceEpoch ??
          prefs.getInt(PrefsKeys.historyLastTimeMs);
      final now = DateTime.now();
      final nowMs = now.millisecondsSinceEpoch;
      // FIX(S1-FU): Dedupe play-history across in-memory calls and cold restarts within 1500ms using PrefsKeys
      if (lastSongId == songId &&
          lastTimeMs != null &&
          (nowMs - lastTimeMs) < 1500) {
        return const Right(null);
      }
      _lastRecordedSongId = songId;
      _lastRecordedTime = now;
      unawaited(prefs.setInt(PrefsKeys.historyLastSongId, songId));
      unawaited(prefs.setInt(PrefsKeys.historyLastTimeMs, nowMs));
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
          .handleError((Object e) => Left<AppFailure, List<AlbumsTableData>>(
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
          .handleError((Object e) => Left<AppFailure, List<SongsTableData>>(
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
          .handleError((Object e) => Left<AppFailure, List<ArtistsTableData>>(
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
          .handleError((Object e) => Left<AppFailure, List<SongsTableData>>(
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
          .handleError((Object e) => Left<AppFailure, List<AlbumsTableData>>(
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
          .handleError((Object e) => Left<AppFailure, List<PlaylistsTableData>>(
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
          .handleError((Object e) => Left<AppFailure, List<SongsTableData>>(
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
          .handleError((Object e) => Left<AppFailure, List<ExcludedFoldersTableData>>(
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
        // FIX(BUG-09): Perform in-place upsert/replacement matching existing row IDs
        // to prevent temporary empty-table window on process kill.
        final existing = await (_db.select(_db.queueItemsTable)
              ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
            .get();
        await _db.batch((batch) {
          for (int i = 0; i < songIds.length; i++) {
            final companion = QueueItemsTableCompanion(
              id: i < existing.length ? Value(existing[i].id) : const Value.absent(),
              songId: Value(songIds[i]),
              orderIndex: Value(i),
              isCurrent: Value(i == currentIndex),
              positionMs: Value(i == currentIndex ? positionMs : 0),
            );
            batch.insert(
              _db.queueItemsTable,
              companion,
              mode: InsertMode.insertOrReplace,
            );
          }
          if (existing.length > songIds.length) {
            final surplusIds = existing
                .sublist(songIds.length)
                .map((e) => e.id)
                .toList();
            batch.deleteWhere(
              _db.queueItemsTable,
              (t) => t.id.isIn(surplusIds),
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
          // Preserve existing ID and all rich user/download metadata.
          // FIX: also preserve enriched audio-header fields + clear isMissing
          // so a rescanned track reappears immediately with quality intact.
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
              isMissing: const Value(false),
              codec: Value(existing.codec),
              bitDepth: Value(existing.bitDepth),
              bitrateKbps: Value(existing.bitrateKbps),
              sampleRate: Value(existing.sampleRate),
              loudnessRange: Value(existing.loudnessRange),
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
              } catch (e, st) {
                ErrorLogger.log('music_repository failed', error: e, stackTrace: st, category: 'MusicRepository');
              }
            }
          });
        }
      } catch (e, st) {
        ErrorLogger.log('music_repository failed', error: e, stackTrace: st, category: 'MusicRepository');
      }

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

      // 1. Fetch unscanned local songs outside the transaction.
      // FIX: chunk-safe — isNotIn() with >999 vars crashes SQLite. Fetch all
      // local rows once and exclude in Dart (libraries are ~10k rows max).
      final allLocal = await (_db.select(_db.songsTable)
            ..where((t) =>
                t.id.isBiggerThanValue(0) &
                t.source.equals(SongSource.local)))
          .get();
      final unscannedSongs =
          allLocal.where((s) => !scannedSongIds.contains(s.id)).toList();

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
      // Fetch the actual file paths for all scannedSongIds in chunks of 500
      // (SQLite var limit) to build the set.
      if (scannedSongIds.isNotEmpty) {
        try {
          final idList = scannedSongIds.toList();
          for (var i = 0; i < idList.length; i += 500) {
            final chunk = idList.sublist(
                i, (i + 500 > idList.length) ? idList.length : i + 500);
            final scannedRows = await (_db.select(_db.songsTable)
                  ..where((t) => t.id.isIn(chunk)))
                .get();
            for (final r in scannedRows) {
              if (r.path.isNotEmpty) scannedPaths.add(r.path.toLowerCase());
            }
          }
        } catch (e, st) {
          ErrorLogger.log('cleanupOrphanedSongs failed', error: e, stackTrace: st, category: 'MusicRepository');
        }
      }

      // Isolate-friendly disk check: use compute for large orphan sets to avoid main-isolate ANR
      // For < 200 items, do cheap chunked async; for larger, offload to isolate
      if (unscannedSongs.length > 500) {
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

  // FIX(D3): Single unified helper for reassigning FKs and deleting duplicate path rows
  Future<void> _dedupeByPath(String newPath, int survivingId) async {
    final dupes = await (_db.select(_db.songsTable)
          ..where((t) =>
              t.path.lower().equals(newPath.toLowerCase()) &
              t.id.equals(survivingId).not()))
        .get();
    for (final dupe in dupes) {
      try {
        await (_db.update(_db.playlistEntriesTable)
              ..where((t) => t.songId.equals(dupe.id)))
            .write(PlaylistEntriesTableCompanion(songId: Value(survivingId)));
        await (_db.update(_db.queueItemsTable)
              ..where((t) => t.songId.equals(dupe.id)))
            .write(QueueItemsTableCompanion(songId: Value(survivingId)));
        await (_db.update(_db.playHistoryTable)
              ..where((t) => t.songId.equals(dupe.id)))
            .write(PlayHistoryTableCompanion(songId: Value(survivingId)));
        await (_db.delete(_db.songsTable)..where((t) => t.id.equals(dupe.id)))
            .go();
      } catch (e, st) {
        ErrorLogger.log('_dedupeByPath failed', error: e, stackTrace: st, category: 'MusicRepository');
      }
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
      final fileExists = await File(newPath).exists();

      // FIX(D3): Wrap entire reconcile lifecycle in a single atomic transaction
      await _db.transaction(() async {
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
        }

        final targetRow = newRow;

        if (targetRow == null) {
          if (fileExists) {
            final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
            final baseSong = oldRow ?? fallbackSong;
            if (baseSong != null) {
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
              } else {
                await _db.into(_db.songsTable).insert(
                      SongsTableCompanion(
                        id: Value(oldId),
                        title: Value(baseSong.title),
                        artist: Value(baseSong.artist),
                        album: Value(baseSong.album.isNotEmpty
                            ? baseSong.album
                            : 'YouTube Music'),
                        durationMs: Value(baseSong.durationMs),
                        path: Value(newPath),
                        source: const Value(SongSource.local),
                        isMissing: const Value(false),
                        isDownloaded: const Value(true),
                        remoteId: Value(baseSong.remoteId),
                        remoteArtworkUrl: Value(baseSong.remoteArtworkUrl),
                        dateAdded: Value(nowSec),
                      ),
                      mode: InsertMode.insertOrReplace,
                    );
              }
              survivingId = oldId;
              await _dedupeByPath(newPath, survivingId!);
            }
          }
          return;
        }

        // Target row exists from scanner
        if (targetRow.isMissing || targetRow.path != newPath) {
          await (_db.update(_db.songsTable)
                ..where((t) => t.id.equals(targetRow.id)))
              .write(SongsTableCompanion(
            path: Value(newPath),
            isMissing: const Value(false),
            isDownloaded: const Value(true),
          ));
        }

        final targetId = targetRow.id;
        survivingId = targetId;

        if (oldRow == null || oldRow.id == targetId) {
          await _dedupeByPath(newPath, survivingId!);
          return;
        }
        final oldData = oldRow;
        final newData = targetRow;

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
          } catch (e, st) {
            ErrorLogger.log('equals failed', error: e, stackTrace: st, category: 'MusicRepository');
          }
        }

        // Merge stats (don't clobber — the scanned row may predate the download).
        final int? mergedLastPlayed;
        if (oldData.lastPlayed != null && newData.lastPlayed != null) {
          mergedLastPlayed = oldData.lastPlayed! > newData.lastPlayed!
              ? oldData.lastPlayed
              : newData.lastPlayed;
        } else {
          mergedLastPlayed = oldData.lastPlayed ?? newData.lastPlayed;
        }
        final keepOldPosition =
            (oldData.lastPlayed ?? 0) > (newData.lastPlayed ?? 0);

        final String effectiveTitle = (oldData.title.isNotEmpty &&
                !oldData.title.toLowerCase().startsWith('ytdl_'))
            ? oldData.title
            : newData.title;
        final String effectiveArtist = (oldData.artist.isNotEmpty &&
                oldData.artist != '<unknown>' &&
                oldData.artist != 'Unknown')
            ? oldData.artist
            : newData.artist;
        final String effectiveAlbum = (oldData.album.isNotEmpty &&
                oldData.album != '<unknown>' &&
                oldData.album != 'Unknown')
            ? oldData.album
            : newData.album;
        final String? effectiveRemoteArt = (oldData.remoteArtworkUrl != null &&
                oldData.remoteArtworkUrl!.isNotEmpty)
            ? oldData.remoteArtworkUrl
            : newData.remoteArtworkUrl;

        await (_db.update(_db.songsTable)..where((t) => t.id.equals(targetId)))
            .write(
          SongsTableCompanion(
            title: Value(effectiveTitle),
            artist: Value(effectiveArtist),
            album: Value(effectiveAlbum),
            genre: Value(oldData.genre ?? newData.genre),
            isFavorite: Value(oldData.isFavorite || newData.isFavorite),
            playCount: Value(oldData.playCount + newData.playCount),
            lastPlayed: Value(mergedLastPlayed),
            lastPositionMs: Value(keepOldPosition
                ? oldData.lastPositionMs
                : newData.lastPositionMs),
            remoteId: Value(oldData.remoteId ?? newData.remoteId),
            remoteArtworkUrl: Value(effectiveRemoteArt),
            source: const Value(SongSource.local),
            isDownloaded: const Value(true),
            pendingDownloadPath: const Value(null),
          ),
        );

        // Delete any duplicate rows matching path using unified helper
        await _dedupeByPath(newPath, survivingId!);
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
      }).handleError((Object e) => Left<AppFailure, List<GenreItem>>(
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
          .handleError((Object e) => Left<AppFailure, List<SongsTableData>>(
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
      }).handleError((Object e) => Left<AppFailure, List<YearItem>>(
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
          .handleError((Object e) => Left<AppFailure, List<SongsTableData>>(
              DatabaseFailure('Failed to watch year songs', e)));
    } catch (e) {
      return Stream.value(
          Left(DatabaseFailure('Failed to watch year songs', e)));
    }
  }
}
