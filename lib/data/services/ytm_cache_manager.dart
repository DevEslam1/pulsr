// lib/core/services/ytm_cache_manager.dart
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utils/error_logger.dart';

@singleton
class YtmCacheManager {
  static const String keyMaxCacheSizeMb = 'setting_stream_cache_max_mb';
  static const int defaultMaxCacheSizeMb = 1024; // 1 GB default

  Future<Directory> getCacheDirectory() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'ytm_cache'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String getHashForVideoId(String videoId, {String? quality}) {
    final key = quality != null ? '$videoId-$quality' : videoId;
    return sha256.convert(utf8.encode(key)).toString();
  }

  /// Returns the cached audio file for [videoId] if it exists on disk and is non-empty (>50KB).
  Future<File?> getCachedAudioFile(String videoId, {String? quality}) async {
    try {
      final dir = await getCacheDirectory();
      final hash = getHashForVideoId(videoId, quality: quality);
      // Try quality-specific hash first, fallback to legacy hash for back-compat
      final hashes = quality != null ? [hash, getHashForVideoId(videoId)] : [hash];
      for (final h in hashes) {
        for (final ext in const ['m4a', 'webm']) {
          final f = File(p.join(dir.path, '$h.$ext'));
          if (await f.exists()) {
            final len = await f.length();
            if (len > 50 * 1024) {
              return f;
            }
          }
        }
      }
    } catch (e, st) {
      ErrorLogger.log('Error checking cached audio for $videoId',
          error: e, stackTrace: st, category: 'YtmCacheManager');
    }
    return null;
  }

  /// Returns total disk space used by stream cache in bytes.
  Future<int> getCacheSizeBytes() async {
    try {
      final dir = await getCacheDirectory();
      if (!await dir.exists()) return 0;
      int total = 0;
      final entities = await dir.list().toList();
      for (final entity in entities) {
        if (entity is File) {
          total += await entity.length();
        }
      }
      return total;
    } catch (e) {
      return 0;
    }
  }

  /// Clears all cached stream files from disk.
  Future<void> clearCache() async {
    try {
      final dir = await getCacheDirectory();
      if (await dir.exists()) {
        final entities = await dir.list().toList();
        for (final entity in entities) {
          if (entity is File) {
            try {
              await entity.delete();
            } catch (_) {}
          }
        }
      }
    } catch (e, st) {
      ErrorLogger.log('Error clearing stream cache',
          error: e, stackTrace: st, category: 'YtmCacheManager');
    }
  }

  /// Prunes oldest accessed files if total cache exceeds user's configured limit.
  Future<void> pruneIfExceedsLimit() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final maxMb = prefs.getInt(keyMaxCacheSizeMb) ?? defaultMaxCacheSizeMb;
      final maxBytes = maxMb * 1024 * 1024;

      final dir = await getCacheDirectory();
      if (!await dir.exists()) return;

      final entities = (await dir.list().toList()).whereType<File>().toList();
      int totalSize = 0;
      final fileList = <({File file, int size, DateTime modified})>[];
      for (final f in entities) {
        final size = await f.length();
        final modified = await f.lastModified();
        totalSize += size;
        fileList.add((file: f, size: size, modified: modified));
      }

      if (totalSize <= maxBytes) return;

      // Sort oldest modified first
      fileList.sort((a, b) => a.modified.compareTo(b.modified));

      for (final item in fileList) {
        if (totalSize <= maxBytes * 0.85) break; // Reduce to 85% of limit
        try {
          await item.file.delete();
          totalSize -= item.size;
        } catch (_) {}
      }
    } catch (e, st) {
      ErrorLogger.log('Error pruning stream cache',
          error: e, stackTrace: st, category: 'YtmCacheManager');
    }
  }
}

