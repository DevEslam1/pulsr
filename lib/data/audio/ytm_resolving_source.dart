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
import 'package:mutex/mutex.dart';
import 'package:path/path.dart' as p;
import '../../core/di/injection.dart';
import '../../core/errors/ytm_error_classifier.dart';
import '../../core/services/ytm_cache_manager.dart';
import '../../core/services/ytm_url_cache.dart';
import '../../core/telemetry/playback_latency_tracker.dart';

/// A [StreamAudioSource] for a YouTube Music track whose stream URL is resolved
/// lazily, on the first byte request rather than up front.
///
/// Hardened with:
/// - In-memory LRU stream URL cache ([YtmUrlCache]) for instantaneous cache hits (<300ms)
/// - Parsing of `expire` query timestamp (proactive re-resolve when < 300s remaining)
/// - Automatic single-retry on 403 Forbidden / 404 Not Found / 416 Range Not Satisfiable
/// - Resilient disk cache managed by [YtmCacheManager] with LRU pruning
class YtmResolvingSource extends StreamAudioSource {
  YtmResolvingSource({
    required this.videoId,
    required this.resolve,
    this.userAgent,
    this.cookies,
    this.onError,
    this.urlCache,
    super.tag,
  });

  YtmResolvingSource.withRefresh({
    required this.videoId,
    required this.resolve,
    this.userAgent,
    this.cookies,
    this.onError,
    this.urlCache,
    super.tag,
  });

  /// The YouTube video id this source streams; also the disk-cache key.
  final String videoId;

  /// Resolves this track to a currently-valid, direct stream URL.
  final Future<String> Function({bool forceRefresh}) resolve;

  /// Optional error callback invoked when resolution fails before rethrow.
  final void Function(Object error)? onError;

  /// Optional explicit URL cache instance (used in tests).
  final YtmUrlCache? urlCache;

  String? userAgent;
  String? cookies;

  final Mutex _requestMutex = Mutex();
  LockCachingAudioSource? _inner;
  Future<LockCachingAudioSource>? _pending;
  DateTime? _resolvedExpiresAt;
  String? _lastResolvedUrl;

  static final YtmCacheManager _cacheManager = YtmCacheManager();

  YtmUrlCache? get _effectiveUrlCache =>
      urlCache ??
      (getIt.isRegistered<YtmUrlCache>() ? getIt<YtmUrlCache>() : null);

  PlaybackLatencyTracker? get _latency =>
      getIt.isRegistered<PlaybackLatencyTracker>()
          ? getIt<PlaybackLatencyTracker>()
          : null;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    return await _requestMutex.protect(() async {
      // 1. Proactive expiry check: if URL is within 5 minutes of expiring, discard & re-resolve
      if (_isExpiringSoon()) {
        debugPrint(
          '[YtmResolvingSource] Stream URL for $videoId is expiring soon. Re-resolving...',
        );
        _inner = null;
        _pending = null;
      }

      try {
        final inner = await _ensureInner();
        try {
          final res = await inner.request(start, end);
          try {
            _latency?.markStage(PlaybackStage.firstBytesReady);
          } catch (_) {}
          return res;
        } catch (byteErr) {
          final errStr = byteErr.toString().toLowerCase();

          // Check if error represents a stale/forbidden stream URL (403/404/416/408)
          final is403or404 =
              errStr.contains('403') ||
              errStr.contains('forbidden') ||
              errStr.contains('404') ||
              errStr.contains('408') ||
              errStr.contains('416');

          debugPrint(
            '[YtmResolvingSource] Byte stream error ($byteErr, isForbidden/Stale=$is403or404) for $videoId. Evicting dead URL & retrying fresh resolution once...',
          );
          _inner = null;
          _pending = null;

          // Evict and blacklist dead URL in cache for this video
          _effectiveUrlCache?.evictDeadUrl(videoId, _lastResolvedUrl);

          try {
            await _deleteCacheFilesFor(videoId);
          } catch (_) {}

          // Single retry through fresh resolution pipeline
          try {
            final freshInner = await _createInner(forceRefresh: true);
            final res = await freshInner.request(start, end);
            try {
              _latency?.markStage(PlaybackStage.firstBytesReady);
            } catch (_) {}
            return res;
          } catch (retryErr) {
            // Classify failure to ensure structured diagnostics
            final classified = YtmErrorClassifier.classify(retryErr);
            debugPrint(
              '[YtmResolvingSource] Retry resolution failed ($retryErr): ${classified.message}',
            );
            onError?.call(retryErr);
            rethrow;
          }
        }
      } catch (err) {
        _inner = null;
        _pending = null;
        final classified = YtmErrorClassifier.classify(err);
        debugPrint(
          '[YtmResolvingSource] Initial resolution failed ($err): ${classified.message}',
        );
        onError?.call(err);
        rethrow;
      }
    });
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

