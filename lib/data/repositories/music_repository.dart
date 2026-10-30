// lib/data/repositories/music_repository.dart
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';
import 'package:rxdart/rxdart.dart';
import '../../core/constants/audio_formats.dart';
import '../../core/constants/channels.dart';
import '../../core/errors/failures.dart';
import '../../core/utils/cue_parser.dart';
import '../../core/utils/error_logger.dart';
import '../../core/utils/local_delete_guard.dart';
import '../../core/utils/metadata_placeholders.dart';
import '../../domain/models/chapter_info.dart';
import '../../domain/models/genre_item.dart';
import '../../domain/models/year_item.dart';
import '../../domain/models/ytm_track.dart';
import '../../domain/repositories/music_repository_interface.dart';
import '../../core/utils/input_sanitizer.dart';
import '../db/app_database.dart';
import '../services/library_maintenance_service.dart';

/// Emits an error value from a watched-result stream. `Stream.handleError`
/// discards its callback's return value, which silently swallowed every
/// database failure in these watch queries.
///
/// Implemented with a controller instead of `transform`: the upstream stream's
/// runtime type is `Stream<Right<...>>`, and Dart reifies `transform`'s type
/// argument, so an `Either` transformer is rejected at runtime even though the
/// widened static type accepts it.
extension ResultStreamRecovery<A, B> on Stream<Either<A, B>> {
  Stream<Either<A, B>> onResultError(
      Either<A, B> Function(Object error, StackTrace stackTrace) mapper) {
    late final StreamController<Either<A, B>> controller;
    StreamSubscription<Either<A, B>>? subscription;
    void start() {
      subscription = listen(
        controller.add,
        onError: (Object error, StackTrace stackTrace) =>
            controller.add(mapper(error, stackTrace)),
        onDone: controller.close,
        cancelOnError: false,
      );
    }

    Future<void> stop() async {
      await subscription?.cancel();
      subscription = null;
    }

    controller = isBroadcast
        ? StreamController<Either<A, B>>.broadcast(
            onListen: start,
            onCancel: stop,
          )
        : StreamController<Either<A, B>>(
            onListen: start,
            onPause: () => subscription?.pause(),
            onResume: () => subscription?.resume(),
            onCancel: stop,
          );
    return controller.stream;
  }
}

@Singleton(as: IMusicRepository)
class MusicRepository implements IMusicRepository {
  final AppDatabase _db;

  MusicRepository(this._db);

