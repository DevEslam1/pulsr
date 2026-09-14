// lib/core/services/ytm_cache_manager.dart
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/error_logger.dart';

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

  String getHashForVideoId(String videoId) {
    return sha256.convert(utf8.encode(videoId)).toString();
  }

  /// Audio containers the stream cache may hold.
  static const List<String> cacheExtensions = ['m4a', 'webm'];

  /// Every extension any version of this app may have written, for cleanup.
  static const List<String> allCacheExtensions = ['m4a', 'webm', 'opus', 'mp4'];

  /// Qualities the streaming setting can name.
  static const List<String> cacheQualities = ['high', 'medium', 'low'];

  /// File name for one cache slot.
  ///
  /// F9: the slot is quality-keyed. The in-memory URL cache always was, but the
  /// on-disk body was keyed on the video id alone, so a body cached for one
  /// streaming quality could be served for another. `high` keeps the historical
  /// un-keyed name so bodies written before this keying are still found.
  static String cacheFileName(String hash, String quality, String ext) {
    final q = quality.trim().toLowerCase();
    return q.isEmpty || q == 'high' ? '$hash.$ext' : '$hash.$q.$ext';
  }

  /// Every name any version may have used for [hash]. Cleanup sweeps only.
  static List<String> allCacheFileNames(String hash) {
    final names = <String>{};
    for (final ext in allCacheExtensions) {
      names.add('$hash.$ext');
      for (final q in cacheQualities) {
        names.add('$hash.$q.$ext');
      }
    }
    return names.toList();
  }

  /// Returns the cached audio file for [videoId] at [quality] if it exists on
  /// disk and is non-empty (>100KB).
  Future<File?> getCachedAudioFile(String videoId,
      {String quality = 'high'}) async {
    try {
      final dir = await getCacheDirectory();
      final hash = getHashForVideoId(videoId);
      for (final ext in cacheExtensions) {
        final f = File(p.join(dir.path, cacheFileName(hash, quality, ext)));
        if (await f.exists()) {
          final len = await f.length();
          if (len > 100 * 1024) {
            // Minimum 100KB for valid audio stream
            // Update last modified time for LRU
            try {
              await f.setLastModified(DateTime.now());
            } catch (_) {}
            return f;
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
