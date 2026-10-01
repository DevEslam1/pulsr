// lib/data/db/database_health_check.dart
import 'dart:async';
import 'app_database.dart';
import '../../core/utils/error_logger.dart';

/// Diagnostics report capturing the physical and relational integrity of the SQLite database.
class DatabaseHealthReport {
  final bool isHealthy;
  final List<String> integrityIssues;
  final List<String> foreignKeyViolations;
  final int totalSongs;
  final int totalPlaylists;
  final int totalHistoryEntries;
  final int databaseSizeBytes;
  final bool ftsHealthy;

  const DatabaseHealthReport({
    required this.isHealthy,
    required this.integrityIssues,
    required this.foreignKeyViolations,
    required this.totalSongs,
    required this.totalPlaylists,
    required this.totalHistoryEntries,
    required this.databaseSizeBytes,
    required this.ftsHealthy,
  });

  Map<String, dynamic> toMap() => {
        'isHealthy': isHealthy,
        'integrityIssues': integrityIssues,
        'foreignKeyViolations': foreignKeyViolations,
        'totalSongs': totalSongs,
        'totalPlaylists': totalPlaylists,
        'totalHistoryEntries': totalHistoryEntries,
        'databaseSizeBytes': databaseSizeBytes,
        'ftsHealthy': ftsHealthy,
      };

  @override
  String toString() =>
      'DatabaseHealthReport(healthy: $isHealthy, songs: $totalSongs, playlists: $totalPlaylists, size: ${databaseSizeBytes ~/ 1024} KB, fts: $ftsHealthy)';
}

/// Comprehensive health inspection engine for [AppDatabase].
class DatabaseHealthCheck {
  final AppDatabase _db;

  DatabaseHealthCheck(this._db);

  /// Performs integrity check, foreign key verification, row counts, and FTS health audit.
  Future<DatabaseHealthReport> checkHealth() async {
    final integrityIssues = <String>[];
    final foreignKeyViolations = <String>[];
    var isHealthy = true;

    // 1. PRAGMA integrity_check
    try {
      final rows = await _db.customSelect('PRAGMA integrity_check;').get();
      for (final row in rows) {
        final res = row.data.values.first?.toString() ?? '';
        if (res.toLowerCase() != 'ok') {
          integrityIssues.add(res);
          isHealthy = false;
        }
      }
    } catch (e, st) {
      integrityIssues.add('integrity_check failed: $e');
      isHealthy = false;
      ErrorLogger.log('integrity_check failed',
          error: e, stackTrace: st, category: 'Database');
    }

    // 2. PRAGMA foreign_key_check
    try {
      final fkRows = await _db.customSelect('PRAGMA foreign_key_check;').get();
      for (final row in fkRows) {
        foreignKeyViolations.add(row.data.toString());
        isHealthy = false;
      }
    } catch (e, st) {
      foreignKeyViolations.add('foreign_key_check failed: $e');
      ErrorLogger.log('foreign_key_check failed',
          error: e, stackTrace: st, category: 'Database');
    }

    // 3. Row counts & Size
    var totalSongs = 0;
    var totalPlaylists = 0;
    var totalHistoryEntries = 0;
    var dbSizeBytes = 0;

    try {
      final songRow = await _db
          .customSelect('SELECT COUNT(*) AS c FROM songs;')
          .getSingleOrNull();
      totalSongs = (songRow?.data['c'] as num?)?.toInt() ?? 0;

      final playlistRow = await _db
          .customSelect('SELECT COUNT(*) AS c FROM playlists;')
          .getSingleOrNull();
      totalPlaylists = (playlistRow?.data['c'] as num?)?.toInt() ?? 0;

      final historyRow = await _db
          .customSelect('SELECT COUNT(*) AS c FROM play_history;')
          .getSingleOrNull();
      totalHistoryEntries = (historyRow?.data['c'] as num?)?.toInt() ?? 0;

      final pageCountRow =
          await _db.customSelect('PRAGMA page_count;').getSingleOrNull();
      final pageSizeRow =
          await _db.customSelect('PRAGMA page_size;').getSingleOrNull();
      final pages = (pageCountRow?.data.values.first as num?)?.toInt() ?? 0;
      final size = (pageSizeRow?.data.values.first as num?)?.toInt() ?? 4096;
      dbSizeBytes = pages * size;
    } catch (e) {
      ErrorLogger.log('Failed to fetch DB stats',
          error: e, category: 'Database');
    }

    // 4. FTS health verification
    var ftsHealthy = !AppDatabase.ftsRebuildFailed;
    if (ftsHealthy) {
      try {
        final ftsCheck = await _db
            .customSelect('SELECT COUNT(*) AS c FROM songs_fts;')
            .getSingleOrNull();
        if (ftsCheck == null) {
          ftsHealthy = false;
        }
      } catch (_) {
        ftsHealthy = false;
      }
    }

    return DatabaseHealthReport(
      isHealthy:
          isHealthy && integrityIssues.isEmpty && foreignKeyViolations.isEmpty,
      integrityIssues: integrityIssues,
      foreignKeyViolations: foreignKeyViolations,
      totalSongs: totalSongs,
      totalPlaylists: totalPlaylists,
      totalHistoryEntries: totalHistoryEntries,
      databaseSizeBytes: dbSizeBytes,
      ftsHealthy: ftsHealthy,
    );
  }
}

