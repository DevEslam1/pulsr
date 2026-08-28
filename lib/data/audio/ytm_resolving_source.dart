// lib/data/audio/ytm_resolving_source.dart
//
// just_audio marks StreamAudioSource / LockCachingAudioSource / StreamAudioResponse
// @experimental. We depend on them deliberately (pinned at just_audio 0.9.46) to
// get lazy resolution + byte caching for YTM inside a ConcatenatingAudioSource.
// ignore_for_file: experimental_member_use
import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import '../../core/services/ytm_cache_manager.dart';

/// A [StreamAudioSource] for a YouTube Music track whose stream URL is resolved
/// lazily, on the first byte request rather than up front.
///
/// Hardened with:
/// - Parsing of `expire` query timestamp (proactive re-resolve when < 300s remaining)
/// - Automatic transparent retry on 403 Forbidden / 416 Range Not Satisfiable
/// - Resilient disk cache managed by [YtmCacheManager] with LRU pruning
class YtmResolvingSource extends StreamAudioSource {
  YtmResolvingSource({
    required this.videoId,
    required this.resolve,
    this.userAgent,
    this.cookies,
    this.onError,
    super.tag,
  });

  YtmResolvingSource.withRefresh({
    required this.videoId,
    required this.resolve,
    this.userAgent,
    this.cookies,
    this.onError,
    super.tag,
  });

  /// The YouTube video id this source streams; also the disk-cache key.
  final String videoId;

  /// Resolves this track to a currently-valid, direct stream URL.
  final Future<String> Function({bool forceRefresh}) resolve;

  /// Optional error callback invoked when resolution fails before rethrow.
  final void Function(Object error)? onError;

  String? userAgent;
  String? cookies;

  LockCachingAudioSource? _inner;
  Future<LockCachingAudioSource>? _pending;
  DateTime? _resolvedExpiresAt;

  static final YtmCacheManager _cacheManager = YtmCacheManager();

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    // 1. Proactive expiry check: if URL is within 5 minutes of expiring, discard & re-resolve
    if (_isExpiringSoon()) {
      debugPrint(
          '[YtmResolvingSource] Stream URL for $videoId is expiring soon. Re-resolving...');
      _inner = null;
      _pending = null;
    }

    try {
      final inner = await _ensureInner();
      try {
        return await inner.request(start, end);
      } catch (byteErr) {
        final errStr = byteErr.toString().toLowerCase();

        // Abort immediately on hard blocks (403/429/forbidden)
        if (errStr.contains('403') ||
            errStr.contains('forbidden') ||
            errStr.contains('429')) {
          debugPrint(
              '[YtmResolvingSource] Hard block ($byteErr) for $videoId. Aborting re-resolution.');
          _inner = null;
          _pending = null;
          onError?.call(byteErr);
          rethrow;
        }

        debugPrint(
            '[YtmResolvingSource] Byte stream error ($byteErr) for $videoId. Re-resolving fresh stream...');
        _inner = null;
        _pending = null;
        try {
          await _deleteCacheFilesFor(videoId);
        } catch (_) {}
        final freshInner = await _createInner(forceRefresh: true);
        return await freshInner.request(start, end);
      }
    } catch (err) {
      _inner = null;
      _pending = null;
      onError?.call(err);
      rethrow;
    }
  }

  bool _isExpiringSoon() {
    final expires = _resolvedExpiresAt;
    if (expires == null) return false;
    final now = DateTime.now();
    return expires.difference(now).inSeconds < 300;
  }

  Future<LockCachingAudioSource> _ensureInner() {
    final existing = _inner;
    if (existing != null && !_isExpiringSoon()) return Future.value(existing);
    return _pending ??= _createInner();
  }

  Future<LockCachingAudioSource> _createInner(
      {bool forceRefresh = false}) async {
    final url = await resolve(forceRefresh: forceRefresh);

    // Parse 'expire' Unix timestamp from query
    try {
      final uri = Uri.parse(url);
      final expireParam = uri.queryParameters['expire'];
      if (expireParam != null) {
        final epochSeconds = int.tryParse(expireParam);
        if (epochSeconds != null) {
          _resolvedExpiresAt =
              DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000);
        }
      }
    } catch (_) {}

    final cacheFile = await _cacheFileFor(videoId, url);
    final ua = userAgent;
    final ck = cookies;
    final headers = <String, String>{
      if (ua != null && ua.isNotEmpty)
        'User-Agent': ua
      else
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36',
      if (ck != null && ck.isNotEmpty) 'Cookie': ck,
      'Referer': 'https://music.youtube.com/',
    };

    // Serialize creation per cache path so two sources for the same videoId
    // never start writing the same file at exactly the same time.
    final pathKey = cacheFile.path;
    final completer = Completer<void>();
    if (_pathCreationLocks.length >= _maxPathCreationLocks &&
        !_pathCreationLocks.containsKey(pathKey)) {
      _pathCreationLocks.remove(_pathCreationLocks.keys.first);
    }
    final previous =
        _pathCreationLocks.putIfAbsent(pathKey, () => completer.future);

    if (!identical(previous, completer.future)) {
      // Another creation is in progress; wait for it
      try {
        await previous;
      } catch (_) {}
      final existing = _inner;
      if (existing != null) return existing;
    }

    try {
      final inner = LockCachingAudioSource(
        Uri.parse(url),
        headers: headers,
        cacheFile: cacheFile,
      );
      _inner = inner;

      // Trigger asynchronous background cache pruning if exceeding size limit
      _cacheManager.pruneIfExceedsLimit().ignore();

      return inner;
    } catch (e) {
      _inner = null;
      _pending = null;
      rethrow;
    } finally {
      if (!completer.isCompleted) {
        completer.complete();
      }
      _pathCreationLocks.remove(pathKey);
    }
  }

  /// Deletes every container variant of this videoId's cache slot (the
  /// resolver may alternate between m4a and webm across re-resolves).
  static Future<void> _deleteCacheFilesFor(String videoId) async {
    final dir = await _cacheManager.getCacheDirectory();
    final hash = _cacheManager.getHashForVideoId(videoId);
    for (final ext in const ['m4a', 'webm', 'opus', 'mp4']) {
      final f = File(p.join(dir.path, '$hash.$ext'));
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
  }

  static const int _maxPathCreationLocks = 32;
  static final LinkedHashMap<String, Future<void>> _pathCreationLocks =
      LinkedHashMap<String, Future<void>>();

  static Future<File> _cacheFileFor(String videoId, String url) async {
    final dir = await _cacheManager.getCacheDirectory();
    final hash = _cacheManager.getHashForVideoId(videoId);
    // Container-aware extension: a webm/opus resolve must not reuse (or be
    // poisoned by) an m4a cache slot written for a different format.
    var ext = 'm4a';
    try {
      final mime = Uri.parse(url).queryParameters['mime'] ?? '';
      if (mime.contains('webm')) ext = 'webm';
    } catch (_) {}
    return File(p.join(dir.path, '$hash.$ext'));
  }
}
