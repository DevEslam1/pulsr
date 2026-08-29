// lib/core/services/artwork_cache_manager.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
  static const int _maxMemoryItems = 150;

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
    unawaited(_enforceDiskLimit());
  }

  /// Hashes cache key into a safe filesystem name
  String _keyToFileName(String key) {
    final bytes = utf8.encode(key);
    final digest = md5.convert(bytes);
    return 'art_$digest.jpg';
  }

  /// Retrieves artwork bytes from memory cache or persistent disk cache
  Future<Uint8List?> get(String key) async {
    // 1. Check memory cache
    if (_memoryCache.containsKey(key)) {
      final bytes = _memoryCache.remove(key)!;
      _memoryCache[key] = bytes; // LRU refresh
      return bytes;
    }

    // 2. Check disk cache
    try {
      if (_cacheDir == null) await init();
      if (_cacheDir != null && await _cacheDir!.exists()) {
        final file = File(p.join(_cacheDir!.path, _keyToFileName(key)));
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          if (bytes.isNotEmpty) {
            _putMemory(key, bytes);
            // Touch file to update lastModified for LRU eviction
            unawaited(file.setLastModified(DateTime.now()).catchError((_) => file));
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
          unawaited(_enforceDiskLimit());
        }
      }
    } catch (e) {
      debugPrint('[ArtworkCache] Write error: $e');
    }
  }

  void _putMemory(String key, Uint8List bytes) {
    if (_memoryCache.containsKey(key)) {
      _memoryCache.remove(key);
    } else if (_memoryCache.length >= _maxMemoryItems) {
      _memoryCache.remove(_memoryCache.keys.first);
    }
    _memoryCache[key] = bytes;
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

  /// Automatic LRU eviction: if disk cache exceeds [_maxCacheSizeMb], evicts oldest files
  Future<void> _enforceDiskLimit() async {
    if (_isCleaning) return;
    _isCleaning = true;

    try {
      if (_cacheDir == null || !await _cacheDir!.exists()) return;
      final maxBytes = _maxCacheSizeMb * 1024 * 1024;
      final entities = (await _cacheDir!.list(followLinks: false).toList())
          .whereType<File>()
          .toList();

      int currentSize = 0;
      final fileList = <({File file, int size, DateTime modified})>[];
      for (final f in entities) {
        final size = await f.length();
        final modified = await f.lastModified();
        currentSize += size;
        fileList.add((file: f, size: size, modified: modified));
      }

      if (currentSize > maxBytes) {
        // Sort oldest first
        fileList.sort((a, b) => a.modified.compareTo(b.modified));
        final targetBytes = (maxBytes * 0.90).toInt(); // trim down to 90%

        for (final item in fileList) {
          if (currentSize <= targetBytes) break;
          try {
            await item.file.delete();
            currentSize -= item.size;
          } catch (_) {}
        }
      }
    } catch (_) {
    } finally {
      _isCleaning = false;
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
