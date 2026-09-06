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
import '../../core/constants/embedded_browser_ua.dart';
import '../../core/di/injection.dart';
import '../../core/errors/ytm_error_classifier.dart';
import '../../core/services/ytm_cache_manager.dart';
import '../../core/services/ytm_url_cache.dart';
import '../../core/telemetry/playback_latency_tracker.dart';
import '../../domain/models/ytm_track.dart';

/// A [StreamAudioSource] for a YouTube Music track whose stream URL is resolved
/// lazily, on the first byte request rather than up front.
///
/// Hardened with:
/// - In-memory LRU stream URL cache ([YtmUrlCache]) for instantaneous cache hits (<300ms)
/// - Parsing of the `expire` stamp (proactive re-resolve when < 300s remaining)
/// - A single retry on a byte error, whose remedy depends on *why* the read
///   failed: a burned URL is re-resolved, a dropped connection is retried
/// - Resilient disk cache managed by [YtmCacheManager] with LRU pruning
class YtmResolvingSource extends StreamAudioSource {
  YtmResolvingSource({
    required this.videoId,
    required this.resolve,
    this.userAgent,
    this.cookies,
    this.quality = 'high',
    this.onError,
    this.urlCache,
    super.tag,
  });

  YtmResolvingSource.withRefresh({
    required this.videoId,
    required this.resolve,
    this.userAgent,
    this.cookies,
    this.quality = 'high',
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

  /// The streaming-quality bucket this source resolves at, which is part of the
  /// [YtmUrlCache] key. It was left at the default `high` on both the read and
  /// the write, so a `low` resolve was stored in — and later served from — the
  /// `high` slot, and a user on the low tier got 256kbps URLs off the cache.
  /// The resolver assigns it alongside [userAgent] / [cookies].
  String quality;

  LockCachingAudioSource? _inner;
  Future<LockCachingAudioSource>? _pending;
  DateTime? _resolvedExpiresAt;

  /// Set when the next creation must bypass every URL cache. Consumed once.
  bool _forceNextRefresh = false;

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
    // 1. Proactive expiry check: if URL is within 5 minutes of expiring, discard
    // & re-resolve. Dropping `_inner`/`_pending` alone was not enough: the URL
    // that is about to die is also the one sitting in `YtmUrlCache`, so the
    // rebuild read it straight back and the check achieved nothing.
    if (_isExpiringSoon()) {
      debugPrint(
          '[YtmResolvingSource] Stream URL for $videoId is expiring soon. Re-resolving...');
      _discardInner(invalidateUrl: true);
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
        final burned = isUrlBurned(byteErr);

        debugPrint(
            '[YtmResolvingSource] Byte stream error ($byteErr, urlBurned=$burned) for $videoId. '
            '${burned ? 'Invalidating URL cache & re-resolving once…' : 'Transport failure — retrying the same URL once…'}');

        // A burned URL and a dropped connection need opposite remedies, and the
        // verdict used to be computed into `is403or404` and then never read —
        // every byte error took the invalidate-and-re-resolve path. A transport
        // blip therefore threw away a good URL, deleted a possibly-complete
        // cache file, and burned a full multi-client resolve (and, under a bot
        // cooldown, a poToken mint) for a failure YouTube had no part in.
        _discardInner(invalidateUrl: burned);
        if (burned) {
          try {
            await _deleteCacheFilesFor(videoId);
          } catch (_) {}
        }

        try {
          final freshInner = await _createInner(forceRefresh: burned);
          final res = await freshInner.request(start, end);
          try {
            _latency?.markStage(PlaybackStage.firstBytesReady);
          } catch (_) {}
          return res;
        } catch (retryErr) {
          // Classify failure to ensure structured diagnostics
          final classified = YtmErrorClassifier.classify(retryErr);
          debugPrint(
              '[YtmResolvingSource] Retry resolution failed ($retryErr): ${classified.message}');
          onError?.call(retryErr);
          rethrow;
        }
      }
    } catch (err) {
      _discardInner();
      final classified = YtmErrorClassifier.classify(err);
      debugPrint(
          '[YtmResolvingSource] Initial resolution failed ($err): ${classified.message}');
      onError?.call(err);
      rethrow;
    }
  }

  /// Whether the stream URL itself is dead, as opposed to the connection to it.
  ///
  /// The verdict lives in [YtmErrorClassifier] because the download path needs
  /// exactly the same one — `HTTP Status Error: 403` from the just_audio fork
  /// and `HTTP 403` from a chunk request mean the same thing, and a second copy
  /// of the rule would drift.
  @visibleForTesting
  static bool isUrlBurned(Object byteErr) =>
      YtmErrorClassifier.isUrlBurned(byteErr);

  /// Drops the memoized [LockCachingAudioSource] so the next request rebuilds
  /// it. [invalidateUrl] additionally evicts the URL from [YtmUrlCache] and
  /// forces the next creation to re-resolve, for when the URL is the problem.
  void _discardInner({bool invalidateUrl = false}) {
    _inner = null;
    _pending = null;
    if (invalidateUrl) {
      _forceNextRefresh = true;
      _effectiveUrlCache?.invalidate(videoId);
    }
  }

