import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';

import '../../core/constants/audio_formats.dart';
import '../../core/utils/error_logger.dart';
import '../../core/utils/local_delete_guard.dart';
import '../db/app_database.dart';

/// Single place that removes a library row and the file behind it.
///
/// The download repository, the scanner, and reconciliation all need the same
/// tombstone semantics: keep the row but mark it missing so playlist, history,
/// and queue references survive, and remove the MediaStore row before the file
/// so the next scan cannot resurrect a track pointing at deleted bytes.
class LibraryMaintenanceService {
  LibraryMaintenanceService({
    required AppDatabase? Function() database,
    required MethodChannel channel,
    Future<List<String>> Function()? allowedDeleteRoots,
  })  : _database = database,
        _channel = channel,
        _allowedDeleteRoots = allowedDeleteRoots ?? allowedAppDeleteRoots;

  final AppDatabase? Function() _database;
  final MethodChannel _channel;

  /// Roots a direct `File.delete()` may touch. Injectable so tests can grant a
  /// sandbox directory without mocking path_provider.
  final Future<List<String>> Function() _allowedDeleteRoots;

  static Future<void> tombstoneSong(AppDatabase db, int songId) {
    return (db.update(db.songsTable)..where((t) => t.id.equals(songId)))
        .write(const SongsTableCompanion(isMissing: Value(true)));
  }

  Future<void> removeDownloadedArtifacts({
    int? localSongId,
    String? filePath,
    String? contentUri,
  }) async {
    var resolvedPath = filePath;
    final db = _database();
    if (localSongId != null && db != null) {
      try {
        final song = await (db.select(db.songsTable)
              ..where((t) => t.id.equals(localSongId)))
            .getSingleOrNull();
        if (song != null) {
          resolvedPath ??= song.path;
          await (db.update(db.songsTable)
                ..where((t) => t.id.equals(localSongId)))
              .write(const SongsTableCompanion(
            isMissing: Value(true),
            isDownloaded: Value(false),
          ));
        }
      } catch (e, st) {
        ErrorLogger.log('Failed to tombstone deleted download row',
            error: e, stackTrace: st, category: 'LibraryMaintenance');
      }
    }

    final hasContentUri = contentUri != null && contentUri.isNotEmpty;
    final path = resolvedPath;
    final hasPath = path != null && path.isNotEmpty;
    if (!hasContentUri && !hasPath) return;

    try {
      await _channel.invokeMethod('deleteFromMusic', {
        if (hasPath) 'path': path,
        if (hasContentUri) 'contentUri': contentUri,
      }).timeout(const Duration(seconds: 2));
    } catch (_) {
      // Missing plugin / non-Android / platform did not answer: the direct
      // delete below still runs and must not be held hostage by the channel.
    }

    if (!hasPath ||
        path.startsWith('content:') ||
        path.startsWith('ytmusic://')) {
      return;
    }

    // A download path is untrusted input: it can arrive from a restored task
    // JSON or a stale database row. Only files that resolve inside an
    // app-owned root are deleted directly; everything else is left to the
    // MediaStore request above.
    final file = await resolveDeletableAudioFile(
      path,
      allowedExtensions: AudioFormats.supportedExtensions.toList(),
      roots: await _allowedDeleteRoots(),
      logCategory: 'LibraryMaintenance',
    );
    if (file == null) return;

    try {
      if (await file.exists()) await file.delete();
    } catch (e, st) {
      ErrorLogger.log('Failed to delete downloaded file "$path"',
          error: e, stackTrace: st, category: 'LibraryMaintenance');
    }

    // Partial artifacts sit next to the audio file, so they are covered by the
    // same containment decision.
    for (final suffix in const ['.part', '.parts', '.part.stamp']) {
      try {
        final part = File('${file.path}$suffix');
        if (await part.exists()) await part.delete();
      } catch (e, st) {
        ErrorLogger.log('Failed to delete partial artifact "$suffix"',
            error: e, stackTrace: st, category: 'LibraryMaintenance');
      }
    }
  }
}
