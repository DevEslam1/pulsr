// lib/core/services/waveform_service.dart
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../constants/channels.dart';
import '../utils/error_logger.dart';
import '../utils/platform_capabilities.dart';
import '../utils/waveform_generator.dart';

/// Produces waveform samples (0..1) for the seek bar.
///
/// For local files it decodes real PCM natively ([MediaExtractor]+[MediaCodec])
/// and caches the result to disk, so decoding runs once per file. Remote rows
/// (YTM) have no local PCM available before download, so they fall back to the
/// synthetic [WaveformGenerator] — honest, not file-accurate, but deterministic.
class WaveformService {
  WaveformService._();
  static final WaveformService instance = WaveformService._();

  static const MethodChannel _channel = MethodChannel(PulsrChannels.waveform);
  static const int _maxMemCacheSize = 100;

  final LinkedHashMap<String, List<double>> _memCache = LinkedHashMap();
  Directory? _cacheDir;

  Future<List<double>> getWaveform({
    required int songId,
    String? filePath,
    int count = 60,
  }) async {
    final memKey = '${songId}_$count';
    final cached = _memCache.remove(memKey);
    if (cached != null) {
      _memCache[memKey] = cached; // refresh LRU position
      return cached;
    }

    List<double>? samples;
    if (_isLocalFile(filePath)) {
      samples = await _loadFromDiskOrDecode(filePath!, count);
    }
    samples ??= await WaveformGenerator().generateWaveform(
      songId: songId,
      filePath: filePath,
      count: count,
    );

    _putMem(memKey, samples);
    return samples;
  }

  bool _isLocalFile(String? path) =>
      path != null &&
      path.isNotEmpty &&
      !path.startsWith('http') &&
      !path.startsWith('ytmusic://');

  void clearMemoryCache() {
    _memCache.clear();
  }

  void _putMem(String key, List<double> value) {
    if (_memCache.length >= _maxMemCacheSize) {
      _memCache.remove(_memCache.keys.first);
    }
    _memCache[key] = value;
  }

  Future<List<double>?> _loadFromDiskOrDecode(String path, int count) async {
    try {
      int mtime = 0;
      int size = 0;
      if (!path.startsWith('content:')) {
        final file = File(
            path.startsWith('file://') ? Uri.parse(path).toFilePath() : path);
        if (await file.exists()) {
          final stat = await file.stat();
          mtime = stat.modified.millisecondsSinceEpoch;
          size = stat.size;
        }
      }

      final diskFile = await _diskCacheFile(path, mtime, size, count);
      if (await diskFile.exists()) {
        try {
          final decoded = (jsonDecode(await diskFile.readAsString()) as List)
              .map((e) => (e as num).toDouble())
              .toList();
          if (decoded.length == count) return decoded;
        } catch (_) {
          // Corrupt cache entry — fall through and re-decode.
        }
      }

      final result = await _decodeNative(path, count);
      if (result != null && result.isNotEmpty) {
        await _pruneStaleEntries(path, keep: diskFile.path);
        try {
          await diskFile.writeAsString(jsonEncode(result));
        } catch (_) {}
        return result;
      }
    } catch (e, st) {
      ErrorLogger.log('Waveform disk/native load failed for $path',
          error: e, stackTrace: st, category: 'Waveform');
    }
    return null;
  }

  Future<List<double>?> _decodeNative(String path, int count) async {
    if (!PlatformCapabilities.isAndroid) return null;
    try {
      final res = await _channel.invokeMethod<List<dynamic>>(
        'decode',
        {'path': path, 'count': count},
      ).timeout(const Duration(seconds: 8));
      return res?.map((e) => (e as num).toDouble()).toList();
    } on TimeoutException {
      ErrorLogger.log('Waveform decode timeout for $path', category: 'Waveform');
      return null;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<File> _diskCacheFile(
      String path, int mtime, int size, int count) async {
    final dir = _cacheDir ??= await _initCacheDir();
    if (path.startsWith('content:')) {
      return File('${dir.path}/content_${_hashPath(path)}_$count.json');
    }
    return File('${dir.path}/${_hashPath(path)}_${mtime}_${size}_$count.json');
  }

  /// Removes older cache files for the same source (different mtime/size/count)
  /// so a re-tagged or re-encoded file does not accumulate stale entries.
  Future<void> _pruneStaleEntries(String path, {required String keep}) async {
    try {
      final dir = _cacheDir;
      if (dir == null) return;
      final prefix = path.startsWith('content:')
          ? 'content_${_hashPath(path)}_'
          : '${_hashPath(path)}_';
      await for (final entity in dir.list()) {
        if (entity is File &&
            entity.path != keep &&
            entity.uri.pathSegments.last.startsWith(prefix)) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  Future<Directory> _initCacheDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/waveforms');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// FNV-1a 64-bit hash → 16-char hex. Stable across runs (unlike [String.hashCode])
  /// and filesystem-safe, so it is a durable disk-cache key for a file path.
  String _hashPath(String s) {
    int hash = 0xcbf29ce484222325;
    const int prime = 0x100000001b3;
    for (final unit in s.codeUnits) {
      hash ^= unit;
      hash = (hash * prime) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toUnsigned(64).toRadixString(16).padLeft(16, '0');
  }
}