  bool _isExpiringSoon() {
    final expires = _resolvedExpiresAt;
    if (expires == null) return false;
    final now = DateTime.now();
    return expires.difference(now).inSeconds < 300;
  }

  Future<LockCachingAudioSource> _ensureInner() async {
    final existing = _inner;
    if (existing != null && !_isExpiringSoon()) return existing;
    final pending = _pending;
    if (pending != null) {
      try {
        return await pending;
      } catch (_) {
        // Stale failed future: fall through and create a fresh one instead
        // of handing every waiter the same cached failure (thundering herd).
        _pending = null;
      }
    }
    final fut = _createInner();
    _pending = fut;
    try {
      final inner = await fut;
      _pending = null;
      return inner;
    } catch (e) {
      _pending = null;
      rethrow;
    }
  }

  Future<LockCachingAudioSource> _createInner(
      {bool forceRefresh = false}) async {
    String? url;
    String? effectiveUa = userAgent;
    String? effectiveCookies = cookies;

    // A refresh armed by a burned URL or a near-expiry check must survive the
    // hop through `_ensureInner`, which calls this with no argument.
    final skipCache = forceRefresh || _forceNextRefresh;
    _forceNextRefresh = false;

    // Check Task 2 in-memory URL cache first when not force refreshing.
    // `get` already drops an expired entry against the cache's own clock, so
    // re-checking here with `DateTime.now()` only added a second, disagreeing
    // opinion about what "now" is.
    if (!skipCache) {
      final cachedEntry = _effectiveUrlCache?.get(videoId, quality: quality);
      if (cachedEntry != null) {
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
      url = await resolve(forceRefresh: skipCache);
      try {
        _latency?.markStage(PlaybackStage.urlObtained);
      } catch (_) {}
      // The resolver assigns userAgent/cookies/quality as a side effect, so read
      // them back rather than keeping the values captured before the call.
      effectiveUa = userAgent ?? effectiveUa;
      effectiveCookies = cookies ?? effectiveCookies;

      // Both stamp forms, `?expire=` and `/expire/<epoch>/`. Reading only the
      // query form left path-form URLs with a null expiry, and with it
      // `_isExpiringSoon()` answers false forever and the proactive re-resolve
      // never fires — the URL simply dies mid-track instead.
      final stamp = YtmStream.expiryFromUrl(url);
      if (stamp != null) {
        _resolvedExpiresAt = DateTime.fromMillisecondsSinceEpoch(stamp);
      }

      // Store resolved stream URL in cache
      _effectiveUrlCache?.put(
        videoId,
        url,
        quality: quality,
        userAgent: effectiveUa,
        cookies: effectiveCookies,
      );
    }

    final cacheFile = await _cacheFileFor(videoId, url);
    final headers = <String, String>{
      if (effectiveUa != null && effectiveUa.isNotEmpty)
        'User-Agent': effectiveUa
      else
        'User-Agent': EmbeddedBrowserUa.desktop,
      // The account cookie jar is scoped to youtube.com; a browser never sends
      // it to the media CDN, which authenticates the request from the signature
      // in the URL instead. Attaching it here leaked the live Google session
      // (SAPISID/SID/HSID) to every googlevideo edge node and made the fetch
      // look unlike the web player it claims to be.
      if (effectiveCookies != null &&
          effectiveCookies.isNotEmpty &&
          _cookiesBelongOn(url))
        'Cookie': effectiveCookies,
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
      _pathCreationLocks.remove(pathKey);
    }
  }

  /// Whether the YouTube cookie jar may be sent to [url]'s host.
  ///
  /// False for the media CDN (`*.googlevideo.com`, the legacy `*.c.youtube.com`
  /// edges, and anything serving `/videoplayback`), which is signature-
  /// authenticated and never receives cookies from a real browser. True for
  /// anything else, which in practice is the self-hosted backend proxy the user
  /// has explicitly opted into syncing cookies with.
  static bool _cookiesBelongOn(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host.toLowerCase();
      if (host == 'googlevideo.com' || host.endsWith('.googlevideo.com')) {
        return false;
      }
      if (host.endsWith('.c.youtube.com')) return false;
      if (uri.path.contains('/videoplayback')) return false;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Deletes every container variant of this videoId's cache slot (the
  /// resolver may alternate between m4a and webm across re-resolves), plus the
  /// `.part` and `.mime` siblings just_audio writes alongside each one. Leaving
  /// those behind orphaned them for good whenever the container changed: nothing
  /// else knows their names, so they sat in the cache directory counting against
  /// the size limit until a prune happened to reach them.
  static Future<void> _deleteCacheFilesFor(String videoId) async {
    final dir = await _cacheManager.getCacheDirectory();
    final hash = _cacheManager.getHashForVideoId(videoId);
    for (final ext in const ['m4a', 'webm', 'opus', 'mp4']) {
      for (final suffix in const ['', '.part', '.mime']) {
        final f = File(p.join(dir.path, '$hash.$ext$suffix'));
        if (await f.exists()) {
          try {
            await f.delete();
          } catch (_) {}
        }
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
