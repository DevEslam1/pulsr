import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../constants/channels.dart';
import '../utils/error_logger.dart';

/// Owns the download scratch-file layout in the cache directory.
class YtDownloadArtifactStore {
  static const Duration orphanMaxAge = Duration(minutes: 10);
  static const MethodChannel _channel = MethodChannel(PulsrChannels.ytDownload);

  /// Checks preflight storage space against [requiredSpace] bytes.
  /// Returns false only when the platform positively reports insufficient space.
  static Future<bool> hasFreeDiskSpace(int requiredSpace) async {
    try {
      final freeBytes = await _channel.invokeMethod<int>('getFreeDiskSpace');
      if (freeBytes != null && freeBytes > 0) {
        const minSafetyBytes = 20 * 1024 * 1024;
        if (freeBytes < minSafetyBytes || freeBytes < requiredSpace) {
          return false;
        }
      }
    } catch (_) {
      // Best-effort: failure intentionally ignored on this non-critical path.
    }
    return true;
  }

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
            name.startsWith('ytdl_$id.') ||
            name.startsWith('ytdl_art_$id.') ||
            name.startsWith('ytdl_art_${id}_'))) {
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
      final artDot = 'ytdl_art_$videoId.';
      final artRun = 'ytdl_art_${videoId}_';
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (!name.startsWith(audio) &&
            !name.startsWith(artDot) &&
            !name.startsWith(artRun)) {
          continue;
        }
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

  /// Looks up a previously committed scratch download for [videoId] so a retry
  /// after post-download cancellation reuses the verified body on disk.
  static Future<({File file, String ext})?> findCommittedTemp(
    Directory dir,
    String videoId,
    String preferredExt, {
    int? minExpectedBytes,
    String? quality,
    String? container,
  }) async {
    final candidates = <String>[
      preferredExt,
      for (final c in const ['m4a', 'webm', 'mp3', 'opus'])
        if (c != preferredExt) c,
    ];
    for (final candExt in candidates) {
      final cand = File(p.join(dir.path, 'ytdl_$videoId.$candExt'));
      final stamp = File('${cand.path}.committed.stamp');
      try {
        if (!await cand.exists() || !await stamp.exists()) continue;
        final rawStamp = (await stamp.readAsString()).trim();
        final parts = rawStamp.split('|');
        if (parts.isEmpty || parts[0] != videoId) continue;
        final len = await cand.length();
        if (len < 1024) continue;
        if (parts.length >= 4) {
          final stampedQuality = parts[1];
          final stampedContainer = parts[2];
          final stampedSize = int.tryParse(parts[3]);
          if (quality != null &&
              stampedQuality.isNotEmpty &&
              stampedQuality != quality) {
            continue;
          }
          if (container != null &&
              stampedContainer.isNotEmpty &&
              stampedContainer != container) {
            continue;
          }
          if (stampedSize != null && stampedSize > 0 && len != stampedSize) {
            continue;
          }
        }
        if (minExpectedBytes != null && len < minExpectedBytes) continue;
        return (file: cand, ext: candExt);
      } catch (_) {
        // Best-effort: failure intentionally ignored on this non-critical path.
      }
    }
    return null;
  }

  /// Writes a committed-body marker next to [temp] so post-download
  /// cancellation does not discard an already-verified audio payload.
  static Future<void> markCommitted(
    File temp,
    String videoId, {
    String? quality,
    String? container,
    int? sizeBytes,
  }) async {
    try {
      final resolvedSize =
          sizeBytes ?? (await temp.exists() ? await temp.length() : 0);
      final stampValue =
          (quality != null || container != null || sizeBytes != null)
              ? '$videoId|${quality ?? ''}|${container ?? ''}|$resolvedSize'
              : videoId;
      await File('${temp.path}.committed.stamp').writeAsString(stampValue);
    } catch (_) {
      // Best-effort: failure intentionally ignored on this non-critical path.
    }
  }

  /// Best-effort deletion of scratch files in `_executeDownload`'s `finally`.
  static Future<void> cleanupScratch({
    File? temp,
    File? tempArt,
    Future<String?>? artworkFuture,
    bool wasCanceled = false,
    bool Function()? isCurrentRun,
  }) async {
    Future<void> deleteArtFromFuture(Future<String?> future) async {
      try {
        final resolvedArtPath = await future.timeout(
          const Duration(seconds: 2),
          onTimeout: () => null,
        );
        if (resolvedArtPath != null && (isCurrentRun?.call() ?? true)) {
          final resolvedArtFile = File(resolvedArtPath);
          if (await resolvedArtFile.exists()) {
            await resolvedArtFile.delete().catchError((_) => resolvedArtFile);
          }
        }
      } catch (_) {
        // Best-effort: failure intentionally ignored on this non-critical path.
      }
    }

    if (artworkFuture != null) {
      await deleteArtFromFuture(artworkFuture);
    }
    if (temp != null) {
      for (final file in [temp, File('${temp.path}.committed.stamp')]) {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {
          // Best-effort: failure intentionally ignored on this non-critical path.
        }
      }
    }
    if (tempArt != null) {
      try {
        if (await tempArt.exists()) await tempArt.delete();
      } catch (_) {
        // Best-effort: failure intentionally ignored on this non-critical path.
      }
    }
  }
}
