import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/error_logger.dart';

@singleton
class ArtworkCacheManager {
  static final ArtworkCacheManager _instance = ArtworkCacheManager._internal();
  factory ArtworkCacheManager() => _instance;
  ArtworkCacheManager._internal();

  static const String _prefMaxCacheSizeMb = 'setting_max_cache_size_mb';
  static const int defaultMaxCacheSizeMb =
      100; // 100 MB default maximum cache size

  final Map<String, Uint8List> _memoryCache = {};
  final Map<String, WeakReference<Uint8List>> _weakMemoryCache = {};
  static const int _maxMemoryItems = 150;
  static const int _maxMemoryBytes = 35 * 1024 * 1024; // 35 MB memory ceiling
  static const int largePayloadThreshold = 512 * 1024; // 512 KB
  int _currentMemoryBytes = 0;

  Directory? _cacheDir;
  int _maxCacheSizeMb = defaultMaxCacheSizeMb;
  bool _isCleaning = false;

  int get maxCacheSizeMb => _maxCacheSizeMb;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _maxCacheSizeMb =
          prefs.getInt(_prefMaxCacheSizeMb) ?? defaultMaxCacheSizeMb;
      final tempDir = await getTemporaryDirectory();
      _cacheDir = Directory(p.join(tempDir.path, 'artwork_cache'));
      if (!await _cacheDir!.exists()) {
        await _cacheDir!.create(recursive: true);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to initialize ArtworkCacheManager',
          error: e, stackTrace: st, category: 'ArtworkCache');
    }
  }

  Future<void> setMaxCacheSizeMb(int mb) async {
    _maxCacheSizeMb = mb;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefMaxCacheSizeMb, mb);
    _enforceDiskLimit();
  }

  /// Hashes cache key into a safe filesystem name
  String _keyToFileName(String key) {
    final bytes = utf8.encode(key);
    final digest = md5.convert(bytes);
    return 'art_$digest.jpg';
  }

  /// Retrieves artwork bytes from memory cache or persistent disk cache
  Future<Uint8List?> get(String key) async {
    // 1. Check memory cache (strong)
    if (_memoryCache.containsKey(key)) {
      final bytes = _memoryCache.remove(key)!;
      _memoryCache[key] = bytes; // LRU refresh
      return bytes;
    }

    // 2. Check weak memory cache for large payloads
    final weak = _weakMemoryCache[key];
    if (weak != null) {
      final target = weak.target;
      if (target != null && target.isNotEmpty) {
        return target;
      }
      _weakMemoryCache.remove(key);
    }

    // 3. Check disk cache
    try {
      if (_cacheDir == null) await init();
      if (_cacheDir != null && await _cacheDir!.exists()) {
        final file = File(p.join(_cacheDir!.path, _keyToFileName(key)));
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          if (bytes.isNotEmpty) {
            _putMemory(key, bytes);
            // Touch file to update lastModified for LRU eviction
            file.setLastModified(DateTime.now()).catchError((_) => file);
            return bytes;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  int _putCount = 0;
  static const int _enforceEvery = 20;

  /// Stores artwork bytes in both memory and persistent disk cache
  Future<void> put(String key, Uint8List? bytes) async {
    if (bytes == null || bytes.isEmpty) return;

    _putMemory(key, bytes);

    try {
      if (_cacheDir == null) await init();
      if (_cacheDir != null) {
        final file = File(p.join(_cacheDir!.path, _keyToFileName(key)));
        await file.writeAsBytes(bytes, flush: false);
        _putCount++;
        if (_putCount % _enforceEvery == 0) {
          unawaited(_enforceDiskLimit().catchError((e, st) {
            ErrorLogger.log('Failed to enforce disk limit in ArtworkCacheManager',
                error: e, stackTrace: st, category: 'ArtworkCacheManager');
          }));
        }
      }
    } catch (e) {
      debugPrint('[ArtworkCache] Write error: $e');
    }
  }

  void _putMemory(String key, Uint8List bytes) {
    if (bytes.lengthInBytes > largePayloadThreshold) {
      _weakMemoryCache[key] = WeakReference(bytes);
      return;
    }

    if (_memoryCache.containsKey(key)) {
      final old = _memoryCache.remove(key)!;
      _currentMemoryBytes -= old.lengthInBytes;
    }
    while (_memoryCache.isNotEmpty &&
        (_memoryCache.length >= _maxMemoryItems ||
            _currentMemoryBytes + bytes.lengthInBytes > _maxMemoryBytes)) {
      final firstKey = _memoryCache.keys.first;
      final removed = _memoryCache.remove(firstKey);
      if (removed != null) {
        _currentMemoryBytes -= removed.lengthInBytes;
      }
    }
    _memoryCache[key] = bytes;
    _currentMemoryBytes += bytes.lengthInBytes;
  }

  /// Calculates total disk cache size in bytes
  Future<int> getDiskCacheSizeBytes() async {
    try {
      if (_cacheDir == null) await init();
      if (_cacheDir == null || !await _cacheDir!.exists()) return 0;
      int total = 0;
      final entities = await _cacheDir!.list(followLinks: false).toList();
      for (final entity in entities) {
        if (entity is File) {
          total += await entity.length();
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// Clears both in-memory and disk cache
  Future<void> clearAllCache() async {
    _memoryCache.clear();
    _weakMemoryCache.clear();
    _currentMemoryBytes = 0;
    try {
      if (_cacheDir == null) await init();
      if (_cacheDir != null && await _cacheDir!.exists()) {
        final entities = await _cacheDir!.list(followLinks: false).toList();
        for (final entity in entities) {
          if (entity is File) {
            await entity.delete().catchError((_) => entity);
          }
        }
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to clear artwork cache',
          error: e, stackTrace: st, category: 'ArtworkCache');
    }
  }

  /// Automatic LRU eviction executed in a background isolate to keep UI frame-rate fluid.
  Future<void> _enforceDiskLimit() async {
    if (_isCleaning) return;
    _isCleaning = true;

    try {
      if (_cacheDir == null || !await _cacheDir!.exists()) return;
      final maxBytes = _maxCacheSizeMb * 1024 * 1024;
      final dirPath = _cacheDir!.path;

      await Isolate.run(() {
        final dir = Directory(dirPath);
        if (!dir.existsSync()) return;
        final entities =
            dir.listSync(followLinks: false).whereType<File>().toList();

        int currentSize = 0;
        final fileList = <({File file, int size, int modifiedMs})>[];
        for (final f in entities) {
          try {
            final stat = f.statSync();
            currentSize += stat.size;
            fileList.add((
              file: f,
              size: stat.size,
              modifiedMs: stat.modified.millisecondsSinceEpoch,
            ));
          } catch (_) {}
        }

        if (currentSize > maxBytes) {
          // Sort oldest first
          fileList.sort((a, b) => a.modifiedMs.compareTo(b.modifiedMs));
          final targetBytes = (maxBytes * 0.90).toInt(); // trim down to 90%

          for (final item in fileList) {
            if (currentSize <= targetBytes) break;
            try {
              item.file.deleteSync();
              currentSize -= item.size;
            } catch (_) {}
          }
        }
      });
    } catch (e, st) {
      ErrorLogger.log('Failed to enforce disk limit in background isolate',
          error: e, stackTrace: st, category: 'ArtworkCacheManager');
    } finally {
      _isCleaning = false;
    }
  }

  /// Prefetches artwork for a list of cache keys or URLs in the background.
  Future<void> prefetch(List<String> keys) async {
    for (final key in keys) {
      if (key.isEmpty || _memoryCache.containsKey(key)) continue;
      try {
        await get(key);
      } catch (_) {}
    }
  }

  /// Returns a low-quality, compressed URL for online artworks (reduces size from 1MB+ down to ~15KB)
  static String toLowQualityArtworkUrl(String url,
      {int width = 200, int height = 200}) {
    var transformed = url;
    if (transformed.contains('googleusercontent.com') ||
        transformed.contains('ggpht.com')) {
      final sizePattern = RegExp(r'=(?:w\d+-h\d+|s\d+)[^?]*');
      if (sizePattern.hasMatch(transformed)) {
        transformed =
            transformed.replaceAll(sizePattern, '=w$width-h$height-l80-rj');
      } else {
        transformed = '$transformed=w$width-h$height-l80-rj';
      }
    } else if (transformed.contains('ytimg.com')) {
      // Use standard default/hqdefault thumbnail instead of maxresdefault for low memory
      transformed =
          transformed.replaceAll('maxresdefault.jpg', 'hqdefault.jpg');
    }
    return transformed;
  }
}
