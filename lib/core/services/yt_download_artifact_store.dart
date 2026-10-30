import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../constants/channels.dart';
import '../utils/error_logger.dart';

/// Owns the download scratch-file layout in the cache directory.
class YtDownloadArtifactStore {
  static const Duration orphanMaxAge = Duration(minutes: 10);
  static const MethodChannel _channel = MethodChannel(PulsrChannels.ytDownload);

  /// Removes a just-saved MediaStore file/row after the library hand-off
  /// failed, so a failed reconcile cannot leave an orphan that a later scan
  /// imports as a duplicate.
  static Future<void> deleteSavedMedia({
    required String path,
    String? contentUri,
  }) async {
    try {
      await _channel.invokeMethod<Object?>('deleteFromMusic', {
        'path': path,
        'contentUri': contentUri,
      });
    } catch (e, st) {
      ErrorLogger.log('Failed to delete rejected download file',
          error: e, stackTrace: st, category: 'download');
    }
  }

  /// Removes stale `ytdl_*` bodies, chunks, stamps and artwork covers while
  /// protecting files owned by active, queued or explicitly protected ids.
  static Future<void> sweepOrphans(
    Directory dir, {
    required Set<String> busyVideoIds,
    Set<String>? activePartNames,
  }) async {
    try {
      if (!await dir.exists()) return;

      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (!name.startsWith('ytdl_')) continue;
        if (activePartNames != null && activePartNames.contains(name)) continue;
        if (busyVideoIds.any((id) =>
            name.startsWith('ytdl_$id.') || name.startsWith('ytdl_art_$id.'))) {
          continue;
        }
        try {
          final stat = await entity.stat();
          if (DateTime.now().difference(stat.modified) > orphanMaxAge) {
            await entity.delete();
          }
        } catch (_) {
          // Best-effort: failure intentionally ignored on this non-critical path.
        }
      }
    } catch (_) {
      // Best-effort: failure intentionally ignored on this non-critical path.
    }
  }

  /// Removes the sequential `.part` and its resume stamp after a parallel
  /// merge committed, so a later retry cannot resume stale bytes.
  static Future<void> deleteLegacySequentialPart(String destPath) async {
    for (final path in ['$destPath.part', '$destPath.part.stamp']) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (e, st) {
        ErrorLogger.log('Failed to remove superseded download part $path',
            error: e, stackTrace: st, category: 'download');
      }
    }
  }

  /// Removes every scratch file for [videoId], with a dot boundary so deleting
  /// `abc` cannot also delete the artifacts of `abcdef`.
  static Future<void> deleteFor(Directory dir, String videoId) async {
    try {
      if (!await dir.exists()) return;
      final audio = 'ytdl_$videoId.';
      final art = 'ytdl_art_$videoId.';
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (!name.startsWith(audio) && !name.startsWith(art)) continue;
        try {
          await entity.delete();
        } catch (_) {
          // Best-effort: failure intentionally ignored on this non-critical path.
        }
      }
    } catch (_) {
      // Best-effort: failure intentionally ignored on this non-critical path.
    }
  }
}