  Future<LockCachingAudioSource> _createInner({
    bool forceRefresh = false,
  }) async {
    String? url;
    String? effectiveUa = userAgent;
    String? effectiveCookies = cookies;

    // Check Task 2 in-memory URL cache first when not force refreshing
    if (!forceRefresh) {
      final cachedEntry = _effectiveUrlCache?.get(
        videoId,
        onStaleRevalidate: (vid) {
          // Asynchronously trigger SWTR refresh without blocking current playback
          unawaited(
            resolve(forceRefresh: true)
                .then((freshUrl) {
                  _effectiveUrlCache?.put(
                    vid,
                    freshUrl,
                    userAgent: effectiveUa,
                    cookies: effectiveCookies,
                  );
                })
                .catchError((_) {}),
          );
        },
      );
      if (cachedEntry != null && !cachedEntry.isExpired()) {
        url = cachedEntry.url;
        effectiveUa = cachedEntry.userAgent ?? effectiveUa;
        effectiveCookies = cachedEntry.cookies ?? effectiveCookies;
        _resolvedExpiresAt = cachedEntry.expiresAt;
        try {
          // Cache hit skips pluginEntered and marks urlObtained directly
          _latency?.markStage(PlaybackStage.urlObtained);
        } catch (_) {}
      }
    }

    if (url == null) {
      try {
        _latency?.markStage(PlaybackStage.pluginEntered);
      } catch (_) {}
      url = await resolve(forceRefresh: forceRefresh);
      try {
        _latency?.markStage(PlaybackStage.urlObtained);
      } catch (_) {}

      // Parse 'expire' Unix timestamp from query
      try {
        final uri = Uri.parse(url);
        final expireParam = uri.queryParameters['expire'];
        if (expireParam != null) {
          final epochSeconds = int.tryParse(expireParam);
          if (epochSeconds != null && epochSeconds > 0) {
            _resolvedExpiresAt = DateTime.fromMillisecondsSinceEpoch(
              epochSeconds * 1000,
            );
          }
        }
      } catch (_) {}

      // Store resolved stream URL in cache
      _effectiveUrlCache?.put(
        videoId,
        url,
        userAgent: effectiveUa,
        cookies: effectiveCookies,
      );
    }

    final cacheFile = await _cacheFileFor(videoId, url);
    final headers = <String, String>{
      if (effectiveUa != null && effectiveUa.isNotEmpty)
        'User-Agent': effectiveUa
      else
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.7204.93 Safari/537.36',
      if (effectiveCookies != null && effectiveCookies.isNotEmpty)
        'Cookie': effectiveCookies,
      'Referer': 'https://music.youtube.com/',
    };

    // Serialize creation per cache path so two sources for the same videoId
    // never start writing the same file at exactly the same time.
    final pathKey = cacheFile.path;
    final completer = Completer<void>();
    if (_pathCreationLocks.length >= _maxPathCreationLocks &&
        !_pathCreationLocks.containsKey(pathKey)) {
      final oldestKey = _pathCreationLocks.keys.first;
      final previous = _pathCreationLocks[oldestKey];
      // Only evict if previous future is completed (avoid removing in-flight lock)
      if (previous != null && previous.isCompleted) {
        _pathCreationLocks.remove(oldestKey);
      } else if (previous != null) {
        // In-flight lock at oldest slot — find first completed entry to evict instead
        String? completedKey;
        for (final entry in _pathCreationLocks.entries) {
          if (entry.value.isCompleted) {
            completedKey = entry.key;
            break;
          }
        }
        if (completedKey != null) {
          _pathCreationLocks.remove(completedKey);
        }
      }
    }
    final existingLock = _pathCreationLocks.putIfAbsent(
      pathKey,
      () => completer,
    );

    if (!identical(existingLock, completer)) {
      // Another creation is in progress; wait for it
      try {
        await existingLock.future;
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
      _lastResolvedUrl = url;
      _inner = inner;
      try {
        _latency?.markStage(PlaybackStage.sourceSet);
      } catch (_) {}

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
      // Only remove our own lock; avoid deleting a newer owner's in-flight lock
      if (identical(_pathCreationLocks[pathKey], completer)) {
        _pathCreationLocks.remove(pathKey);
      }
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
  static final LinkedHashMap<String, Completer<void>> _pathCreationLocks =
      LinkedHashMap<String, Completer<void>>();

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