  /// Escapes LIKE metacharacters (%, _, \) so user input and folder paths
  /// match literally. Use with `escapeChar: r'\'`.
  static String _likeEscape(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');

  /// Central hidden-folder predicate used by every discovery query (recently
  /// played/added, top played, genres, years, stats and duplicate scans).
  ///
  /// A folder path is prefix-matched with a trailing separator so excluding
  /// `/music/A` never also hides `/music/AB`. The predicate is a no-op when no
  /// folders are excluded.
  Expression<bool> _notInExcludedFolders(List<String> excludedFolders) {
    Expression<bool> predicate = const Constant(true);
    for (final raw in excludedFolders) {
      final base = raw.replaceAll(RegExp(r'[\\/]+$'), '').trim();
      if (base.isEmpty) continue;
      // Paths on Android use '/', while desktop libraries may use '\'. Apply
      // both prefixes so exclusions behave identically in tests and on device.
      final slashPrefix = _likeEscape('$base/');
      final backslashPrefix = _likeEscape('$base\\');
      predicate = predicate &
          _db.songsTable.path.like('$slashPrefix%', escapeChar: r'\').not() &
          _db.songsTable.path.like('$backslashPrefix%', escapeChar: r'\').not();
    }
    return predicate;
  }

  void _applyExcludedFolders(
    SimpleSelectStatement<$SongsTableTable, SongsTableData> query,
    List<String> excludedFolders,
  ) {
    if (excludedFolders.isEmpty) return;
    query.where((_) => _notInExcludedFolders(excludedFolders));
  }

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
        final trimmed = searchQuery.trim();
        final useTrigram = shouldUseTrigram(trimmed);
        final ftsQuery =
            useTrigram ? toTrigramFtsQuery(trimmed) : _toFtsQuery(trimmed);

        if (ftsQuery != null && !AppDatabase.ftsRebuildFailed) {
          return _watchSongsFts(
            ftsQuery: ftsQuery,
            sortBy: sortBy,
            ascending: ascending,
            limit: limit ?? 200,
            offset: offset,
            excludedFolders: excludedFolders,
            useTrigram: useTrigram,
          );
        }

        // Fallback when FTS tokenization yields no tokens or FTS failed:
        // Bound the scan (limit to 200 max unless caller provided explicit bound).
        final escaped = _likeEscape(trimmed);
        if (trimmed.length >= 3) {
          final prefixPattern = '$escaped%';
          final containsPattern = '%$escaped%';
          // Prefer prefix search on title (index-friendly idx_songs_title), falling back to contains
          query.where((t) =>
              t.title.like(prefixPattern, escapeChar: r'\') |
              t.title.like(containsPattern, escapeChar: r'\') |
              t.artist.like(containsPattern, escapeChar: r'\') |
              t.album.like(containsPattern, escapeChar: r'\'));
        } else {
          final containsPattern = '%$escaped%';
          query.where((t) =>
              t.title.like(containsPattern, escapeChar: r'\') |
              t.artist.like(containsPattern, escapeChar: r'\') |
              t.album.like(containsPattern, escapeChar: r'\'));
        }
      }

      if (excludedFolders.isNotEmpty) {
        _applyExcludedFolders(query, excludedFolders);
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
      } else if (sortBy == 'sampleRate') {
        query.orderBy([
          (t) => OrderingTerm(
              expression: t.sampleRate,
              mode: ascending ? OrderingMode.asc : OrderingMode.desc)
        ]);
      } else {
        // FIX B4: unrecognized sortBy must still yield deterministic ordering;
        // an unordered query breaks stable pagination for callers.
        query.orderBy([
          (t) => OrderingTerm(
              expression: t.title,
              mode: ascending ? OrderingMode.asc : OrderingMode.desc)
        ]);
      }

      final effectiveLimit = limit ??
          (searchQuery != null && searchQuery.trim().isNotEmpty ? 200 : null);
      if (effectiveLimit != null) {
        query.limit(effectiveLimit, offset: offset);
      }

      return query
          .watch()
          .map<Either<AppFailure, List<SongsTableData>>>(
              (songs) => Right<AppFailure, List<SongsTableData>>(songs))
          // Stream.handleError DISCARDS the callback's return value; use the
          // RxDart operator that actually emits the mapped error value.
          .onErrorReturnWith((e, st) => Left<AppFailure, List<SongsTableData>>(
              DatabaseFailure('Failed to watch songs', e)));
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

  /// Detects if a query contains CJK characters or is a short substring query
  /// that benefits from the trigram index rather than unicode61 prefix matching.
  static bool shouldUseTrigram(String query) {
    if (!AppDatabase.ftsTrigramSupported) return false;
    final trimmed = query.trim();
    if (trimmed.isEmpty) return false;
    // FTS5 trigram MATCH cannot resolve a query shorter than one trigram;
    // those must fall back to the unicode61 prefix query (or LIKE).
    if (trimmed.length < 3) return false;
    // Check for CJK Ideographs / Hiragana / Katakana / Hangul
    final hasCjk =
        RegExp(r'[\u4E00-\u9FFF\u3040-\u309F\u30A0-\u30FF\uAC00-\uD7AF]')
            .hasMatch(trimmed);
    if (hasCjk) return true;
    return trimmed.length == 3;
  }

  /// Formats query for FTS5 trigram virtual table.
  static String? toTrigramFtsQuery(String input) {
    final clean = input.replaceAll('"', '""').trim();
    if (clean.isEmpty) return null;
    return '"$clean"';
  }

  Stream<Result<List<SongsTableData>>> _watchSongsFts({
    required String ftsQuery,
    required String sortBy,
    required bool ascending,
    required int limit,
    int? offset,
    List<String> excludedFolders = const [],
    bool useTrigram = false,
  }) {
    try {
      final ftsTable = (useTrigram && AppDatabase.ftsTrigramSupported)
          ? 'songs_fts_trigram'
          : 'songs_fts';
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
        'sampleRate' => 's.sample_rate',
        'year' => 's.year',
        _ => 's.title COLLATE NOCASE',
      };
      final dir = ascending ? 'ASC' : 'DESC';
      final buffer = StringBuffer(
        'SELECT s.* FROM songs s '
        'JOIN $ftsTable f ON s.id = f.rowid '
        'WHERE $ftsTable MATCH ? AND s.is_missing = 0 '
        'AND s.source = ? '
        "AND s.path NOT LIKE 'ytmusic://%' "
        'AND (s.cue_file IS NULL OR s.cue_start_ms IS NOT NULL) ',
      );
      final vars = <Variable>[
        Variable.withString(ftsQuery),
        Variable.withString(SongSource.local),
      ];
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
              variables: vars, readsFrom: {_db.songsTable})
          .watch()
          .asyncMap<Either<AppFailure, List<SongsTableData>>>((rows) async {
            final songs = await Future.wait(
                rows.map((r) => _db.songsTable.mapFromRow(r)));
            return Right<AppFailure, List<SongsTableData>>(songs);
          })
          .onErrorReturnWith((e, st) {
            // Missing/corrupt FTS (failed migration rebuild or a damaged
            // index): attempt a bounded repair, then report. The next watch
            // re-subscribes onto the rebuilt index. repairFtsIndex caps its
            // own attempts per session, so this cannot loop.
            AppDatabase.ftsRebuildFailed = true;
            unawaited(_db.repairFtsIndex());
            return Left<AppFailure, List<SongsTableData>>(
                DatabaseFailure('Failed to watch songs (FTS)', e));
          });
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
    List<String> excludedFolders = const [],
  }) async {
    try {
      final query = _db.select(_db.songsTable)
        ..where((t) =>
            t.isMissing.equals(false) &
            t.source.equals(SongSource.local) &
            t.path.like('ytmusic://%').not() &
            (t.cueFile.isNull() | t.cueStartMs.isNotNull()));
      _applyExcludedFolders(query, excludedFolders);
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
      } else if (sortBy == 'sampleRate') {
        query.orderBy([
          (t) => OrderingTerm(
              expression: t.sampleRate,
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
  Future<Result<List<FolderSongEntry>>> getLocalSongEntries() async {
    try {
      final query = _db.selectOnly(_db.songsTable)
        ..addColumns([
          _db.songsTable.id,
          _db.songsTable.albumId,
          _db.songsTable.path,
          _db.songsTable.artworkUri,
          _db.songsTable.remoteArtworkUrl,
        ])
        ..where(_db.songsTable.isMissing.equals(false) &
            _db.songsTable.source.equals(SongSource.local) &
            _db.songsTable.path.like('ytmusic://%').not() &
            _db.songsTable.cueStartMs.isNull());
      final rows = await query.get();
      final entries = rows
          .map((r) {
            final path = r.read(_db.songsTable.path);
            final id = r.read(_db.songsTable.id);
            if (path == null || id == null) return null;
            return FolderSongEntry(
              path: path,
              id: id,
              albumId: r.read(_db.songsTable.albumId),
              artworkUri: r.read(_db.songsTable.artworkUri),
              remoteArtworkUrl: r.read(_db.songsTable.remoteArtworkUrl),
            );
          })
          .whereType<FolderSongEntry>()
          .toList();
      return Right(entries);
    } catch (e) {
      return Left(DatabaseFailure('Failed to fetch folder song entries', e));
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
      final slashPrefix = target.endsWith('/') ? target : '$target/';
      final backPrefix = slashPrefix.replaceAll('/', r'\');
      final query = _db.select(_db.songsTable)
        ..where((t) =>
            t.isMissing.equals(false) &
            t.source.equals(SongSource.local) &
            (t.path.like('${_likeEscape(slashPrefix)}%', escapeChar: r'\') |
                t.path.like('${_likeEscape(backPrefix)}%', escapeChar: r'\') |
                t.path.like('${_likeEscape(target)}%', escapeChar: r'\')) &
            (t.cueFile.isNull() | t.cueStartMs.isNotNull()));
      return query.watch().map((songs) {
        final filtered = songs
            .where((s) => _normalizeDirPath(_parentDirPath(s.path)) == target)
            .toList();
        return Right<AppFailure, List<SongsTableData>>(filtered);
      }).onResultError((error, stackTrace) =>
          Left<AppFailure, List<SongsTableData>>(
              DatabaseFailure('Failed to watch folder songs', error)));
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
            ..where((t) => t.path.lower().equals(path.toLowerCase()))
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

  /// All downloaded rows, independent of the paginated 500-row library window.
  ///
  /// Candidates are rows flagged [SongsTable.isDownloaded] or legacy local
  /// rows that kept a YouTube [SongsTable.remoteId]. The caller still applies
  /// the shared `isDownloadedOnlineTrack` classifier, so the two definitions
  /// cannot drift.
  @override
  Stream<Result<List<SongsTableData>>> watchDownloadedSongs({
    List<String> excludedFolders = const [],
  }) {
    try {
      final query = _db.select(_db.songsTable)
        ..where((t) =>
            t.isMissing.equals(false) &
            t.path.equals('').not() &
            t.path.like('ytmusic://%').not() &
            (t.isDownloaded.equals(true) |
                (t.source.equals(SongSource.local) &
                    t.remoteId.isNotNull() &
                    t.remoteId.equals('').not())))
        ..orderBy([
          (t) => OrderingTerm(expression: t.title),
          (t) => OrderingTerm(expression: t.id),
        ]);
      _applyExcludedFolders(query, excludedFolders);
      return query
          .watch()
          .map((songs) => Right<AppFailure, List<SongsTableData>>(songs))
          .onResultError((e, st) => Left<AppFailure, List<SongsTableData>>(
              DatabaseFailure('Failed to watch downloaded songs', e)));
    } catch (e) {
      return Stream.value(
          Left(DatabaseFailure('Failed to watch downloaded songs', e)));
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
          .onResultError((e, st) => Left<AppFailure, List<SongsTableData>>(
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
    if (tracks.isEmpty) return const Right(0);
    try {
      // Single transaction: atomic import (no partial state on failure) and
      // batched SELECT / UPDATE / INSERT statements instead of 2N round-trips.
      final count = await _db.transaction(() async {
        const chunkSize = 400;
        final existingByRemoteId = <String, int>{};
        final videoIds = tracks
            .map((t) => t.videoId)
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList(growable: false);
        for (var i = 0; i < videoIds.length; i += chunkSize) {
          final chunk =
              videoIds.sublist(i, (i + chunkSize).clamp(0, videoIds.length));
          final rows = await (_db.select(_db.songsTable)
                ..where((t) => t.remoteId.isIn(chunk)))
              .get();
          for (final row in rows) {
            final rId = row.remoteId;
            if (rId != null) {
              existingByRemoteId.putIfAbsent(rId, () => row.id);
            }
          }
        }

        final takenIds = <int>{...existingByRemoteId.values};
        final songDataList =
            tracks.map((t) => t.toSongData()).toList(growable: false);
        final preferredIds =
            songDataList.map((s) => s.id).toSet().toList(growable: false);
        for (var i = 0; i < preferredIds.length; i += chunkSize) {
          final chunk = preferredIds.sublist(
              i, (i + chunkSize).clamp(0, preferredIds.length));
          final rows = await (_db.selectOnly(_db.songsTable)
                ..addColumns([_db.songsTable.id])
                ..where(_db.songsTable.id.isIn(chunk)))
              .get();
          for (final row in rows) {
            final id = row.read(_db.songsTable.id);
            if (id != null) takenIds.add(id);
          }
        }

        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final idsToMarkFavorite = <int>{};
        final toInsert = <SongsTableCompanion>[];
        var n = 0;

        for (var i = 0; i < tracks.length; i++) {
          final track = tracks[i];
          final songData = songDataList[i];
          final existingId = existingByRemoteId[track.videoId];

          if (existingId != null) {
            idsToMarkFavorite.add(existingId);
            n++;
          } else {
            // The deterministic negative id is only 62 bits of the video hash,
            // so a collision with an unrelated row (a local file, a CUE virtual
            // track, or another video) is possible. Never clobber it: allocate
            // the next free id in the online id space instead.
            final int id;
            if (!takenIds.contains(songData.id)) {
              id = songData.id;
              takenIds.add(id);
            } else {
              id = await _resolveFreeSongId(songData.id, takenIds: takenIds);
              takenIds.add(id);
            }
            existingByRemoteId[track.videoId] = id;
            toInsert.add(
              SongsTableCompanion(
                id: Value(id),
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
                dateAdded: Value(nowMs),
              ),
            );
            n++;
          }
        }

        if (idsToMarkFavorite.isNotEmpty) {
          final favList = idsToMarkFavorite.toList(growable: false);
          for (var i = 0; i < favList.length; i += chunkSize) {
            final chunk =
                favList.sublist(i, (i + chunkSize).clamp(0, favList.length));
            await (_db.update(_db.songsTable)..where((t) => t.id.isIn(chunk)))
                .write(const SongsTableCompanion(
              isFavorite: Value(true),
              isMissing: Value(false),
            ));
          }
        }

        if (toInsert.isNotEmpty) {
          await _db.batch((b) {
            b.insertAll(
              _db.songsTable,
              toInsert,
              mode: InsertMode.insertOrReplace,
            );
          });
        }

        return n;
      });
      return Right(count);
    } catch (e) {
      return Left(
          DatabaseFailure('Failed to import online tracks as favorites', e));
    }
  }

  /// Returns [preferred] when no row owns that id, otherwise walks the online
  /// (negative) id space in batched blocks until a free slot is found. Keeps
  /// the deterministic id for the common case while guaranteeing an insert
  /// never overwrites an unrelated song on a hash collision. Must be called
  /// inside the import transaction so earlier inserts in the same batch are
  /// visible.
  Future<int> _resolveFreeSongId(int preferred, {Set<int>? takenIds}) async {
    const blockSize = 64;
    final step = preferred < 0 ? -1 : 1;
    final base = preferred;
    for (var offset = 0; offset < 4096; offset += blockSize) {
      final candidates = <int>[];
      for (var j = 0; j < blockSize && (offset + j) < 4096; j++) {
        final c = base + (offset + j) * step;
        if (takenIds == null || !takenIds.contains(c)) {
          candidates.add(c);
        }
      }
      if (candidates.isEmpty) continue;
      final rows = await (_db.selectOnly(_db.songsTable)
            ..addColumns([_db.songsTable.id])
            ..where(_db.songsTable.id.isIn(candidates)))
          .get();
      final dbTaken = <int>{
        for (final r in rows)
          if (r.read(_db.songsTable.id) != null) r.read(_db.songsTable.id)!,
      };
      if (takenIds != null) takenIds.addAll(dbTaken);
      for (final c in candidates) {
        if (!dbTaken.contains(c)) return c;
      }
    }
    // Pathological fallback: a time-derived magnitude cannot equal a
    // video-hash id in practice, and still lives in the negative id space.
    var fallback =
        -(DateTime.now().microsecondsSinceEpoch & 0x3FFFFFFFFFFFFFFF);
    while (takenIds != null && takenIds.contains(fallback)) {
      fallback -= 1;
    }
    return fallback;
  }

  @override
  Future<Result<int>> ensureSongPersisted(SongsTableData song) async {
    try {
      final resolvedId = await _db.transaction<int?>(() async {
        final byId = await (_db.select(_db.songsTable)
              ..where((t) => t.id.equals(song.id))
              ..limit(1))
            .getSingleOrNull();
        if (byId != null) return byId.id;

        // A downloaded track keeps its remote id on the scanned local row, so
        // prefer that over inserting a second sentinel row for the same video.
        final remoteId = song.remoteId;
        if (remoteId != null && remoteId.isNotEmpty) {
          final byRemoteId = await (_db.select(_db.songsTable)
                ..where((t) =>
                    t.remoteId.equals(remoteId) & t.isMissing.equals(false))
                ..orderBy([
                  (t) => OrderingTerm(
                      expression: t.dateAdded, mode: OrderingMode.desc)
                ])
                ..limit(1))
              .getSingleOrNull();
          if (byRemoteId != null) return byRemoteId.id;
        }

        final isOnline = song.source == SongSource.youtube ||
            song.path.startsWith('ytmusic://');
        if (!isOnline) {
          // Stale local object (e.g. a rescan replaced its row): find the
          // current row instead of failing the playlist write.
          if (song.path.isNotEmpty) {
            final byPath = await (_db.select(_db.songsTable)
                  ..where((t) =>
                      t.path.lower().equals(song.path.toLowerCase()) &
                      (song.cueStartMs == null
                          ? t.cueStartMs.isNull()
                          : t.cueStartMs.equals(song.cueStartMs!)))
                  ..limit(1))
                .getSingleOrNull();
            if (byPath != null) return byPath.id;
          }
          return null;
        }

        // YouTube search results exist only in memory until something (favorite,
        // download, playlist) persists them. playlist_entries.song_id is an FK,
        // so the row must exist before the membership insert.
        final id = await _resolveFreeSongId(song.id);
        await _db.into(_db.songsTable).insert(
              SongsTableCompanion(
                id: Value(id),
                title: Value(song.title),
                artist: Value(song.artist),
                album: Value(song.album),
                durationMs: Value(song.durationMs),
                path: Value(song.path),
                source: const Value(SongSource.youtube),
                remoteId: Value(remoteId),
                remoteArtworkUrl: Value(song.remoteArtworkUrl),
                isFavorite: const Value(false),
                isMissing: const Value(false),
                dateAdded: Value(DateTime.now().millisecondsSinceEpoch),
              ),
              mode: InsertMode.insertOrIgnore,
            );
        return id;
      });
      if (resolvedId == null) {
        return const Left(
            DatabaseFailure('This song is no longer in your library'));
      }
      return Right(resolvedId);
    } catch (e) {
      return Left(DatabaseFailure('Failed to add song to playlist', e));
    }
  }

  @override
  Stream<Result<List<SongsTableData>>> watchRecentlyPlayed({
    int limit = 20,
    List<String> excludedFolders = const [],
  }) {
    try {
      final query = _db.select(_db.songsTable)
        ..where((t) =>
            t.lastPlayed.isNotNull() &
            t.isMissing.equals(false) &
            t.source.equals(SongSource.local) &
            t.path.like('ytmusic://%').not() &
            (t.cueFile.isNull() | t.cueStartMs.isNotNull()))
        ..orderBy([
          (t) =>
              OrderingTerm(expression: t.lastPlayed, mode: OrderingMode.desc),
          // Deterministic tie-breaker so the stream and the one-shot
          // [getRecentlyPlayed] snapshot agree on the order.
          (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
        ])
        ..limit(limit);
      _applyExcludedFolders(query, excludedFolders);
      return query
          .watch()
          .map((songs) => Right<AppFailure, List<SongsTableData>>(songs))
          .onResultError((e, st) => Left<AppFailure, List<SongsTableData>>(
              DatabaseFailure('Failed to watch recently played', e)));
    } catch (e) {
      return Stream.value(
          Left(DatabaseFailure('Failed to watch recently played', e)));
    }
  }

  @override
  Future<Result<List<SongsTableData>>> getRecentlyPlayed({
    int limit = 20,
    List<String> excludedFolders = const [],
  }) async {
    try {
      final query = _db.select(_db.songsTable)
        ..where((t) =>
            t.lastPlayed.isNotNull() &
            t.isMissing.equals(false) &
            t.source.equals(SongSource.local) &
            t.path.like('ytmusic://%').not() &
            (t.cueFile.isNull() | t.cueStartMs.isNotNull()))
        ..orderBy([
          (t) =>
              OrderingTerm(expression: t.lastPlayed, mode: OrderingMode.desc),
          // Must stay in sync with [watchRecentlyPlayed] so a queue built
          // from this one-shot snapshot matches the displayed order.
          (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
        ])
        ..limit(limit);
      _applyExcludedFolders(query, excludedFolders);
      final songs = await query.get();
      return Right(songs);
    } catch (e) {
      return Left(DatabaseFailure('Failed to fetch recently played songs', e));
    }
  }

  @override
  Future<Result<void>> clearRecentlyPlayed() async {
    try {
      await (_db.update(_db.songsTable)..where((t) => t.lastPlayed.isNotNull()))
          .write(const SongsTableCompanion(lastPlayed: Value(null)));
      return const Right(null);
    } catch (e) {
      return Left(
          DatabaseFailure('Failed to clear recently played history', e));
    }
  }

  @override
  Stream<Result<List<SongsTableData>>> watchRecentlyAdded({
    int? limit = 20,
    List<String> excludedFolders = const [],
  }) {
    try {
      final query = _db.select(_db.songsTable)
        ..where((t) =>
            t.isMissing.equals(false) &
            t.source.equals(SongSource.local) &
            t.path.like('ytmusic://%').not() &
            (t.cueFile.isNull() | t.cueStartMs.isNotNull()))
        // `dateAdded` collides for bulk-scanned files (same second), so `id`
        // breaks ties deterministically and keeps the stream and the one-shot
        // [getRecentlyAdded] in the same order.
        ..orderBy([
          (t) => OrderingTerm(expression: t.dateAdded, mode: OrderingMode.desc),
          (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
        ]);
      if (limit != null) {
        query.limit(limit);
      }
      _applyExcludedFolders(query, excludedFolders);
      return query
          .watch()
          .map((songs) => Right<AppFailure, List<SongsTableData>>(songs))
          .onResultError((e, st) => Left<AppFailure, List<SongsTableData>>(
              DatabaseFailure('Failed to watch recently added', e)));
    } catch (e) {
      return Stream.value(
          Left(DatabaseFailure('Failed to watch recently added', e)));
    }
  }

  @override
  Future<Result<List<SongsTableData>>> getRecentlyAdded({
    int? limit = 20,
    List<String> excludedFolders = const [],
  }) async {
    try {
      final query = _db.select(_db.songsTable)
        ..where((t) =>
            t.isMissing.equals(false) &
            t.source.equals(SongSource.local) &
            t.path.like('ytmusic://%').not() &
            (t.cueFile.isNull() | t.cueStartMs.isNotNull()))
        // Must stay in sync with [watchRecentlyAdded] so a queue built from
        // this one-shot snapshot matches the displayed section order.
        ..orderBy([
          (t) => OrderingTerm(expression: t.dateAdded, mode: OrderingMode.desc),
          (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
        ]);
      if (limit != null) {
        query.limit(limit);
      }
      _applyExcludedFolders(query, excludedFolders);
      final songs = await query.get();
      return Right(songs);
    } catch (e) {
      return Left(DatabaseFailure('Failed to fetch recently added songs', e));
    }
  }

  @override
  Stream<Result<List<SongsTableData>>> watchTopPlayed({
    int limit = 30,
    List<String> excludedFolders = const [],
  }) {
    try {
      final query = _db.select(_db.songsTable)
        ..where((t) =>
            t.playCount.isBiggerThanValue(0) &
            t.isMissing.equals(false) &
            t.source.equals(SongSource.local) &
            t.path.like('ytmusic://%').not() &
            (t.cueFile.isNull() | t.cueStartMs.isNotNull()))
        ..orderBy([
          (t) => OrderingTerm(expression: t.playCount, mode: OrderingMode.desc)
        ])
        ..limit(limit);
      _applyExcludedFolders(query, excludedFolders);
      return query
          .watch()
          .map((songs) => Right<AppFailure, List<SongsTableData>>(songs))
          .onResultError((e, st) => Left<AppFailure, List<SongsTableData>>(
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
          .onResultError((e, st) => Left<AppFailure, List<AlbumsTableData>>(
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
          .onResultError((e, st) => Left<AppFailure, List<SongsTableData>>(
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
  Future<Result<AlbumsTableData?>> getAlbumById(int albumId) async {
    try {
      final album = await (_db.select(_db.albumsTable)
            ..where((t) => t.id.equals(albumId)))
          .getSingleOrNull();
      return Right(album);
    } catch (e) {
      return Left(DatabaseFailure('Failed to fetch album by id', e));
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
          .onResultError((e, st) => Left<AppFailure, List<ArtistsTableData>>(
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
          .onResultError((e, st) => Left<AppFailure, List<SongsTableData>>(
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
  Future<Result<ArtistsTableData?>> getArtistById(int artistId) async {
    try {
      final artist = await (_db.select(_db.artistsTable)
            ..where((t) => t.id.equals(artistId)))
          .getSingleOrNull();
      return Right(artist);
    } catch (e) {
      return Left(DatabaseFailure('Failed to fetch artist by id', e));
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
          .onResultError((e, st) => Left<AppFailure, List<AlbumsTableData>>(
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
          .onResultError((e, st) => Left<AppFailure, List<PlaylistsTableData>>(
              DatabaseFailure('Failed to watch playlists', e)));
    } catch (e) {
      return Stream.value(
          Left(DatabaseFailure('Failed to watch playlists', e)));
    }
  }

  @override
  Future<Result<PlaylistsTableData?>> getPlaylistById(int playlistId) async {
    try {
      final query = _db.select(_db.playlistsTable)
        ..where((t) => t.id.equals(playlistId));
      final playlist = await query.getSingleOrNull();
      return Right(playlist);
    } catch (e) {
      return Left(DatabaseFailure('Failed to get playlist by id', e));
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
          .onResultError((e, st) => Left<AppFailure, List<SongsTableData>>(
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
      await _db.transaction(() async {
        // Read MAX(orderIndex) inside the same transaction: two concurrent
        // adds used to pick the same next index and one batch then failed
        // against the (playlist_id, order_index) unique index.
        final existingRows = await (_db.select(_db.playlistEntriesTable)
              ..where((t) => t.playlistId.equals(playlistId)))
            .get();
        final existingSongIds = existingRows.map((r) => r.songId).toSet();
        int nextOrderIndex = existingRows.isEmpty
            ? 0
            : existingRows.map((r) => r.orderIndex).reduce(max) + 1;
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

  // --- ONLINE LIBRARY CACHE ---

  static YtmTrack _toYtmTrack(OnlinePlaylistEntriesTableData row) => YtmTrack(
        videoId: row.videoId,
        title: row.title,
        artist: row.artist,
        duration: Duration(milliseconds: row.durationMs),
        artworkUrl: row.artworkUrl,
      );

  static OnlinePlaylistEntriesTableCompanion _onlineEntryCompanion({
    required String playlistId,
    required int orderIndex,
    required YtmTrack track,
  }) =>
      OnlinePlaylistEntriesTableCompanion.insert(
        playlistId: playlistId,
        videoId: track.videoId,
        title: track.title,
        artist: Value(track.artist),
        durationMs: Value(track.duration.inMilliseconds),
        artworkUrl: Value(track.artworkUrl),
        orderIndex: orderIndex,
      );

  @override
  Stream<Result<List<YtmTrack>>> watchOnlinePlaylistTracks(String playlistId) {
    try {
      final query = _db.select(_db.onlinePlaylistEntriesTable)
        ..where((t) => t.playlistId.equals(playlistId))
        ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]);
      return query.watch().map((rows) => Right<AppFailure, List<YtmTrack>>(
          rows.map(_toYtmTrack).toList(growable: false)));
    } catch (e) {
      return Stream.value(
          Left(DatabaseFailure('Failed to watch online playlist tracks', e)));
    }
  }

  @override
  Future<Result<List<YtmTrack>>> getOnlinePlaylistTracks(
      String playlistId) async {
    try {
      final rows = await (_db.select(_db.onlinePlaylistEntriesTable)
            ..where((t) => t.playlistId.equals(playlistId))
            ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
          .get();
      return Right(rows.map(_toYtmTrack).toList(growable: false));
    } catch (e) {
      return Left(DatabaseFailure('Failed to fetch online playlist tracks', e));
    }
  }

  @override
  Future<Result<OnlinePlaylistsTableData?>> getOnlinePlaylist(
      String playlistId) async {
    try {
      final row = await (_db.select(_db.onlinePlaylistsTable)
            ..where((t) => t.playlistId.equals(playlistId)))
          .getSingleOrNull();
      return Right(row);
    } catch (e) {
      return Left(DatabaseFailure('Failed to fetch online playlist', e));
    }
  }

  @override
  Future<Result<List<OnlinePlaylistsTableData>>> getOnlinePlaylists() async {
    try {
      final rows = await (_db.select(_db.onlinePlaylistsTable)
            ..orderBy([
              (t) => OrderingTerm(expression: t.sortOrder),
              (t) => OrderingTerm(expression: t.title),
            ]))
          .get();
      return Right(rows);
    } catch (e) {
      return Left(DatabaseFailure('Failed to fetch online playlists', e));
    }
  }

  @override
  Future<Result<void>> cacheOnlinePlaylist({
    required String playlistId,
    required String kind,
    required String title,
    String author = '',
    String? artworkUrl,
    int sortOrder = 0,
    required List<YtmTrack> tracks,
    bool fullSnapshot = true,
  }) async {
    try {
      await _db.transaction(() async {
        final now = DateTime.now();
        final existing = await (_db.select(_db.onlinePlaylistsTable)
              ..where((t) => t.playlistId.equals(playlistId)))
            .getSingleOrNull();

        // Video ids are unique within a playlist; keep the first occurrence so
        // a duplicated remote page cannot create a duplicate order slot.
        final uniqueTracks = <String, YtmTrack>{};
        for (final track in tracks) {
          if (track.videoId.isEmpty) continue;
          uniqueTracks.putIfAbsent(track.videoId, () => track);
        }

        await _db.into(_db.onlinePlaylistsTable).insertOnConflictUpdate(
              OnlinePlaylistsTableCompanion.insert(
                playlistId: playlistId,
                title: title,
                author: Value(author),
                artworkUrl: Value(artworkUrl ?? existing?.artworkUrl),
                // Keep the classification the playlist was first cached
                // under: opening it from a pasted URL must not turn an
                // account playlist into a custom one.
                kind: Value(existing?.kind ?? kind),
                sortOrder: Value(sortOrder),
                hasCustomOrder: Value(existing?.hasCustomOrder ?? false),
                cachedAt: Value(
                  fullSnapshot && uniqueTracks.isNotEmpty
                      ? now
                      : existing?.cachedAt,
                ),
                updatedAt: Value(now),
              ),
            );

        // An empty response is ambiguous (truncated body, transient parse
        // failure). Keep the cached list rather than presenting an empty
        // playlist and losing a hand-built order.
        if (uniqueTracks.isEmpty) return;

        final existingEntries =
            await (_db.select(_db.onlinePlaylistEntriesTable)
                  ..where((t) => t.playlistId.equals(playlistId))
                  ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
                .get();

        final orderedIds = <String>[];
        final kept = <String>{};
        if ((existing?.hasCustomOrder ?? false) && existingEntries.isNotEmpty) {
          for (final entry in existingEntries) {
            if (uniqueTracks.containsKey(entry.videoId) &&
                kept.add(entry.videoId)) {
              orderedIds.add(entry.videoId);
            }
          }
          for (final id in uniqueTracks.keys) {
            if (kept.add(id)) orderedIds.add(id);
          }
        } else {
          orderedIds.addAll(uniqueTracks.keys);
        }

        // Replace the snapshot wholesale: simpler than diffing, and the ids of
        // these rows are not referenced anywhere else.
        await (_db.delete(_db.onlinePlaylistEntriesTable)
              ..where((t) => t.playlistId.equals(playlistId)))
            .go();

        await _db.batch((batch) {
          for (var i = 0; i < orderedIds.length; i++) {
            batch.insert(
              _db.onlinePlaylistEntriesTable,
              _onlineEntryCompanion(
                playlistId: playlistId,
                orderIndex: i,
                track: uniqueTracks[orderedIds[i]]!,
              ),
            );
          }
        });
      });
      return const Right(null);
    } catch (e) {
      return Left(DatabaseFailure('Failed to cache online playlist', e));
    }
  }

  @override
  Future<Result<void>> reorderOnlinePlaylistTracks(
      String playlistId, List<String> orderedVideoIds) async {
    try {
      await _db.transaction(() async {
        final entries = await (_db.select(_db.onlinePlaylistEntriesTable)
              ..where((t) => t.playlistId.equals(playlistId))
              ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
            .get();
        if (entries.isEmpty) return;

        final byVideoId = <String, OnlinePlaylistEntriesTableData>{
          for (final entry in entries) entry.videoId: entry,
        };
        final ordered = <String>[];
        final seen = <String>{};
        for (final id in orderedVideoIds) {
          if (byVideoId.containsKey(id) && seen.add(id)) {
            ordered.add(id);
          }
        }
        // Tracks that arrived while the user was dragging keep their relative
        // order and land at the end instead of being dropped.
        for (final entry in entries) {
          if (seen.add(entry.videoId)) ordered.add(entry.videoId);
        }

        await (_db.delete(_db.onlinePlaylistEntriesTable)
              ..where((t) => t.playlistId.equals(playlistId)))
            .go();

        await _db.batch((batch) {
          for (var i = 0; i < ordered.length; i++) {
            final entry = byVideoId[ordered[i]]!;
            batch.insert(
              _db.onlinePlaylistEntriesTable,
              _onlineEntryCompanion(
                playlistId: playlistId,
                orderIndex: i,
                track: _toYtmTrack(entry),
              ),
            );
          }
        });

        await (_db.update(_db.onlinePlaylistsTable)
              ..where((t) => t.playlistId.equals(playlistId)))
            .write(OnlinePlaylistsTableCompanion(
          hasCustomOrder: const Value(true),
          updatedAt: Value(DateTime.now()),
        ));
      });
      return const Right(null);
    } catch (e) {
      return Left(DatabaseFailure('Failed to reorder online playlist', e));
    }
  }

  @override
  Future<Result<void>> renameOnlinePlaylist(
      String playlistId, String newTitle) async {
    try {
      await (_db.update(_db.onlinePlaylistsTable)
            ..where((t) => t.playlistId.equals(playlistId)))
          .write(OnlinePlaylistsTableCompanion(
        title: Value(newTitle.trim()),
        updatedAt: Value(DateTime.now()),
      ));
      return const Right(null);
    } catch (e) {
      return Left(DatabaseFailure('Failed to rename online playlist', e));
    }
  }

  @override
  Future<Result<void>> removeOnlinePlaylist(String playlistId) async {
    try {
      await _db.transaction(() async {
        await (_db.delete(_db.onlinePlaylistEntriesTable)
              ..where((t) => t.playlistId.equals(playlistId)))
            .go();
        await (_db.delete(_db.onlinePlaylistsTable)
              ..where((t) => t.playlistId.equals(playlistId)))
            .go();
      });
      return const Right(null);
    } catch (e) {
      return Left(DatabaseFailure('Failed to remove online playlist', e));
    }
  }

  @override
  Future<Result<void>> clearOnlineLibraryCache() async {
    try {
      await _db.transaction(() async {
        await _db.delete(_db.onlinePlaylistEntriesTable).go();
        await _db.delete(_db.onlinePlaylistsTable).go();
      });
      return const Right(null);
    } catch (e) {
      return Left(DatabaseFailure('Failed to clear online library cache', e));
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
          .onResultError((e, st) =>
              Left<AppFailure, List<ExcludedFoldersTableData>>(
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
        if (songIds.isEmpty) return;
        final existingRows = await (_db.selectOnly(_db.songsTable)
              ..addColumns([_db.songsTable.id])
              ..where(_db.songsTable.id.isIn(songIds)))
            .get();
        final existingIds =
            existingRows.map((r) => r.read(_db.songsTable.id)!).toSet();
        await _db.batch((batch) {
          for (int i = 0; i < songIds.length; i++) {
            final id = songIds[i];
            if (!existingIds.contains(id)) continue;
            batch.insert(
              _db.queueItemsTable,
              QueueItemsTableCompanion.insert(
                songId: id,
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
      await _db.transaction(() async {
        // Collapse legacy case-variant duplicates before remapping: the remap
        // keys on lower(path), so a single owner must exist before the upsert
        // can land on it without colliding with a loser's exact path.
        await _dedupeSongsByPath();
        final remappedSongs = await _remapSongsOntoExistingPaths(songs);
        final preservedSongs = await _preserveExistingMetadata(remappedSongs);
        await _db.batch((batch) {
          batch.insertAllOnConflictUpdate(_db.songsTable, preservedSongs);
          batch.insertAllOnConflictUpdate(_db.albumsTable, albums);
          batch.insertAllOnConflictUpdate(_db.artistsTable, artists);
        });
        // Defensive second pass: the incoming batch itself may contain
        // case-variant duplicates.
        await _dedupeSongsByPath();
      });
      return const Right(null);
    } catch (e) {
      return Left(DatabaseFailure('Failed to sync scanned music', e));
    }
  }

  /// Deduplicates local rows sharing a normalized path — prevents a downloaded
  /// song appearing twice when the scanner inserts a new row for a path already
  /// owned by a reconciled YTM row. Keep, per path, a downloaded row in
  /// preference to a plain scanned row, then the lowest id so play history
  /// survives. Child rows (playlist membership, queue slots, play history) are
  /// re-pointed to the surviving id before the loser is deleted, so the FK
  /// cascade cannot drop them. Only touched when a path genuinely has >1 local
  /// row (the UNIQUE(path,cue) index makes this unreachable in normal
  /// operation, so this is purely defensive against pre-index rows).
  Future<void> _dedupeSongsByPath() async {
    final rows = await _db
        .customSelect(
          "SELECT s1.id AS id, s1.is_downloaded AS downloaded, "
          "lower(s1.path) AS path_key "
          "FROM songs s1 "
          "WHERE s1.source = 'local' AND s1.path != '' "
          "AND s1.path NOT LIKE 'ytmusic://%' "
          "AND s1.cue_start_ms IS NULL "
          "AND lower(s1.path) IN ("
          "SELECT lower(path) FROM songs "
          "WHERE source = 'local' AND path != '' "
          "AND path NOT LIKE 'ytmusic://%' "
          "AND cue_start_ms IS NULL "
          "GROUP BY lower(path) HAVING COUNT(*) > 1)",
        )
        .get();
    if (rows.isEmpty) return;

    final groups = <String, List<(int, int)>>{};
    for (final row in rows) {
      groups
          .putIfAbsent(row.read<String>('path_key'), () => [])
          .add((row.read<int>('id'), row.read<int>('downloaded')));
    }

    for (final group in groups.values) {
      // Downloaded rows win over plain scanned rows; then the lowest id.
      group.sort((a, b) {
        if (a.$2 != b.$2) return b.$2.compareTo(a.$2);
        return a.$1.compareTo(b.$1);
      });
      final survivorId = group.first.$1;
      for (final loser in group.skip(1)) {
        await _db.customStatement(
          'DELETE FROM playlist_entries WHERE song_id = ? AND playlist_id IN '
          '(SELECT playlist_id FROM playlist_entries WHERE song_id = ?);',
          [loser.$1, survivorId],
        );
        await _db.customStatement(
          'UPDATE playlist_entries SET song_id = ? WHERE song_id = ?;',
          [survivorId, loser.$1],
        );
        await _db.customStatement(
          'UPDATE queue_items SET song_id = ? WHERE song_id = ?;',
          [survivorId, loser.$1],
        );
        await _db.customStatement(
          'UPDATE play_history SET song_id = ? WHERE song_id = ?;',
          [survivorId, loser.$1],
        );
        await _db.customStatement(
          'DELETE FROM songs WHERE id = ?;',
          [loser.$1],
        );
      }
    }
  }

  /// Rewrites incoming scanner rows so their primary key matches any existing
  /// local row that already owns the same `(lower(path), cue window)`. This
  /// turns what would be a UNIQUE(path) violation on a changed MediaStore id
  /// into a primary-key update, preserving the row id and its user data.
  Future<List<SongsTableCompanion>> _remapSongsOntoExistingPaths(
      List<SongsTableCompanion> songs) async {
    if (songs.isEmpty) return songs;

    final paths = <String>{};
    for (final c in songs) {
      final p = c.path.present ? c.path.value : null;
      if (p != null && p.isNotEmpty) paths.add(p);
    }
    if (paths.isEmpty) return songs;

    final pathList = paths.toList();
    final byKey = <(String, int), int>{};
    const batchSize = 400;

    for (var i = 0; i < pathList.length; i += batchSize) {
      final chunk = pathList.sublist(i, min(i + batchSize, pathList.length));
      // Match on lower(path): the keys below are lowercased, and a
      // case-insensitive filesystem reports the same file with different
      // casing across scans. An exact-case IN would miss the owner row and
      // insert a duplicate.
      final lowerChunk = chunk.map((p) => p.toLowerCase()).toList();
      final query = _db.selectOnly(_db.songsTable)
        ..addColumns([
          _db.songsTable.id,
          _db.songsTable.path,
          _db.songsTable.cueStartMs,
        ])
        ..where(_db.songsTable.source.equals(SongSource.local) &
            _db.songsTable.path.lower().isIn(lowerChunk));

      final rows = await query.get();
      for (final row in rows) {
        final id = row.read(_db.songsTable.id);
        final path = row.read(_db.songsTable.path);
        final cueStart = row.read(_db.songsTable.cueStartMs);
        if (id != null && path != null && path.isNotEmpty) {
          byKey[(path.toLowerCase(), cueStart ?? -1)] = id;
        }
      }
    }

    if (byKey.isEmpty) return songs;
    var changed = false;
    final out = <SongsTableCompanion>[];
    for (final c in songs) {
      final path = c.path.present ? c.path.value : null;
      final id = c.id.present ? c.id.value : null;
      if (path != null && path.isNotEmpty && id != null) {
        final key = (
          path.toLowerCase(),
          c.cueStartMs.present ? (c.cueStartMs.value ?? -1) : -1
        );
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

  /// Stops a scanner pass from replacing authoritative metadata with the
  /// placeholders MediaStore uses when a container has no readable tags.
  ///
  /// A downloaded WebM/Opus (or a file whose tag write failed) is indexed by
  /// MediaStore as "Unknown Artist"/"Unknown Album" and a file-name title.
  /// Without this merge, every library rescan reverted a correctly reconciled
  /// download back to Unknown Artist.
  Future<List<SongsTableCompanion>> _preserveExistingMetadata(
      List<SongsTableCompanion> songs) async {
    if (songs.isEmpty) return songs;

    final ids = <int>{};
    for (final companion in songs) {
      if (companion.id.present) ids.add(companion.id.value);
    }
    if (ids.isEmpty) return songs;

    final existingById = <int, SongsTableData>{};
    final idList = ids.toList(growable: false);
    const chunkSize = 400;
    for (var i = 0; i < idList.length; i += chunkSize) {
      final chunk = idList.sublist(i, (i + chunkSize).clamp(0, idList.length));
      final rows = await (_db.select(_db.songsTable)
            ..where((t) => t.id.isIn(chunk)))
          .get();
      for (final row in rows) {
        existingById[row.id] = row;
      }
    }
    if (existingById.isEmpty) return songs;

    final out = <SongsTableCompanion>[];
    for (final incoming in songs) {
      if (!incoming.id.present) {
        out.add(incoming);
        continue;
      }
      final existing = existingById[incoming.id.value];
      if (existing == null) {
        out.add(incoming);
        continue;
      }
      out.add(_preserveOneScannedMetadata(incoming, existing));
    }
    return out;
  }

  SongsTableCompanion _preserveOneScannedMetadata(
    SongsTableCompanion incoming,
    SongsTableData existing,
  ) {
    final incomingTitle = incoming.title.present ? incoming.title.value : null;
    final incomingArtist =
        incoming.artist.present ? incoming.artist.value : null;
    final incomingAlbum = incoming.album.present ? incoming.album.value : null;

    final scannerLacksTags =
        MetadataPlaceholders.isUnknownArtist(incomingArtist) ||
            MetadataPlaceholders.isUnknownAlbum(incomingAlbum);
    final downloadedTitleIsSuspect = existing.isDownloaded && scannerLacksTags;

    final keepExistingTitle = (downloadedTitleIsSuspect ||
            MetadataPlaceholders.isUnknownTitle(incomingTitle)) &&
        MetadataPlaceholders.isRealTitle(existing.title);
    final keepExistingArtist =
        MetadataPlaceholders.isUnknownArtist(incomingArtist) &&
            MetadataPlaceholders.isRealArtist(existing.artist);
    final keepExistingAlbum =
        MetadataPlaceholders.isUnknownAlbum(incomingAlbum) &&
            MetadataPlaceholders.isRealAlbum(existing.album);

    final incomingGenre = incoming.genre.present ? incoming.genre.value : null;
    final incomingYear = incoming.year.present ? incoming.year.value : null;
    final incomingTrack =
        incoming.trackNumber.present ? incoming.trackNumber.value : null;

    return incoming.copyWith(
      title: keepExistingTitle ? Value(existing.title) : incoming.title,
      artist: keepExistingArtist ? Value(existing.artist) : incoming.artist,
      album: keepExistingAlbum ? Value(existing.album) : incoming.album,
      artistId:
          keepExistingArtist ? Value(existing.artistId) : incoming.artistId,
      albumId: keepExistingAlbum ? Value(existing.albumId) : incoming.albumId,
      durationMs: incoming.durationMs.present && incoming.durationMs.value > 0
          ? incoming.durationMs
          : (existing.durationMs > 0
              ? Value(existing.durationMs)
              : incoming.durationMs),
      genre: (incomingGenre == null || incomingGenre.trim().isEmpty) &&
              (existing.genre ?? '').trim().isNotEmpty
          ? Value(existing.genre)
          : incoming.genre,
      year: incomingYear == null && existing.year != null
          ? Value(existing.year)
          : incoming.year,
      trackNumber: incomingTrack == null && existing.trackNumber != null
          ? Value(existing.trackNumber)
          : incoming.trackNumber,
      fileSize: incoming.fileSize.present && incoming.fileSize.value != null
          ? incoming.fileSize
          : (existing.fileSize != null
              ? Value(existing.fileSize)
              : incoming.fileSize),
      uri: incoming.uri.present && (incoming.uri.value ?? '').isNotEmpty
          ? incoming.uri
          : (existing.uri != null ? Value(existing.uri) : incoming.uri),
      dateAdded: incoming.dateAdded.present && incoming.dateAdded.value != null
          ? incoming.dateAdded
          : (existing.dateAdded != null
              ? Value(existing.dateAdded)
              : incoming.dateAdded),
    );
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

  /// Paths already probed for an embedded CUE sheet with nothing found.
  /// Negative-only and process-lifetime: every rescan must not re-open every
  /// FLAC/WAV just to rediscover there is no embedded sheet. A file that gains
  /// an embedded cue mid-process is picked up on the next app start.
  static final Set<String> _embeddedCueMisses = {};
  static const int _embeddedCueMissCacheMax = 20000;

  /// Test seam: number of embedded-cue probes actually attempted.
  @visibleForTesting
  static int embeddedCueProbeCount = 0;

  /// Cache of container path -> cue content hash to skip re-parsing unchanged cue sheets.
  static final Map<String, int> _cueContentHashCache = {};
  static const int _cueContentHashCacheMax = 20000;

  /// Bounded write-through for [_cueContentHashCache]. Without the trim this
  /// static map lives for the whole process and grows with every CUE-backed
  /// container ever seen.
  static void _rememberCueContentHash(String path, int hash) {
    if (!_cueContentHashCache.containsKey(path) &&
        _cueContentHashCache.length >= _cueContentHashCacheMax) {
      final toRemove = (_cueContentHashCacheMax * 0.25).toInt();
      for (final key in _cueContentHashCache.keys.take(toRemove).toList()) {
        _cueContentHashCache.remove(key);
      }
    }
    _cueContentHashCache[path] = hash;
  }

  @visibleForTesting
  static void resetEmbeddedCueProbeState() {
    _embeddedCueMisses.clear();
    _cueContentHashCache.clear();
    embeddedCueProbeCount = 0;
  }

  static void _rememberEmbeddedCueMiss(String path) {
    if (_embeddedCueMisses.length >= _embeddedCueMissCacheMax) {
      final toRemove = (_embeddedCueMissCacheMax * 0.25).toInt();
      for (final key in _embeddedCueMisses.take(toRemove).toList()) {
        _embeddedCueMisses.remove(key);
      }
    }
    _embeddedCueMisses.add(path);
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
      // Paths whose cue state was conclusively evaluated in this pass. Virtual
      // rows for any other path (e.g. a container that is currently missing or
      // a cue that could not be read) must be preserved: deleting them would
      // cascade away playlist entries and play history for a transient I/O
      // failure.
      final evaluatedPaths = <String>{};
      var expanded = 0;

      for (final container in containers) {
        final cuePath = _siblingCuePath(container.path);
        String? effectiveCuePath;
        String? rawCueContent;
        var cueReadFailed = false;
        List<ChapterInfo> chapters = const [];

        if (cuePath.isNotEmpty && await File(cuePath).exists()) {
          try {
            rawCueContent = await File(cuePath).readAsString();
            effectiveCuePath = cuePath;
          } catch (_) {
            cueReadFailed = true;
          }
        } else if (!_embeddedCueMisses.contains(container.path)) {
          embeddedCueProbeCount++;
          final embedded =
              await CueParser.extractEmbeddedCueSheet(container.path);
          if (embedded != null && embedded.isNotEmpty) {
            rawCueContent = embedded;
            effectiveCuePath = 'embedded://${container.path}';
          } else {
            _rememberEmbeddedCueMiss(container.path);
          }
        }

        if (rawCueContent == null ||
            rawCueContent.isEmpty ||
            effectiveCuePath == null) {
          _cueContentHashCache.remove(container.path);
          // A failed read is not evidence that the cue sheet disappeared;
          // only a definitively absent/empty cue retires its virtual rows.
          if (!cueReadFailed) evaluatedPaths.add(container.path);
          continue;
        }

        final contentHash = rawCueContent.hashCode;
        final cachedHash = _cueContentHashCache[container.path];
        // If the cue sheet content hasn't changed, reuse existing virtual tracks without re-parsing
        if (cachedHash != null && cachedHash == contentHash) {
          final existingVirtual = await (_db.select(_db.songsTable)
                ..where((t) =>
                    t.path.equals(container.path) & t.cueStartMs.isNotNull()))
              .get();
          if (existingVirtual.isNotEmpty) {
            newIdsByPath[container.path] =
                existingVirtual.map((v) => v.id).toList();
            coverByContainerId[container.id] = effectiveCuePath;
            coveredPaths.add(container.path);
            evaluatedPaths.add(container.path);
            expanded += existingVirtual.length;
            continue;
          }
        }

        chapters = CueParser.parse(rawCueContent);

        if (chapters.isEmpty) {
          evaluatedPaths.add(container.path);
          continue;
        }
        // Only whole-file album sheets are expanded. Multi-file sheets map
        // chapters onto several source files; expanding the wrong window on
        // this one file would fabricate playback, so skip them.
        final fileNames = chapters
            .map((c) => (c.fileName ?? '').toLowerCase())
            .where((f) => f.isNotEmpty)
            .toSet();
        if (fileNames.length > 1) {
          evaluatedPaths.add(container.path);
          continue;
        }
        // The cue must reference this audio file, not an unrelated sibling.
        if (fileNames.isNotEmpty &&
            !effectiveCuePath.startsWith('embedded://')) {
          final referenced = fileNames.first;
          final audioName = container.path
              .replaceAll('\\', '/')
              .split('/')
              .last
              .toLowerCase();
          if (referenced != audioName) {
            evaluatedPaths.add(container.path);
            continue;
          }
        }
        final virtual = buildCueExpansion(
          container: container,
          chapters: chapters,
          cuePath: effectiveCuePath,
        );
        if (virtual.isEmpty) {
          evaluatedPaths.add(container.path);
          continue;
        }
        _rememberCueContentHash(container.path, contentHash);
        companions.addAll(virtual);
        newIdsByPath[container.path] = virtual.map((c) => c.id.value).toList();
        coverByContainerId[container.id] = effectiveCuePath;
        coveredPaths.add(container.path);
        evaluatedPaths.add(container.path);
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
          // As with virtual rows, only clear markers for containers this pass
          // actually observed; an absent SD card must not unhide a file that
          // still has its cue sheet on disk.
          if (!evaluatedPaths.contains(marker.path)) continue;
          await (_db.update(_db.songsTable)
                ..where((t) => t.id.equals(marker.id)))
              .write(const SongsTableCompanion(cueFile: Value(null)));
        }
        // Drop virtual rows that no longer belong to a live expansion.
        final virtualRows = await (_db.select(_db.songsTable)
              ..where((t) => t.cueStartMs.isNotNull()))
            .get();
        for (final row in virtualRows) {
          // Never delete a virtual row whose container was not conclusively
          // evaluated in this pass (missing/unreadable file): the cue could
          // return on the next scan and the row still owns playlist/history
          // references.
          if (!evaluatedPaths.contains(row.path)) continue;
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

  /// Case-insensitive, separator-normalized containment check matching the
  /// scanner's own exclusion rule, so "hidden" and "missing" cannot disagree.
  static bool _isUnderExcludedFolder(
      String path, List<String> excludedFolderPrefixes) {
    if (excludedFolderPrefixes.isEmpty || path.isEmpty) return false;
    final normPath = path.toLowerCase();
    for (final folder in excludedFolderPrefixes) {
      if (folder.isEmpty) continue;
      final normFolder = folder.toLowerCase();
      // Accept both separators: the row may carry a MediaStore '/' path while
      // the stored exclusion was built with the host separator (or vice versa).
      for (final sep in const ['/', r'\']) {
        final prefix =
            normFolder.endsWith(sep) ? normFolder : '$normFolder$sep';
        if (normPath == normFolder || normPath.startsWith(prefix)) return true;
      }
    }
    return false;
  }

  @override
  Future<Result<int>> cleanupOrphanedSongs(
    Set<int> scannedSongIds, {
    List<String> excludedFolderPrefixes = const [],
  }) async {
    try {
      // NEVER delete or mark missing on an empty scan result (protect against unmounted SD cards, OS indexing, permission drops)
      if (scannedSongIds.isEmpty) {
        return const Right(0);
      }

      // 1. Fetch all local songs and compute unscanned in Dart memory to avoid SQLite variable limits
      final allLocalSongs = await (_db.select(_db.songsTable)
            ..where((t) =>
                t.id.isBiggerThanValue(0) & t.source.equals(SongSource.local)))
          .get();
      // A user-excluded folder is *hidden*, not missing: the scanner drops
      // those rows from `validSongIds` by design, so treating them as absent
      // would mark them missing and let "remove missing files" hard-delete
      // real library rows (favourites, play counts, ratings).
      final unscannedSongs = allLocalSongs
          .where((s) => !scannedSongIds.contains(s.id))
          .where((s) => !_isUnderExcludedFolder(s.path, excludedFolderPrefixes))
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
      final unscannedById = {for (final s in unscannedSongs) s.id: s};
      for (final id in trulyMissingIds) {
        final song = unscannedById[id];
        if (song == null) continue;
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

  /// Resolves the directories Pulsr is allowed to delete local audio from.
  /// Shared with the download-artifact path so both delete surfaces enforce
  /// the same containment policy.
  Future<List<String>> _allowedDeleteRoots() => allowedAppDeleteRoots();

  /// Defensive containment check before deleting a local file. Requires the
  /// path to be a non-empty absolute audio file whose canonical location sits
  /// under an allowed app root. If no root can be resolved, the delete is
  /// refused (fail safe).
  Future<bool> _isSafeLocalDeletePath(String path) async {
    final file = await resolveDeletableAudioFile(
      path,
      allowedExtensions: AudioFormats.supportedExtensions.toList(),
      roots: await _allowedDeleteRoots(),
      logCategory: 'MusicRepository',
    );
    return file != null;
  }

  /// Asks the platform to delete a MediaStore row (and the file behind it).
  /// Returns false on non-Android hosts, when the plugin is missing, or when
  /// the platform reports that it removed nothing.
  Future<bool> _deleteViaMediaStore(String path) async {
    if (!Platform.isAndroid) return false;
    try {
      final deleted = await const MethodChannel(PulsrChannels.ytDownload)
          .invokeMethod<bool>('deleteFromMusic', {'path': path}).timeout(
              const Duration(seconds: 2));
      return deleted ?? false;
    } catch (e, st) {
      ErrorLogger.log('MediaStore delete failed for "$path"',
          error: e, stackTrace: st, category: 'MusicRepository');
      return false;
    }
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
          final playlistIds =
              await (_db.selectOnly(_db.playlistEntriesTable, distinct: true)
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
          // App-owned files (downloads, cache) are removed directly under the
          // containment guard. Library files in a shared collection cannot be
          // File.delete()'d under scoped storage, so they go through the same
          // MediaStore request the download path uses. Without this the row was
          // deleted but the file survived, and the next scan re-indexed the
          // track with no favourites, ratings or play count.
          if (await _isSafeLocalDeletePath(path)) {
            final file = File(path);
            if (await file.exists()) await file.delete();
          } else if (!await _deleteViaMediaStore(path)) {
            ErrorLogger.log(
              'Deleted song ${song.id} from the library but left its file in place: $path',
              category: 'MusicRepository',
            );
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

  /// Chooses the best real metadata for a merged download row. The existing
  /// row wins, then the download's known value, then the scanner's.
  static String _bestMetadata(
    String current,
    String? downloaded,
    String? scanned,
    bool Function(String?) isPlaceholder,
  ) {
    if (!isPlaceholder(current)) return current;
    if (downloaded != null && !isPlaceholder(downloaded)) return downloaded;
    if (scanned != null && !isPlaceholder(scanned)) return scanned;
    return current;
  }

  /// For a row the scanner created while saving, the download's known value is
  /// authoritative: MediaStore may have guessed from the file name or found no
  /// tags at all.
  static String _downloadedMetadata(
    String scanned,
    String? downloaded,
    bool Function(String?) isPlaceholder,
  ) =>
      (downloaded != null && !isPlaceholder(downloaded)) ? downloaded : scanned;

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
        // A metadata match on a *different* path that still exists is an
        // unrelated same-title local track, not this download. Hijacking it
        // marked that file downloaded and orphaned the new one.
        if (newRow != null && newRow.path != newPath) {
          var matchedPathExists = false;
          try {
            matchedPathExists =
                newRow.path.isNotEmpty && await File(newRow.path).exists();
          } catch (_) {}
          if (matchedPathExists) newRow = null;
        }
      }

      final fileExists = await File(newPath).exists();

      // Step 2: Write phase in focused transaction
      await _db.transaction(() async {
        if (newRow == null) {
          if (fileExists) {
            final nowMs = DateTime.now().millisecondsSinceEpoch;
            if (oldRow != null) {
              final resolvedDateAdded = (oldRow.dateAdded ?? 0) > 0
                  ? (oldRow.dateAdded! < 10000000000
                      ? oldRow.dateAdded! * 1000
                      : oldRow.dateAdded!)
                  : nowMs;
              final bestTitle = _bestMetadata(oldRow.title, fallbackSong?.title,
                  null, MetadataPlaceholders.isUnknownTitle);
              final bestArtist = _bestMetadata(
                  oldRow.artist,
                  fallbackSong?.artist,
                  null,
                  MetadataPlaceholders.isUnknownArtist);
              final bestAlbum = _bestMetadata(oldRow.album, fallbackSong?.album,
                  null, MetadataPlaceholders.isUnknownAlbum);
              await (_db.update(_db.songsTable)
                    ..where((t) => t.id.equals(oldId)))
                  .write(
                SongsTableCompanion(
                  path: Value(newPath),
                  title: Value(bestTitle),
                  artist: Value(bestArtist),
                  album: Value(bestAlbum),
                  artistId: bestArtist != oldRow.artist
                      ? const Value(null)
                      : const Value.absent(),
                  albumId: bestAlbum != oldRow.album
                      ? const Value(null)
                      : const Value.absent(),
                  durationMs: oldRow.durationMs <= 0 &&
                          (fallbackSong?.durationMs ?? 0) > 0
                      ? Value(fallbackSong!.durationMs)
                      : const Value.absent(),
                  source: const Value(SongSource.local),
                  isMissing: const Value(false),
                  isDownloaded: const Value(true),
                  dateAdded: Value(resolvedDateAdded),
                  pendingDownloadPath: const Value(null),
                  remoteId: (oldRow.remoteId ?? '').trim().isEmpty &&
                          (fallbackSong?.remoteId ?? '').trim().isNotEmpty
                      ? Value(fallbackSong!.remoteId)
                      : const Value.absent(),
                  remoteArtworkUrl:
                      (oldRow.remoteArtworkUrl ?? '').trim().isEmpty &&
                              (fallbackSong?.remoteArtworkUrl ?? '')
                                  .trim()
                                  .isNotEmpty
                          ? Value(fallbackSong!.remoteArtworkUrl)
                          : const Value.absent(),
                  bitrateKbps: fallbackSong?.bitrateKbps != null
                      ? Value(fallbackSong!.bitrateKbps)
                      : const Value.absent(),
                  codec: fallbackSong?.codec != null
                      ? Value(fallbackSong!.codec)
                      : const Value.absent(),
                  sampleRate: fallbackSong?.sampleRate != null
                      ? Value(fallbackSong!.sampleRate)
                      : const Value.absent(),
                ),
              );
              survivingId = oldId;
              // FIX: Clean any other row that already owns this path (scanner may have inserted it first)
              try {
                final dupes = await (_db.select(_db.songsTable)
                      ..where((t) =>
                          t.path.lower().equals(newPath.toLowerCase()) &
                          t.id.equals(oldId).not()))
                    .get();
                for (final d in dupes) {
                  await (_db.update(_db.playlistEntriesTable)
                        ..where((t) => t.songId.equals(d.id)))
                      .write(
                          PlaylistEntriesTableCompanion(songId: Value(oldId)));
                  await (_db.update(_db.queueItemsTable)
                        ..where((t) => t.songId.equals(d.id)))
                      .write(QueueItemsTableCompanion(songId: Value(oldId)));
                  await (_db.delete(_db.songsTable)
                        ..where((t) => t.id.equals(d.id)))
                      .go();
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
                      dateAdded: Value(nowMs),
                      bitrateKbps: fallbackSong.bitrateKbps != null
                          ? Value(fallbackSong.bitrateKbps)
                          : const Value.absent(),
                      codec: fallbackSong.codec != null
                          ? Value(fallbackSong.codec)
                          : const Value.absent(),
                      sampleRate: fallbackSong.sampleRate != null
                          ? Value(fallbackSong.sampleRate)
                          : const Value.absent(),
                    ),
                    mode: InsertMode.insertOrReplace,
                  );
              survivingId = oldId;
              try {
                final dupes2 = await (_db.select(_db.songsTable)
                      ..where((t) =>
                          t.path.lower().equals(newPath.toLowerCase()) &
                          t.id.equals(oldId).not()))
                    .get();
                for (final d in dupes2) {
                  await (_db.delete(_db.songsTable)
                        ..where((t) => t.id.equals(d.id)))
                      .go();
                }
              } catch (_) {}
            }
          }
          return;
        }

        final targetId = newRow.id;
        survivingId = targetId;

        if (oldRow == null || oldRow.id == targetId) {
          // The scanner already owns the path (or the download row itself is
          // the target). Adopt the download's metadata instead of trusting
          // MediaStore, which falls back to "Unknown Artist" when the
          // container carries no readable tags (WebM/Opus) and otherwise
          // guesses the title from the file name.
          final bestTitle = _downloadedMetadata(newRow.title,
              fallbackSong?.title, MetadataPlaceholders.isUnknownTitle);
          final bestArtist = _downloadedMetadata(newRow.artist,
              fallbackSong?.artist, MetadataPlaceholders.isUnknownArtist);
          final bestAlbum = _downloadedMetadata(newRow.album,
              fallbackSong?.album, MetadataPlaceholders.isUnknownAlbum);
          final bestDuration = newRow.durationMs > 0
              ? newRow.durationMs
              : (fallbackSong?.durationMs ?? 0);
          final bestRemoteId = (newRow.remoteId ?? '').trim().isNotEmpty
              ? newRow.remoteId
              : fallbackSong?.remoteId;
          final bestArt = (newRow.remoteArtworkUrl ?? '').trim().isNotEmpty
              ? newRow.remoteArtworkUrl
              : fallbackSong?.remoteArtworkUrl;
          await (_db.update(_db.songsTable)
                ..where((t) => t.id.equals(targetId)))
              .write(SongsTableCompanion(
            title: Value(bestTitle),
            artist: Value(bestArtist),
            album: Value(bestAlbum),
            // A scanner id for the placeholder name would still take the song
            // to an "Unknown Artist" page; drop it when the name was repaired.
            artistId: bestArtist != newRow.artist
                ? const Value(null)
                : const Value.absent(),
            albumId: bestAlbum != newRow.album
                ? const Value(null)
                : const Value.absent(),
            durationMs:
                bestDuration > 0 ? Value(bestDuration) : const Value.absent(),
            path:
                newRow.path != newPath ? Value(newPath) : const Value.absent(),
            source: const Value(SongSource.local),
            isMissing: const Value(false),
            isDownloaded: const Value(true),
            pendingDownloadPath: const Value(null),
            remoteId: bestRemoteId != null && bestRemoteId.trim().isNotEmpty
                ? Value(bestRemoteId)
                : const Value.absent(),
            remoteArtworkUrl: bestArt != null && bestArt.trim().isNotEmpty
                ? Value(bestArt)
                : const Value.absent(),
          ));
          return;
        }
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
            await LibraryMaintenanceService.tombstoneSong(_db, oldId);
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

        final String effectiveTitle = _bestMetadata(
            oldData.title,
            fallbackSong?.title,
            newData.title,
            MetadataPlaceholders.isUnknownTitle);
        final String effectiveArtist = _bestMetadata(
            oldData.artist,
            fallbackSong?.artist,
            newData.artist,
            MetadataPlaceholders.isUnknownArtist);
        final String effectiveAlbum = _bestMetadata(
            oldData.album,
            fallbackSong?.album,
            newData.album,
            MetadataPlaceholders.isUnknownAlbum);
        final String? effectiveRemoteArt = [
          oldData.remoteArtworkUrl,
          fallbackSong?.remoteArtworkUrl,
          newData.remoteArtworkUrl,
        ].firstWhere((v) => v != null && v.trim().isNotEmpty,
            orElse: () => null);
        final String? effectiveRemoteId = [
          oldData.remoteId,
          fallbackSong?.remoteId,
          newData.remoteId,
        ].firstWhere((v) => v != null && v.trim().isNotEmpty,
            orElse: () => null);

        await (_db.update(_db.songsTable)..where((t) => t.id.equals(targetId)))
            .write(
          SongsTableCompanion(
            title: Value(effectiveTitle),
            artist: Value(effectiveArtist),
            album: Value(effectiveAlbum),
            artistId: effectiveArtist != newData.artist
                ? const Value(null)
                : const Value.absent(),
            albumId: effectiveAlbum != newData.album
                ? const Value(null)
                : const Value.absent(),
            genre: Value(oldData.genre ?? newData.genre),
            isFavorite: Value(oldData.isFavorite || newData.isFavorite),
            playCount: Value(oldData.playCount + newData.playCount),
            lastPlayed: Value(mergedLastPlayed),
            lastPositionMs: Value(keepOldPosition
                ? oldData.lastPositionMs
                : newData.lastPositionMs),
            // Carry the video id and online remoteArtworkUrl
            remoteId: Value(effectiveRemoteId),
            remoteArtworkUrl: Value(effectiveRemoteArt),
            path:
                newData.path != newPath ? Value(newPath) : const Value.absent(),
            source: const Value(SongSource.local),
            isMissing: const Value(false),
            isDownloaded: const Value(true),
            pendingDownloadPath: const Value(null),
          ),
        );

        // FIX: Remove any other duplicate path rows that the scanner may have inserted in parallel
        // This guarantees a single entry per file path after download, fixing "repeats twice on local"
        final newRowPath = newPath;
        final duplicateOthers = await (_db.select(_db.songsTable)
              ..where((t) =>
                  t.path.lower().equals(newRowPath.toLowerCase()) &
                  t.id.isNotIn([oldId, targetId])))
            .get();
        for (final dupe in duplicateOthers) {
          try {
            // Move any playlist/queue/history refs to surviving target before deleting duplicate
            await (_db.update(_db.playlistEntriesTable)
                  ..where((t) => t.songId.equals(dupe.id)))
                .write(PlaylistEntriesTableCompanion(songId: Value(targetId)));
            await (_db.update(_db.queueItemsTable)
                  ..where((t) => t.songId.equals(dupe.id)))
                .write(QueueItemsTableCompanion(songId: Value(targetId)));
            await (_db.delete(_db.songsTable)
                  ..where((t) => t.id.equals(dupe.id)))
                .go();
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
                t.path.lower().equals(path.toLowerCase()) &
                t.source.equals(SongSource.local) &
                t.cueStartMs.isNull()))
          .getSingleOrNull();
      if (existing != null) {
        // A reader that could not parse tags (or a failed tag write) reports
        // placeholders. Do not let that wipe real metadata that is already in
        // the library.
        final safeTitle = MetadataPlaceholders.isUnknownTitle(title) &&
                MetadataPlaceholders.isRealTitle(existing.title)
            ? existing.title
            : title;
        final safeArtist = MetadataPlaceholders.isUnknownArtist(artist) &&
                MetadataPlaceholders.isRealArtist(existing.artist)
            ? existing.artist
            : artist;
        final safeAlbum = MetadataPlaceholders.isUnknownAlbum(album) &&
                MetadataPlaceholders.isRealAlbum(existing.album)
            ? existing.album
            : album;
        await _db.transaction(() async {
          await (_db.update(_db.songsTable)
                ..where((t) => t.id.equals(existing.id)))
              .write(
            SongsTableCompanion(
              title: Value(safeTitle),
              artist: Value(safeArtist),
              album: Value(safeAlbum),
              genre: Value(genre),
              year: Value(year),
              trackNumber: Value(trackNumber),
            ),
          );
          // Keep the denormalised album/artist rows in step: the library
          // browse surfaces read titles/names from those tables, so a tag edit
          // would otherwise leave a renamed album/artist showing stale text
          // until the next full MediaStore scan.
          if (existing.albumId != null && existing.albumId! > 0) {
            await (_db.update(_db.albumsTable)
                  ..where((t) => t.id.equals(existing.albumId!)))
                .write(AlbumsTableCompanion(
              title: Value(safeAlbum),
              artist: Value(safeArtist),
            ));
          }
          if (existing.artistId != null && existing.artistId! > 0) {
            await (_db.update(_db.artistsTable)
                  ..where((t) => t.id.equals(existing.artistId!)))
                .write(ArtistsTableCompanion(name: Value(safeArtist)));
          }
        });
      }
      return const Right(null);
    } catch (e) {
      return Left(DatabaseFailure('Failed to update song tags', e));
    }
  }

  @override
  Future<Result<void>> updateAudioQualityBatch(
      List<
              ({
                int songId,
                String path,
                int? sampleRate,
                int? bitDepth,
                int? bitrateKbps,
                String? codec,
                double? loudnessRange
              })>
          updates) async {
    if (updates.isEmpty) return const Right(null);
    try {
      await _db.batch((batch) {
        for (final u in updates) {
          final companion = SongsTableCompanion(
            sampleRate: Value(u.sampleRate),
            bitDepth: Value(u.bitDepth),
            bitrateKbps: Value(u.bitrateKbps),
            codec: Value(u.codec),
            loudnessRange: Value(u.loudnessRange),
          );
          if (u.path.isNotEmpty) {
            batch.update(
              _db.songsTable,
              companion,
              where: (t) => t.path.equals(u.path),
            );
          } else {
            batch.update(
              _db.songsTable,
              companion,
              where: (t) => t.id.equals(u.songId),
            );
          }
        }
      });
      return const Right(null);
    } catch (e) {
      return Left(DatabaseFailure('Failed to batch update audio quality', e));
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
  Stream<Result<List<GenreItem>>> watchGenres({
    List<String> excludedFolders = const [],
  }) {
    try {
      final countExp = _db.songsTable.id.count();
      final query = _db.selectOnly(_db.songsTable)
        ..addColumns([_db.songsTable.genre, countExp])
        ..where(_db.songsTable.genre.isNotNull() &
            _db.songsTable.genre.equals('').not() &
            _db.songsTable.isMissing.equals(false) &
            _db.songsTable.path.like('ytmusic://%').not() &
            (_db.songsTable.cueFile.isNull() |
                _db.songsTable.cueStartMs.isNotNull()) &
            _notInExcludedFolders(excludedFolders))
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
      }).onResultError((e, st) => Left<AppFailure, List<GenreItem>>(
          DatabaseFailure('Failed to watch genres', e)));
    } catch (e) {
      return Stream.value(Left(DatabaseFailure('Failed to watch genres', e)));
    }
  }

  @override
  Future<Result<List<GenreItem>>> getGenres({
    List<String> excludedFolders = const [],
  }) async {
    try {
      final countExp = _db.songsTable.id.count();
      final query = _db.selectOnly(_db.songsTable)
        ..addColumns([_db.songsTable.genre, countExp])
        ..where(_db.songsTable.genre.isNotNull() &
            _db.songsTable.genre.equals('').not() &
            _db.songsTable.isMissing.equals(false) &
            _db.songsTable.path.like('ytmusic://%').not() &
            (_db.songsTable.cueFile.isNull() |
                _db.songsTable.cueStartMs.isNotNull()) &
            _notInExcludedFolders(excludedFolders))
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
          .onResultError((e, st) => Left<AppFailure, List<SongsTableData>>(
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
  Stream<Result<List<YearItem>>> watchYears({
    List<String> excludedFolders = const [],
  }) {
    try {
      final countExp = _db.songsTable.id.count();
      final query = _db.selectOnly(_db.songsTable)
        ..addColumns([_db.songsTable.year, countExp])
        ..where(_db.songsTable.year.isNotNull() &
            _db.songsTable.year.isBiggerThanValue(0) &
            _db.songsTable.isMissing.equals(false) &
            _db.songsTable.path.like('ytmusic://%').not() &
            (_db.songsTable.cueFile.isNull() |
                _db.songsTable.cueStartMs.isNotNull()) &
            _notInExcludedFolders(excludedFolders))
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
      }).onResultError((e, st) => Left<AppFailure, List<YearItem>>(
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
          .onResultError((e, st) => Left<AppFailure, List<SongsTableData>>(
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