/// Results returned after running [DatabaseOptimizer.optimize].
class DatabaseOptimizationReport {
  final int pagesBefore;
  final int pagesAfter;
  final int bytesReclaimed;
  final Duration duration;
  final bool ftsRebuilt;

  const DatabaseOptimizationReport({
    required this.pagesBefore,
    required this.pagesAfter,
    required this.bytesReclaimed,
    required this.duration,
    required this.ftsRebuilt,
  });

  Map<String, dynamic> toMap() => {
        'pagesBefore': pagesBefore,
        'pagesAfter': pagesAfter,
        'bytesReclaimed': bytesReclaimed,
        'durationMs': duration.inMilliseconds,
        'ftsRebuilt': ftsRebuilt,
      };

  @override
  String toString() =>
      'DatabaseOptimizationReport(reclaimed: ${bytesReclaimed ~/ 1024} KB, ftsRebuilt: $ftsRebuilt, took: ${duration.inMilliseconds}ms)';
}

/// Executes VACUUM, ANALYZE, and FTS index rebuilding to optimize SQLite performance.
class DatabaseOptimizer {
  final AppDatabase _db;

  DatabaseOptimizer(this._db);

  /// Performs full database optimization:
  /// - Executes `ANALYZE` to refresh SQLite query planner statistics.
  /// - Rebuilds `songs_fts` FTS5 index if [rebuildFts] is true.
  /// - Executes `VACUUM` to defragment SQLite pages and release unused space.
  Future<DatabaseOptimizationReport> optimize({bool rebuildFts = true}) async {
    final sw = Stopwatch()..start();

    int pageSize = 4096;
    int pagesBefore = 0;
    try {
      final sizeRow =
          await _db.customSelect('PRAGMA page_size;').getSingleOrNull();
      final countRow =
          await _db.customSelect('PRAGMA page_count;').getSingleOrNull();
      pageSize = (sizeRow?.data.values.first as num?)?.toInt() ?? 4096;
      pagesBefore = (countRow?.data.values.first as num?)?.toInt() ?? 0;
    } catch (_) {}

    // 1. ANALYZE query planner statistics
    try {
      await _db.customStatement('ANALYZE;');
    } catch (e, st) {
      ErrorLogger.log('ANALYZE failed',
          error: e, stackTrace: st, category: 'Database');
    }

    // 2. Rebuild FTS5 search index
    var ftsSuccess = false;
    if (rebuildFts) {
      try {
        ftsSuccess = await _db.repairFtsIndex(force: true);
      } catch (e, st) {
        ErrorLogger.log('FTS rebuild during optimization failed',
            error: e, stackTrace: st, category: 'Database');
      }
    }

    // 3. VACUUM to reclaim free pages
    try {
      await _db.customStatement('VACUUM;');
    } catch (e, st) {
      ErrorLogger.log('VACUUM failed',
          error: e, stackTrace: st, category: 'Database');
    }

    int pagesAfter = pagesBefore;
    try {
      final countAfterRow =
          await _db.customSelect('PRAGMA page_count;').getSingleOrNull();
      pagesAfter =
          (countAfterRow?.data.values.first as num?)?.toInt() ?? pagesBefore;
    } catch (_) {}

    sw.stop();
    final bytesReclaimed =
        (pagesBefore - pagesAfter).clamp(0, 1 << 30) * pageSize;

    return DatabaseOptimizationReport(
      pagesBefore: pagesBefore,
      pagesAfter: pagesAfter,
      bytesReclaimed: bytesReclaimed,
      duration: sw.elapsed,
      ftsRebuilt: ftsSuccess,
    );
  }
}

/// Validation result produced by [DatabaseMigrationValidator].
class MigrationValidationResult {
  final bool isValid;
  final int currentVersion;
  final int expectedVersion;
  final List<String> missingTables;
  final List<String> missingColumns;
  final List<String> missingIndexes;

