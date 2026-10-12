// lib/services/canvas/canvas_cache.dart
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/utils/error_logger.dart';
import 'canvas_artwork.dart';

/// LRU Memory and Disk cache for Canvas videos with a 150 MB disk boundary.
///
/// Prevents redundant downloading when looping short 5-8 second clips over a 3-4 minute song.
class CanvasCache {
  CanvasCache({
    http.Client? client,
    int maxDiskBytes = 150 * 1024 * 1024, // 150 MB
    int maxMemoryEntries = 64,
    String? customCacheDirPath,
  })  : _client = client ?? http.Client(),
        _maxDiskBytes = maxDiskBytes,
        _maxMemoryEntries = maxMemoryEntries,
        _customCacheDirPath = customCacheDirPath;

  final http.Client _client;
  final int _maxDiskBytes;
  final int _maxMemoryEntries;
  final String? _customCacheDirPath;

  // In-memory LRU cache storing CanvasArtwork (or null for negative caching misses).
  final LinkedHashMap<String, CanvasArtwork?> _memoryCache = LinkedHashMap();

  // In-flight download deduplication.
  final Map<String, Future<String?>> _inFlightDownloads = {};

  Directory? _cacheDir;
  final Completer<void> _initCompleter = Completer<void>();
  bool _isInitialized = false;

  /// Ensures cache directory is ready.
  Future<void> init() async {
    if (_isInitialized) return;
    try {
      if (_customCacheDirPath != null) {
        _cacheDir = Directory(_customCacheDirPath!);
      } else {
        final baseDir = await getTemporaryDirectory();
        _cacheDir = Directory(p.join(baseDir.path, 'canvas_cache'));
      }
      if (!await _cacheDir!.exists()) {
        await _cacheDir!.create(recursive: true);
      }
      _isInitialized = true;
      if (!_initCompleter.isCompleted) _initCompleter.complete();
    } catch (e, st) {
      ErrorLogger.log('Failed to initialize CanvasCache directory',
          error: e, stackTrace: st, category: 'CanvasCache');
      if (!_initCompleter.isCompleted) _initCompleter.complete();
    }
  }

  Future<Directory> get _dir async {
    if (!_isInitialized) await init();
    return _cacheDir!;
  }

  // ---------------------------------------------------------------------------
  // Memory Cache
  // ---------------------------------------------------------------------------

  /// Retrieves cached artwork from memory (can be null for negative-cache miss).
  bool hasInMemory(String key) => _memoryCache.containsKey(key);

  CanvasArtwork? getFromMemory(String key) {
    if (!_memoryCache.containsKey(key)) return null;
    // Move to end (most recently used)
    final val = _memoryCache.remove(key);
    _memoryCache[key] = val;
    return val;
  }

  void putInMemory(String key, CanvasArtwork? artwork) {
    if (_memoryCache.containsKey(key)) {
      _memoryCache.remove(key);
    } else if (_memoryCache.length >= _maxMemoryEntries) {
      _memoryCache.remove(_memoryCache.keys.first);
    }
    _memoryCache[key] = artwork;
  }

  void clearMemory() => _memoryCache.clear();

  // ---------------------------------------------------------------------------
  // Disk Cache (150 MB LRU Boundary)
  // ---------------------------------------------------------------------------

  String _urlToFilename(String url) {
    final hash = sha256.convert(utf8.encode(url)).toString().substring(0, 32);
    return '$hash.mp4';
  }

  /// Checks if the video at [videoUrl] is already downloaded on disk.
  Future<String?> getLocalPathIfExists(String videoUrl) async {
    try {
      final dir = await _dir;
      final file = File(p.join(dir.path, _urlToFilename(videoUrl)));
      if (await file.exists() && await file.length() > 0) {
        // Touch file to refresh last accessed time for LRU
        try {
          await file.setLastModified(DateTime.now());
        } catch (_) {}
        return file.path;
      }
    } catch (_) {}
    return null;
  }

  /// Downloads and caches the video file to disk, enforcing the 150 MB LRU boundary.
  Future<String?> getOrDownloadVideo(String videoUrl) async {
    final existing = await getLocalPathIfExists(videoUrl);
    if (existing != null) return existing;

    // Deduplicate concurrent requests for the same URL
    if (_inFlightDownloads.containsKey(videoUrl)) {
      return _inFlightDownloads[videoUrl];
    }

    final downloadFuture = _downloadAndCache(videoUrl);
    _inFlightDownloads[videoUrl] = downloadFuture;

    try {
      final result = await downloadFuture;
      return result;
    } finally {
      _inFlightDownloads.remove(videoUrl);
    }
  }

  Future<String?> _downloadAndCache(String videoUrl) async {
    try {
      final dir = await _dir;
      final targetFile = File(p.join(dir.path, _urlToFilename(videoUrl)));
      final tempFile = File('${targetFile.path}.tmp');

      final uri = Uri.tryParse(videoUrl);
      if (uri == null) return null;

      final request = http.Request('GET', uri)
        ..headers['User-Agent'] =
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

      final response = await _client.send(request).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        return null;
      }

      final sink = tempFile.openWrite();
      await response.stream.pipe(sink);
      await sink.close();

      if (await tempFile.length() == 0) {
        if (await tempFile.exists()) await tempFile.delete();
        return null;
      }

      // Rename atomically
      if (await targetFile.exists()) await targetFile.delete();
      await tempFile.rename(targetFile.path);

      // Enforce 150 MB boundary
      await _evictDiskIfNeeded();

      return targetFile.path;
    } catch (e, st) {
      ErrorLogger.log('Canvas video download failed: $videoUrl',
          error: e, stackTrace: st, category: 'CanvasCache');
      return null;
    }
  }

  /// Evicts oldest accessed files until total size is within [_maxDiskBytes].
  Future<void> _evictDiskIfNeeded() async {
    try {
      final dir = await _dir;
      final entities = dir.listSync();
      final List<_DiskFileEntry> files = [];
      int totalSize = 0;

      for (final e in entities) {
        if (e is File && e.path.endsWith('.mp4')) {
          final stat = e.statSync();
          final size = stat.size;
          totalSize += size;
          files.add(_DiskFileEntry(e, stat.modified, size));
        }
      }

      if (totalSize <= _maxDiskBytes) return;

      // Sort by modified time ascending (oldest first)
      files.sort((a, b) => a.modified.compareTo(b.modified));

      for (final item in files) {
        try {
          if (item.file.existsSync()) {
            final size = item.size;
            item.file.deleteSync();
            totalSize -= size;
          }
        } catch (_) {}
        if (totalSize <= _maxDiskBytes) break;
      }
    } catch (e, st) {
      ErrorLogger.log('Canvas cache LRU eviction error',
          error: e, stackTrace: st, category: 'CanvasCache');
    }
  }

  /// Calculates total size of all cached video files on disk.
  Future<int> currentDiskUsageBytes() async {
    try {
      final dir = await _dir;
      if (!await dir.exists()) return 0;
      int total = 0;
      for (final e in dir.listSync()) {
        if (e is File) total += e.lengthSync();
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// Deletes all files in disk cache.
  Future<void> clearDisk() async {
    try {
      final dir = await _dir;
      if (await dir.exists()) {
        for (final e in dir.listSync()) {
          if (e is File) await e.delete();
        }
      }
    } catch (_) {}
  }
}

class _DiskFileEntry {
  final File file;
  final DateTime modified;
  final int size;

  _DiskFileEntry(this.file, this.modified, this.size);
}
