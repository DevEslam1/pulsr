// lib/data/repositories/music_repository.dart
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';
import '../../core/errors/failures.dart';
import '../../core/utils/cue_parser.dart';
import '../../core/utils/error_logger.dart';
import '../../domain/models/chapter_info.dart';
import '../../domain/models/genre_item.dart';
import '../../domain/models/year_item.dart';
import '../../domain/models/ytm_track.dart';
import '../../domain/repositories/music_repository_interface.dart';
import '../../core/utils/input_sanitizer.dart';
import '../db/app_database.dart';

@Singleton(as: IMusicRepository)
class MusicRepository implements IMusicRepository {
  final AppDatabase _db;

  MusicRepository(this._db);

  /// Escapes LIKE metacharacters (%, _, \) so user input and folder paths
  /// match literally. Use with `escapeChar: r'\'`.
  static String _likeEscape(String s) => s
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');

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
            (t.cueFile.isNull() | t.cueStartMs.isNotNull()));

      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        final ftsQuery = _toFtsQuery(searchQuery);
        if (ftsQuery != null && !AppDatabase.ftsRebuildFailed) {
          // 10/10 path: FTS5 index instead of full-table LIKE scan.
          return _watchSongsFts(
            ftsQuery: ftsQuery,
            sortBy: sortBy,
            ascending: ascending,
            limit: limit ?? 200,
            offset: offset,
            excludedFolders: excludedFolders,
          );
        }
        // Fallback when FTS tokenization yields no tokens: use indexed prefix search when possible
        final trimmed = searchQuery.trim();
        final escaped = _likeEscape(trimmed);
        final prefixPattern = '$escaped%';
        final containsPattern = '%$escaped%';
        query.where((t) =>
            t.title.like(prefixPattern, escapeChar: r'\') |
            t.artist.like(prefixPattern, escapeChar: r'\') |
            t.title.like(containsPattern, escapeChar: r'\') |
            t.artist.like(containsPattern, escapeChar: r'\') |
            t.album.like(containsPattern, escapeChar: r'\'));
      }

      if (excludedFolders.isNotEmpty) {
        final sanitizedFolders = excludedFolders
            .where((f) => f.trim().isNotEmpty)
            .map((folder) => folder.endsWith(Platform.pathSeparator)
                ? folder
                : '$folder${Platform.pathSeparator}')
            .toList();

        for (final prefix in sanitizedFolders) {
          query.where(
              (t) => t.path.like('${_likeEscape(prefix)}%', escapeChar: r'\').not());
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
      } else if (sortBy == 'album') {
        query.orderBy([
          (t) => OrderingTerm(
              expression: t.album,
              mode: ascending ? OrderingMode.asc : OrderingMode.desc)
        ]);
      } else if (sortBy == 'playCount') {
        query.orderBy([
          (t) => OrderingTerm(
              expression: t.playCount,
              mode: ascending ? OrderingMode.asc : OrderingMode.desc)
        ]);
      } else if (sortBy == 'lastPlayed') {
        query.orderBy([
          (t) => OrderingTerm(
              expression: t.lastPlayed,
              mode: ascending ? OrderingMode.asc : OrderingMode.desc)
        ]);
      } else if (sortBy == 'fileSize') {
        query.orderBy([
          (t) => OrderingTerm(
              expression: t.fileSize,
              mode: ascending ? OrderingMode.asc : OrderingMode.desc)
        ]);
      } else if (sortBy == 'year') {
        query.orderBy([
          (t) => OrderingTerm(
              expression: t.year,
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

  /// Sanitizes user input into a safe FTS5 prefix query. Returns null when
  /// the input has no usable token (caller falls back to LIKE).
  // FIX-D01: Sanitize SQLite FTS5 special characters (*, ", ^, -) and escape double quotes
  // P1-1: Unicode-aware tokenization supporting CJK, Cyrillic, Hebrew, Arabic, Latin, etc.
  @visibleForTesting
  static String? toFtsQuery(String input) {
    final cleanInput = input.replaceAll(RegExp(r'["*^\-]'), ' ');
    final tokens = cleanInput
        .toLowerCase()
        .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
        .where((t) => t.isNotEmpty)
        .take(8)
        .map((t) => '"${t.replaceAll('"', '""')}"*')
        .toList();
    if (tokens.isEmpty) return null;
    return tokens.join(' ');
  }

  String? _toFtsQuery(String input) => toFtsQuery(input);

  Stream<Result<List<SongsTableData>>> _watchSongsFts({
    required String ftsQuery,
    required String sortBy,
    required bool ascending,
    required int limit,
    int? offset,
    List<String> excludedFolders = const [],
  }) {
    try {
      // Text sorts are NOCASE so Arabic/diacritic titles order like the
      // indexed watchAllSongs path; numeric sorts stay binary.
      final orderCol = switch (sortBy) {
        'artist' => 's.artist COLLATE NOCASE',
        'dateAdded' => 's.date_added',
        'duration' => 's.duration_ms',
        'album' => 's.album COLLATE NOCASE',
        'playCount' => 's.play_count',
        'lastPlayed' => 's.last_played',
        'fileSize' => 's.file_size',
        'year' => 's.year',
        _ => 's.title COLLATE NOCASE',
      };
      final dir = ascending ? 'ASC' : 'DESC';
      final buffer = StringBuffer(
        'SELECT s.* FROM songs s '
        'JOIN songs_fts f ON s.id = f.rowid '
        'WHERE songs_fts MATCH ? AND s.is_missing = 0 '
        'AND (s.cue_file IS NULL OR s.cue_start_ms IS NOT NULL) ',
      );
      final vars = <Variable>[Variable.withString(ftsQuery)];
      for (final folder in excludedFolders.where((f) => f.trim().isNotEmpty)) {
        buffer.write(r"AND s.path NOT LIKE ? ESCAPE '\' ");
        final prefix = folder.endsWith(Platform.pathSeparator)
            ? folder
            : '$folder${Platform.pathSeparator}';
        vars.add(Variable.withString('${_likeEscape(prefix)}%'));
      }
      buffer.write('ORDER BY $orderCol $dir LIMIT ? ');
      vars.add(Variable.withInt(limit));
      if (offset != null) {
        buffer.write('OFFSET ?');
        vars.add(Variable.withInt(offset));
      }
        return _db
            .customSelect(buffer.toString(),
                variables: vars, readsFrom: {_db.songsTable}).watch().asyncMap((rows) async {
          final songs = await Future.wait(
              rows.map((r) => _db.songsTable.mapFromRow(r)));
          return Right<AppFailure, List<SongsTableData>>(songs);
        }).handleError(
          (e) {
            // Missing/corrupt FTS (failed migration rebuild or a damaged
            // index): attempt a bounded repair, then report. The next watch
            // re-subscribes onto the rebuilt index. repairFtsIndex caps its
            // own attempts per session, so this cannot loop.
            AppDatabase.ftsRebuildFailed = true;
            unawaited(_db.repairFtsIndex());
            return Left<AppFailure, List<SongsTableData>>(
                DatabaseFailure('Failed to watch songs (FTS)', e));
          },
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
            (t.cueFile.isNull() | t.cueStartMs.isNotNull()));
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
      } else if (sortBy == 'album') {
        query.orderBy([
          (t) => OrderingTerm(
              expression: t.album,
              mode: ascending ? OrderingMode.asc : OrderingMode.desc)
        ]);
      } else if (sortBy == 'playCount') {
        query.orderBy([
          (t) => OrderingTerm(
              expression: t.playCount,
              mode: ascending ? OrderingMode.asc : OrderingMode.desc)
        ]);
      } else if (sortBy == 'lastPlayed') {
        query.orderBy([
          (t) => OrderingTerm(
              expression: t.lastPlayed,
              mode: ascending ? OrderingMode.asc : OrderingMode.desc)
        ]);
      } else if (sortBy == 'fileSize') {
        query.orderBy([
          (t) => OrderingTerm(
              expression: t.fileSize,
              mode: ascending ? OrderingMode.asc : OrderingMode.desc)
        ]);
      } else if (sortBy == 'year') {
        query.orderBy([
          (t) => OrderingTerm(
              expression: t.year,
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
  Future<Result<List<String>>> getLocalSongPaths() async {
    try {
      // CUE virtual tracks share their container's path — excluding them
      // here dedupes the path list (callers diff by file, not by chapter).
      final query = _db.selectOnly(_db.songsTable)
        ..addColumns([_db.songsTable.path])
        ..where(_db.songsTable.isMissing.equals(false) &
            _db.songsTable.source.equals(SongSource.local) &
            _db.songsTable.path.like('ytmusic://%').not() &
            _db.songsTable.cueStartMs.isNull());
      final rows = await query.get();
      final paths = rows
          .map((r) => r.read(_db.songsTable.path))
          .whereType<String>()
          .toList();
      return Right(paths);
    } catch (e) {
      return Left(DatabaseFailure('Failed to fetch song paths', e));
    }
  }

  @override
  Stream<Result<List<SongsTableData>>> watchSongsInFolder(String folderPath) {
    try {
      final target = _normalizeDirPath(folderPath);
      // Push the prefix into SQL so the watch doesn't re-emit the whole
      // library on every change; the Dart parent-dir check below stays as
      // the exact tiebreak (separator/case normalization). LIKE is
      // case-insensitive (PRAGMA case_sensitive_like=OFF); match both
      // separator styles and escape metacharacters.
      final slashPrefix =
          target.endsWith('/') ? target : '$target/';
      final backPrefix = slashPrefix.replaceAll('/', r'\');
      final query = _db.select(_db.songsTable)
        ..where((t) =>
            t.isMissing.equals(false) &
            t.source.equals(SongSource.local) &
            (t.path.like('${_likeEscape(slashPrefix)}%',
                    escapeChar: r'\') |
                t.path.like('${_likeEscape(backPrefix)}%',
                    escapeChar: r'\') |
                t.path.like('${_likeEscape(target)}%', escapeChar: r'\')) &
            (t.cueFile.isNull() | t.cueStartMs.isNotNull()));
      return query.watch().map((songs) {
        final filtered = songs
            .where((s) => _normalizeDirPath(_parentDirPath(s.path)) == target)
            .toList();
        return Right<AppFailure, List<SongsTableData>>(filtered);
      }).handleError((Object e) => Left<AppFailure, List<SongsTableData>>(
          DatabaseFailure('Failed to watch folder songs', e)));
    } catch (e) {
      return Stream.value(
          Left(DatabaseFailure('Failed to watch folder songs', e)));
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
            ..where((t) => t.path.equals(path))
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.cueStartMs, nulls: NullsOrder.first)
            ])
            ..limit(1))
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
            ..where((t) => t.uri.equals(uri) | t.path.equals(uri))
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.cueStartMs, nulls: NullsOrder.first)
            ])
            ..limit(1))
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
                (t.cueFile.isNull() | t.cueStartMs.isNotNull()) &
                (t.isMissing.equals(false) |
                    t.source.equals(SongSource.youtube) |
                    t.remoteId.isNotNull()))
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
                (t.cueFile.isNull() | t.cueStartMs.isNotNull()) &
                (t.isMissing.equals(false) |
                    t.source.equals(SongSource.youtube) |
                    t.remoteId.isNotNull()))
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
      // Single transaction: atomic import (no partial state on failure) and
      // one round-trip instead of 2N statements.
      final count = await _db.transaction(() async {
        var n = 0;
        for (final track in tracks) {
          final songData = track.toSongData();
          final existing = await (_db.select(_db.songsTable)
                ..where((t) => t.remoteId.equals(track.videoId))
                ..limit(1))
              .getSingleOrNull();

          if (existing != null) {
            await (_db.update(_db.songsTable)
                  ..where((t) => t.id.equals(existing.id)))
                .write(const SongsTableCompanion(
                  isFavorite: Value(true),
                  isMissing: Value(false),
                ));
            n++;
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
                    isMissing: const Value(false),
                    dateAdded: Value(DateTime.now().millisecondsSinceEpoch),
                  ),
                  mode: InsertMode.insertOrReplace,
                );
            n++;
          }
        }
        return n;
      });
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
                t.path.like('ytmusic://%').not() &
                (t.cueFile.isNull() | t.cueStartMs.isNotNull()))
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
                t.path.like('ytmusic://%').not() &
                (t.cueFile.isNull() | t.cueStartMs.isNotNull()))
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
  Future<Result<void>> clearRecentlyPlayed() async {
    try {
      await (_db.update(_db.songsTable)
            ..where((t) => t.lastPlayed.isNotNull()))
          .write(const SongsTableCompanion(lastPlayed: Value(null)));
      return const Right(null);
    } catch (e) {
      return Left(DatabaseFailure('Failed to clear recently played history', e));
    }
  }

  @override
  Stream<Result<List<SongsTableData>>> watchRecentlyAdded({int? limit = 20}) {
    try {
      final query = _db.select(_db.songsTable)
        ..where((t) =>
            t.isMissing.equals(false) &
            t.source.equals(SongSource.local) &
            t.path.like('ytmusic://%').not() &
            (t.cueFile.isNull() | t.cueStartMs.isNotNull()))
        ..orderBy([
          (t) =>
              OrderingTerm(expression: t.dateAdded, mode: OrderingMode.desc)
        ]);
      if (limit != null) {
        query.limit(limit);
      }
      return query
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
                t.path.like('ytmusic://%').not() &
                (t.cueFile.isNull() | t.cueStartMs.isNotNull()))
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
          // Atomic increment: the old read-modify-write lost increments when
          // two tracks advanced close together.
          await _db.customStatement(
            'UPDATE songs SET play_count = play_count + 1, last_played = ? WHERE id = ?;',
            [nowMs, songId],
          );
          await _db.into(_db.playHistoryTable).insert(
                PlayHistoryTableCompanion.insert(
                  songId: songId,
                  completed: Value(completed),
                ),
              );
          await _db.customStatement(
            'DELETE FROM play_history WHERE id NOT IN ('
            'SELECT id FROM play_history ORDER BY played_at DESC LIMIT 500'
            ');',
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
                t.path.like('ytmusic://%').not() &
                (t.cueFile.isNull() | t.cueStartMs.isNotNull()))
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
                t.path.like('ytmusic://%').not() &
                (t.cueFile.isNull() | t.cueStartMs.isNotNull()))
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

  @override
  Future<Result<void>> updateAlbumArtwork(
      int albumId, String artworkUrl) async {
    try {
      await (_db.update(_db.albumsTable)..where((t) => t.id.equals(albumId)))
          .write(AlbumsTableCompanion(artworkUri: Value(artworkUrl)));
      return const Right(null);
    } catch (e) {
      return Left(DatabaseFailure('Failed to update album artwork', e));
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
                t.path.like('ytmusic://%').not() &
                (t.cueFile.isNull() | t.cueStartMs.isNotNull())))
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
                t.path.like('ytmusic://%').not() &
                (t.cueFile.isNull() | t.cueStartMs.isNotNull())))
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
      final safeName = InputSanitizer.sanitizePlaylistName(name);
      final id = await _db.into(_db.playlistsTable).insert(
            PlaylistsTableCompanion.insert(
              name: safeName,
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
      final safeName = InputSanitizer.sanitizePlaylistName(newName);
      await (_db.update(_db.playlistsTable)
            ..where((t) => t.id.equals(playlistId)))
          .write(
        PlaylistsTableCompanion(
          name: Value(safeName),
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
      final safeName = InputSanitizer.sanitizePlaylistName(name);
      await (_db.update(_db.playlistsTable)
            ..where((t) => t.id.equals(playlistId)))
          .write(
        PlaylistsTableCompanion(
          name: Value(safeName),
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
      // Atomic check+MAX+insert: closes the dual-add race. The v11 unique
      // index on (playlist_id, song_id) is the final backstop — a conflict
      // insert becomes a no-op instead of a duplicate row.
      await _db.transaction(() async {
        final existing = await (_db.select(_db.playlistEntriesTable)
              ..where((t) =>
                  t.playlistId.equals(playlistId) & t.songId.equals(songId)))
            .getSingleOrNull();
        if (existing != null) return;

        // Use MAX(orderIndex) not COUNT to avoid duplicate orderIndex on concurrent dual add (P2-1)
        final maxExp = _db.playlistEntriesTable.orderIndex.max();
        final maxQuery = _db.selectOnly(_db.playlistEntriesTable)
          ..where(_db.playlistEntriesTable.playlistId.equals(playlistId))
          ..addColumns([maxExp]);
        final maxIdx =
            await maxQuery.map((row) => row.read(maxExp)).getSingle();
        final nextIdx = (maxIdx ?? -1) + 1;

        await _db.into(_db.playlistEntriesTable).insert(
              PlaylistEntriesTableCompanion.insert(
                playlistId: playlistId,
                songId: songId,
                orderIndex: nextIdx,
              ),
              mode: InsertMode.insertOrIgnore,
            );
      });
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
  // Ownership (defect 10-01): this Drift table is the cold-resume source of
  // truth for the audio service. [AudioHandler] writes it — a full rewrite on
  // structural queue edits, and a single-row position refresh on the periodic
  // flush — and reads it back on cold start. PlayerCubit's `queue_slots_v1`
  // preference holds the editable 3-slot UI state used for slot switching.
  // Backup restore is the only other writer, by design.
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

  @override
  Future<Result<void>> updateQueuePosition(int positionMs) async {
    try {
      await (_db.update(_db.queueItemsTable)
            ..where((t) => t.isCurrent.equals(true)))
          .write(QueueItemsTableCompanion(positionMs: Value(positionMs)));
      return const Right(null);
    } catch (e) {
      return Left(DatabaseFailure('Failed to update queue position', e));
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
      // The v11 UNIQUE(path, cue) index is a partial/expression index and so
      // cannot be a Drift upsert target; insertAllOnConflictUpdate only
      // targets the primary key. A rescan whose MediaStore id changed for an
      // unchanged path would therefore raise UNIQUE constraint failed and
      // roll back the whole batch. Remap each incoming row onto the id already
      // owning that (path, cue) first, so the update lands on the existing row
      // and keeps its ratings/play history.
      final remappedSongs = await _remapSongsOntoExistingPaths(songs);
      await _db.transaction(() async {
        await _db.batch((batch) {
          batch.insertAllOnConflictUpdate(_db.songsTable, remappedSongs);
          batch.insertAllOnConflictUpdate(_db.albumsTable, albums);
          batch.insertAllOnConflictUpdate(_db.artistsTable, artists);
        });
      });
      // FIX: Deduplicate by file path after scan — prevents a downloaded song
      // appearing twice when the scanner inserts a new row for a path already
      // owned by a reconciled YTM row. Keep, per path, a downloaded row in
      // preference to a plain scanned row, then the lowest id so play history
      // survives. Only touched when a path genuinely has >1 local row (the
      // UNIQUE(path,cue) index makes this unreachable in normal operation, so
      // this is purely defensive against pre-index rows).
      try {
        await _db.customStatement(
          "DELETE FROM songs WHERE id NOT IN ("
          "SELECT s1.id FROM songs s1 "
          "WHERE s1.path != '' AND s1.path NOT LIKE 'ytmusic://%' AND s1.cue_start_ms IS NULL "
          "AND NOT EXISTS ("
          "SELECT 1 FROM songs s2 WHERE s2.path != '' AND s2.path NOT LIKE 'ytmusic://%' "
          "AND s2.cue_start_ms IS NULL AND lower(s2.path) = lower(s1.path) "
          "AND ((s2.is_downloaded = 1 AND s1.is_downloaded = 0) "
          "OR (s2.is_downloaded = s1.is_downloaded AND s2.id < s1.id))"
          ")) "
          "AND path != '' AND path NOT LIKE 'ytmusic://%' AND cue_start_ms IS NULL "
          "AND lower(path) IN (SELECT lower(path) FROM songs "
          "WHERE path != '' AND path NOT LIKE 'ytmusic://%' AND cue_start_ms IS NULL "
          "GROUP BY lower(path) HAVING COUNT(*) > 1);",
        );
      } catch (_) {}
      return const Right(null);
    } catch (e) {
      return Left(DatabaseFailure('Failed to sync scanned music', e));
    }
  }

  /// Rewrites incoming scanner rows so their primary key matches any existing
  /// local row that already owns the same `(lower(path), cue window)`. This
  /// turns what would be a UNIQUE(path) violation on a changed MediaStore id
  /// into a primary-key update, preserving the row id and its user data.
  Future<List<SongsTableCompanion>> _remapSongsOntoExistingPaths(
      List<SongsTableCompanion> songs) async {
    if (songs.isEmpty) return songs;
    final existing = await (_db.select(_db.songsTable)
          ..where((t) => t.source.equals(SongSource.local)))
        .get();
    if (existing.isEmpty) return songs;
    final byKey = <String, int>{};
    for (final s in existing) {
      if (s.path.isEmpty) continue;
      byKey['${s.path.toLowerCase()}\u0000${s.cueStartMs ?? -1}'] = s.id;
    }
    if (byKey.isEmpty) return songs;
    var changed = false;
    final out = <SongsTableCompanion>[];
    for (final c in songs) {
      final path = c.path.present ? c.path.value : null;
      final id = c.id.present ? c.id.value : null;
      if (path != null && path.isNotEmpty && id != null) {
        final key =
            '${path.toLowerCase()}\u0000${c.cueStartMs.present ? (c.cueStartMs.value ?? -1) : -1}';
        final existingId = byKey[key];
        if (existingId != null && existingId != id) {
          out.add(c.copyWith(id: Value(existingId)));
          changed = true;
          continue;
        }
      }
      out.add(c);
    }
    return changed ? out : songs;
  }

  /// Deterministic negative primary key for a virtual track expanded from a
  /// CUE sheet. MediaStore ids are positive, so the two id spaces cannot
  /// overlap; the same `path` + track index always maps to the same row, which
  /// keeps repeat scans idempotent (upsert, never a fresh id).
  @visibleForTesting
  static int cueVirtualSongId(String path, int trackIndex) {
    var hash = 0xcbf29ce484222325; // FNV-1a 64-bit offset basis
    for (final unit in '${path.toLowerCase()}#$trackIndex'.codeUnits) {
      hash ^= unit;
      hash *= 0x100000001b3; // Dart wraps on overflow
    }
    final magnitude = hash & 0x3FFFFFFFFFFFFFFF;
    return -(magnitude == 0 ? 1 : magnitude);
  }

  static String _siblingCuePath(String audioPath) {
    final lastDot = audioPath.lastIndexOf('.');
    if (lastDot <= 0) return '';
    return '${audioPath.substring(0, lastDot)}.cue';
  }

  /// Pure mapping: one container row + its parsed [chapters] -> virtual song
  /// companions. Carries the real file's codec/rate/depth/duration so the UI
  /// position (which is absolute inside the file) always fits the reported
  /// duration; the sub-track window lives in `cueStartMs`/`cueEndMs`. Play
  /// stats stay absent so an upsert never clobbers them.
  @visibleForTesting
  static List<SongsTableCompanion> buildCueExpansion({
    required SongsTableData container,
    required List<ChapterInfo> chapters,
    required String cuePath,
  }) {
    final companions = <SongsTableCompanion>[];
    final totalMs = container.durationMs;
    for (final chapter in chapters) {
      final startMs = chapter.start.inMilliseconds;
      // A window that reaches the end of the file is left open so natural
      // file completion advances the queue; forcing a boundary at/after EOF
      // would race the gapless completed handler into a double skip.
      final chapterEndMs = chapter.end?.inMilliseconds;
      final int? cueEndMs = (chapterEndMs != null &&
              chapterEndMs > startMs &&
              (totalMs <= 0 || chapterEndMs < totalMs))
          ? chapterEndMs
          : null;
      final id = cueVirtualSongId(container.path, chapter.index);
      companions.add(SongsTableCompanion(
        id: Value(id),
        title: Value(chapter.title),
        artist: Value(container.artist),
        artistId: Value(container.artistId),
        album: Value(container.album),
        albumId: Value(container.albumId),
        durationMs: Value(totalMs),
        path: Value(container.path),
        trackNumber: Value(chapter.index),
        discNumber: Value(container.discNumber),
        year: Value(container.year),
        dateAdded: Value(container.dateAdded),
        genre: Value(container.genre),
        fileSize: Value(container.fileSize),
        artworkUri: Value(container.artworkUri),
        sampleRate: Value(container.sampleRate),
        bitDepth: Value(container.bitDepth),
        bitrateKbps: Value(container.bitrateKbps),
        codec: Value(container.codec),
        source: const Value(SongSource.local),
        cueStartMs: Value(startMs),
        cueEndMs: Value(cueEndMs),
        cueFile: Value(cuePath),
      ));
    }
    return companions;
  }

  @override
  Future<Result<int>> expandCueSheets() async {
    try {
      final containers = await (_db.select(_db.songsTable)
            ..where((t) =>
                t.id.isBiggerThanValue(0) &
                t.source.equals(SongSource.local) &
                t.isMissing.equals(false) &
                t.path.equals('').not() &
                t.path.like('ytmusic://%').not()))
          .get();

      final companions = <SongsTableCompanion>[];
      final newIdsByPath = <String, List<int>>{};
      final coverByContainerId = <int, String>{};
      final coveredPaths = <String>{};
      var expanded = 0;

      for (final container in containers) {
        final cuePath = _siblingCuePath(container.path);
        if (cuePath.isEmpty) continue;
        final cueFile = File(cuePath);
        if (!await cueFile.exists()) continue;
        final chapters = await CueParser.findAndParseCue(container.path);
        if (chapters.isEmpty) continue;
        // Only whole-file album sheets are expanded. Multi-file sheets map
        // chapters onto several source files; expanding the wrong window on
        // this one file would fabricate playback, so skip them.
        final fileNames = chapters
            .map((c) => (c.fileName ?? '').toLowerCase())
            .where((f) => f.isNotEmpty)
            .toSet();
        if (fileNames.length > 1) continue;
        // The cue must reference this audio file, not an unrelated sibling.
        if (fileNames.isNotEmpty) {
          final referenced = fileNames.first;
          final audioName =
              container.path.replaceAll('\\', '/').split('/').last.toLowerCase();
          if (referenced != audioName) continue;
        }
        final virtual = buildCueExpansion(
          container: container,
          chapters: chapters,
          cuePath: cuePath,
        );
        if (virtual.isEmpty) continue;
        companions.addAll(virtual);
        newIdsByPath[container.path] =
            virtual.map((c) => c.id.value).toList();
        coverByContainerId[container.id] = cuePath;
        coveredPaths.add(container.path);
        expanded += virtual.length;
      }

      await _db.transaction(() async {
        if (companions.isNotEmpty) {
          await _db.batch((batch) {
            batch.insertAllOnConflictUpdate(_db.songsTable, companions);
          });
        }
        for (final entry in coverByContainerId.entries) {
          await (_db.update(_db.songsTable)
                ..where((t) => t.id.equals(entry.key)))
              .write(SongsTableCompanion(cueFile: Value(entry.value)));
        }
        // Clear the marker on containers whose cue disappeared so they return
        // to the normal library instead of being hidden forever.
        final markers = await (_db.select(_db.songsTable)
              ..where((t) =>
                  t.cueFile.isNotNull() &
                  t.cueStartMs.isNull() &
                  t.id.isBiggerThanValue(0)))
            .get();
        for (final marker in markers) {
          if (coveredPaths.contains(marker.path)) continue;
          await (_db.update(_db.songsTable)
                ..where((t) => t.id.equals(marker.id)))
              .write(const SongsTableCompanion(cueFile: Value(null)));
        }
        // Drop virtual rows that no longer belong to a live expansion.
        final virtualRows = await (_db.select(_db.songsTable)
              ..where((t) => t.cueStartMs.isNotNull()))
            .get();
        for (final row in virtualRows) {
          final keep = newIdsByPath[row.path];
          if (keep != null && keep.contains(row.id)) continue;
          await (_db.delete(_db.songsTable)..where((t) => t.id.equals(row.id)))
              .go();
        }
      });

      // Keep album/artist counts in step with the virtual tracks now that the
      // container rows are hidden from listings.
      await _db.customStatement(
        "UPDATE albums SET song_count = (SELECT COUNT(*) FROM songs WHERE songs.album_id = albums.id AND songs.is_missing = 0 AND songs.source = '${SongSource.local}' AND songs.path NOT LIKE 'ytmusic://%' AND (songs.cue_file IS NULL OR songs.cue_start_ms IS NOT NULL));",
      );
      await _db.customStatement(
        "UPDATE artists SET song_count = (SELECT COUNT(*) FROM songs WHERE songs.artist_id = artists.id AND songs.is_missing = 0 AND songs.source = '${SongSource.local}' AND songs.path NOT LIKE 'ytmusic://%' AND (songs.cue_file IS NULL OR songs.cue_start_ms IS NOT NULL));",
      );

      return Right(expanded);
    } catch (e) {
      return Left(DatabaseFailure('Failed to expand cue sheets', e));
    }
  }

  @override
  Future<Result<int>> cleanupOrphanedSongs(Set<int> scannedSongIds) async {
    try {
      // NEVER delete or mark missing on an empty scan result (protect against unmounted SD cards, OS indexing, permission drops)
      if (scannedSongIds.isEmpty) {
        return const Right(0);
      }

      // 1. Fetch all local songs and compute unscanned in Dart memory to avoid SQLite variable limits
      final allLocalSongs = await (_db.select(_db.songsTable)
            ..where((t) =>
                t.id.isBiggerThanValue(0) &
                t.source.equals(SongSource.local)))
          .get();
      final unscannedSongs = allLocalSongs
          .where((s) => !scannedSongIds.contains(s.id))
          .toList();

      // 2. Bounded async disk checks without blocking the UI isolate or DB
      // locks: 64-wide concurrency with a cooperative yield between chunks
      // so a 10k SD-card library can't freeze scrolling while orphan
      // cleanup runs. Each check is individually error-isolated — one
      // unreadable file must not abort the whole sweep.
      final trulyMissingIds = <int>[];
      final reappearedIds = <int>[];
      const chunkSize = 64;

      for (var i = 0; i < unscannedSongs.length; i += chunkSize) {
        final end = (i + chunkSize < unscannedSongs.length)
            ? i + chunkSize
            : unscannedSongs.length;
        final chunk = unscannedSongs.sublist(i, end);
        await Future.wait(chunk.map((song) async {
          try {
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
          } catch (_) {
            // Treat unreadable as missing (marks row, never deletes).
            trulyMissingIds.add(song.id);
          }
        }));
        // Yield to the event loop so UI frames interleave with SD I/O.
        await Future<void>.delayed(Duration.zero);
      }

      // Re-verify the small truly-missing set right before the write: a
      // file reappearing in the scan→check→write gap would otherwise be
      // marked missing until the next scan. content: URIs skip disk I/O.
      final reverifiedMissing = <int>[];
      final reverifiedReappeared = <int>[];
      for (final id in trulyMissingIds) {
        final song = unscannedSongs.firstWhere((s) => s.id == id);
        if (song.path.isEmpty || song.path.startsWith('content:')) {
          reverifiedMissing.add(id);
          continue;
        }
        try {
          if (await File(song.path).exists()) {
            reverifiedReappeared.add(id);
          } else {
            reverifiedMissing.add(id);
          }
        } catch (_) {
          reverifiedMissing.add(id);
        }
      }
      trulyMissingIds
        ..clear()
        ..addAll(reverifiedMissing);
      reappearedIds.addAll(reverifiedReappeared);

      // P0-6: Use Drift batch for atomic single-transaction execution
      const updateChunkSize = 400;
      await _db.batch((batch) {
        if (trulyMissingIds.isNotEmpty) {
          for (var i = 0; i < trulyMissingIds.length; i += updateChunkSize) {
            final end = (i + updateChunkSize < trulyMissingIds.length)
                ? i + updateChunkSize
                : trulyMissingIds.length;
            final chunk = trulyMissingIds.sublist(i, end);
            batch.update(
              _db.songsTable,
              const SongsTableCompanion(isMissing: Value(true)),
              where: (t) => t.id.isIn(chunk),
            );
          }
        }

        // Ensure newly/currently scanned songs and reappeared songs are marked active (not missing)
        final activeIds = [...scannedSongIds, ...reappearedIds];
        if (activeIds.isNotEmpty) {
          for (var i = 0; i < activeIds.length; i += updateChunkSize) {
            final end = (i + updateChunkSize < activeIds.length)
                ? i + updateChunkSize
                : activeIds.length;
            final chunk = activeIds.sublist(i, end);
            batch.update(
              _db.songsTable,
              const SongsTableCompanion(isMissing: Value(false)),
              where: (t) => t.id.isIn(chunk),
            );
          }
        }
      });

      final markedMissingCount = trulyMissingIds.length;

      // Recalculate song counts using active (non-missing) local songs
      final albumCounts = await (_db.selectOnly(_db.songsTable)
            ..addColumns([_db.songsTable.albumId, _db.songsTable.id.count()])
            ..where(_db.songsTable.albumId.isNotNull() &
                _db.songsTable.isMissing.equals(false) &
                _db.songsTable.source.equals(SongSource.local) &
                _db.songsTable.path.like('ytmusic://%').not() &
                (_db.songsTable.cueFile.isNull() |
                    _db.songsTable.cueStartMs.isNotNull()))
            ..groupBy([_db.songsTable.albumId]))
          .get();

        final artistCounts = await (_db.selectOnly(_db.songsTable)
              ..addColumns([_db.songsTable.artistId, _db.songsTable.id.count()])
              ..where(_db.songsTable.artistId.isNotNull() &
                  _db.songsTable.isMissing.equals(false) &
                  _db.songsTable.source.equals(SongSource.local) &
                  _db.songsTable.path.like('ytmusic://%').not() &
                  (_db.songsTable.cueFile.isNull() |
                      _db.songsTable.cueStartMs.isNotNull()))
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

      // Albums/artists whose every song became missing are not updated by the
      // group-by above (they have no active rows), so prune them here to match
      // hardDeleteMissingSongs and avoid stale entries in watchAlbums.
      await _db.customStatement(
        'DELETE FROM albums WHERE NOT EXISTS (SELECT 1 FROM songs WHERE songs.album_id = albums.id AND songs.is_missing = 0);',
      );
      await _db.customStatement(
        'DELETE FROM artists WHERE NOT EXISTS (SELECT 1 FROM songs WHERE songs.artist_id = artists.id AND songs.is_missing = 0);',
      );

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
  Future<Result<void>> deleteSongs(List<int> ids) async {
    final res = await deleteSongsWithReport(ids);
    return res.fold(Left.new, (_) => const Right(null));
  }

  @override
  Future<Result<List<int>>> deleteSongsWithReport(List<int> ids) async {
    if (ids.isEmpty) return const Right([]);
    try {
      // Chunk large id lists: a "select all" delete over a 10k library would
      // otherwise exceed SQLite's bound-variable limit. The DB portion is one
      // transaction so counts/memberships cannot be left half-applied.
      const chunkSize = 400;
      final songs = <SongsTableData>[];
      final affectedPlaylistIds = <int>{};
      await _db.transaction(() async {
        for (var i = 0; i < ids.length; i += chunkSize) {
          final chunk = ids.sublist(i, min(i + chunkSize, ids.length));
          songs.addAll(await (_db.select(_db.songsTable)
                ..where((t) => t.id.isIn(chunk)))
              .get());
          // Snapshot affected playlists BEFORE the FK cascade wipes membership.
          final playlistIds = await (_db.selectOnly(
                  _db.playlistEntriesTable,
                  distinct: true)
                ..where(_db.playlistEntriesTable.songId.isIn(chunk))
                ..addColumns([_db.playlistEntriesTable.playlistId]))
              .map((r) => r.read(_db.playlistEntriesTable.playlistId))
              .get();
          affectedPlaylistIds.addAll(playlistIds.whereType<int>());
        }
        for (var i = 0; i < ids.length; i += chunkSize) {
          final chunk = ids.sublist(i, min(i + chunkSize, ids.length));
          await (_db.delete(_db.songsTable)..where((t) => t.id.isIn(chunk)))
              .go();
        }
        await _db.customStatement(
          'DELETE FROM albums WHERE NOT EXISTS (SELECT 1 FROM songs WHERE songs.album_id = albums.id AND songs.is_missing = 0);',
        );
        await _db.customStatement(
          'DELETE FROM artists WHERE NOT EXISTS (SELECT 1 FROM songs WHERE songs.artist_id = artists.id AND songs.is_missing = 0);',
        );
        await _db.customStatement(
          'UPDATE albums SET song_count = (SELECT COUNT(*) FROM songs WHERE songs.album_id = albums.id AND songs.is_missing = 0);',
        );
        await _db.customStatement(
          'UPDATE artists SET song_count = (SELECT COUNT(*) FROM songs WHERE songs.artist_id = artists.id AND songs.is_missing = 0);',
        );
      });

      for (final song in songs) {
        if (song.source != SongSource.local) continue;
        if (song.cueStartMs != null) continue;
        final path = song.path;
        if (path.isEmpty || path.startsWith('ytmusic://')) continue;
        try {
          final file = File(path);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (e, st) {
          ErrorLogger.log('Failed to delete file for song ${song.id}',
              error: e, stackTrace: st, category: 'MusicRepository');
        }
      }

      if (affectedPlaylistIds.isNotEmpty) {
        ErrorLogger.log(
            'deleteSongs cascaded ${ids.length} song(s) out of ${affectedPlaylistIds.length} playlist(s): $affectedPlaylistIds',
            category: 'MusicRepository');
      }
      return Right(affectedPlaylistIds.toList());
    } catch (e) {
      return Left(DatabaseFailure('Failed to delete songs', e));
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
        final oldData = oldRow;
        final newData = newRow;

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
            // Carry the video id and online remoteArtworkUrl
            remoteId: Value(oldData.remoteId ?? newData.remoteId),
            remoteArtworkUrl: Value(effectiveRemoteArt),
            source: const Value(SongSource.local),
            isDownloaded: const Value(true),
            pendingDownloadPath: const Value(null),
          ),
        );

        // FIX: Remove any other duplicate path rows that the scanner may have inserted in parallel
        // This guarantees a single entry per file path after download, fixing "repeats twice on local"
        final newRowPath = newData.path;
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
            ..where((t) =>
                t.path.equals(path) &
                t.source.equals(SongSource.local) &
                t.cueStartMs.isNull()))
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
      final song = await (_db.select(_db.songsTable)
            ..where((t) => t.id.equals(songId)))
          .getSingleOrNull();
      // A CUE image's virtual tracks all share the container's path, so push
      // the header fields to every row backed by the same file.
      final target = song != null && song.path.isNotEmpty
          ? (_db.update(_db.songsTable)..where((t) => t.path.equals(song.path)))
          : (_db.update(_db.songsTable)..where((t) => t.id.equals(songId)));
      await target.write(
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
            _db.songsTable.path.like('ytmusic://%').not() &
            (_db.songsTable.cueFile.isNull() |
                _db.songsTable.cueStartMs.isNotNull()))
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
            _db.songsTable.path.like('ytmusic://%').not() &
            (_db.songsTable.cueFile.isNull() |
                _db.songsTable.cueStartMs.isNotNull()))
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
                t.path.like('ytmusic://%').not() &
                (t.cueFile.isNull() | t.cueStartMs.isNotNull()))
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
                t.path.like('ytmusic://%').not() &
                (t.cueFile.isNull() | t.cueStartMs.isNotNull()))
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
            _db.songsTable.path.like('ytmusic://%').not() &
            (_db.songsTable.cueFile.isNull() |
                _db.songsTable.cueStartMs.isNotNull()))
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
                t.path.like('ytmusic://%').not() &
                (t.cueFile.isNull() | t.cueStartMs.isNotNull()))
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

String _normalizeDirPath(String path) =>
    path.replaceAll('\\', '/').toLowerCase().trim();

String _parentDirPath(String path) {
  final slash = path.lastIndexOf('/');
  final backslash = path.lastIndexOf('\\');
  final i = slash > backslash ? slash : backslash;
  return i <= 0 ? path : path.substring(0, i);
}