  const MigrationValidationResult({
    required this.isValid,
    required this.currentVersion,
    required this.expectedVersion,
    required this.missingTables,
    required this.missingColumns,
    required this.missingIndexes,
  });

  Map<String, dynamic> toMap() => {
        'isValid': isValid,
        'currentVersion': currentVersion,
        'expectedVersion': expectedVersion,
        'missingTables': missingTables,
        'missingColumns': missingColumns,
        'missingIndexes': missingIndexes,
      };

  @override
  String toString() =>
      'MigrationValidationResult(valid: $isValid, version: $currentVersion/$expectedVersion, missingTables: $missingTables, missingColumns: $missingColumns, missingIndexes: $missingIndexes)';
}

/// Validates that database migrations produced the complete, expected schema.
class DatabaseMigrationValidator {
  final AppDatabase _db;

  DatabaseMigrationValidator(this._db);

  static const List<String> requiredTables = [
    'songs',
    'albums',
    'artists',
    'playlists',
    'playlist_entries',
    'play_history',
    'queue_items',
    'excluded_folders',
  ];

  static const Map<String, List<String>> requiredColumns = {
    'songs': [
      'id',
      'title',
      'artist',
      'album',
      'duration_ms',
      'path',
      'genre',
      'is_favorite',
      'is_missing',
      'is_downloaded',
      'sample_rate',
      'bit_depth',
      'bitrate_kbps',
      'codec',
      'source',
      'remote_id',
      'cue_start_ms',
      'cue_end_ms',
      'cue_file',
      'replay_gain_track',
      'loudness_range',
    ],
    'playlists': ['id', 'name', 'created_at', 'updated_at'],
    'playlist_entries': ['id', 'playlist_id', 'song_id', 'order_index'],
    'play_history': ['id', 'song_id', 'played_at'],
  };

  static const List<String> requiredIndexes = [
    'idx_songs_title',
    'idx_songs_artist',
    'idx_songs_path',
    'idx_songs_path_cue',
    'idx_playlist_entries_unique',
  ];

  /// Checks user_version, verifies tables, required columns, and critical indexes.
  Future<MigrationValidationResult> validateSchema() async {
    int currentVersion = 0;
    try {
      final verRow =
          await _db.customSelect('PRAGMA user_version;').getSingleOrNull();
      currentVersion = (verRow?.data.values.first as num?)?.toInt() ?? 0;
    } catch (_) {}

    final missingTables = <String>[];
    final missingColumns = <String>[];
    final missingIndexes = <String>[];

    // 1. Check tables
    final existingTables = <String>{};
    try {
      final tableRows = await _db
          .customSelect("SELECT name FROM sqlite_master WHERE type='table';")
          .get();
      for (final r in tableRows) {
        final name = r.data['name']?.toString();
        if (name != null) existingTables.add(name);
      }
    } catch (_) {}

    for (final tbl in requiredTables) {
      if (!existingTables.contains(tbl)) {
        missingTables.add(tbl);
      }
    }

    // 2. Check columns
    for (final entry in requiredColumns.entries) {
      final tbl = entry.key;
      if (!existingTables.contains(tbl)) continue;

      try {
        final colRows =
            await _db.customSelect('PRAGMA table_info($tbl);').get();
        final existingCols = colRows
            .map((r) => r.data['name']?.toString())
            .whereType<String>()
            .toSet();
        for (final reqCol in entry.value) {
          if (!existingCols.contains(reqCol)) {
            missingColumns.add('$tbl.$reqCol');
          }
        }
      } catch (_) {}
    }

    // 3. Check indexes
    final existingIndexes = <String>{};
    try {
      final indexRows = await _db
          .customSelect("SELECT name FROM sqlite_master WHERE type='index';")
          .get();
      for (final r in indexRows) {
        final name = r.data['name']?.toString();
        if (name != null) existingIndexes.add(name);
      }
    } catch (_) {}

    for (final idx in requiredIndexes) {
      if (!existingIndexes.contains(idx)) {
        missingIndexes.add(idx);
      }
    }

    final isValid = currentVersion == _db.schemaVersion &&
        missingTables.isEmpty &&
        missingColumns.isEmpty &&
        missingIndexes.isEmpty;

    return MigrationValidationResult(
      isValid: isValid,
      currentVersion: currentVersion,
      expectedVersion: _db.schemaVersion,
      missingTables: missingTables,
      missingColumns: missingColumns,
      missingIndexes: missingIndexes,
    );
  }
}
