import 'dart:io';

import 'package:path/path.dart' as p;

/// Owns the download scratch-file layout in the cache directory.
class YtDownloadArtifactStore {
  static const Duration orphanMaxAge = Duration(minutes: 10);

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
