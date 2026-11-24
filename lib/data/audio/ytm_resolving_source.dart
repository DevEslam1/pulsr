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
import '../../core/utils/error_logger.dart';
import 'adaptive_buffer_engine.dart';
import '../../core/services/stream_url_verifier.dart';
import '../../core/services/ytm_cache_manager.dart';
import '../../core/services/ytm_url_cache.dart';
import '../../core/telemetry/playback_latency_tracker.dart';
import '../../domain/models/ytm_track.dart';

/// A [StreamAudioSource] for a YouTube Music track whose stream URL is resolved
/// lazily, on the first byte request rather than up front.
///
/// Hardened with:
/// - In-memory LRU stream URL cache ([YtmUrlCache]) for instantaneous cache hits (<300ms)
/// - One reachability probe ([StreamUrlVerifier]) before a cached URL is trusted,
///   so a dead signature costs a single round trip instead of the multi-second
///   re-resolve it would otherwise trigger on the first byte
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

  /// The YouTube video id this source streams; also the disk-cache key.
  final String videoId;

  /// Resolves this track to a currently-valid, direct stream URL.
  final Future<String> Function({bool forceRefresh}) resolve;

  /// Optional error callback invoked when resolution fails before rethrow.
  final void Function(Object error)? onError;

  /// Optional explicit URL cache instance (used in tests).
  ///
  /// Supplying one disables cached-URL probing entirely: every host test builds
  /// the source this way, a probe would reach the network, and the pre-probe
  /// behaviour is what those tests pin. Production leaves this null and resolves
  /// the registered singleton.
  final YtmUrlCache? urlCache;

  /// Retries on HTTP 5xx errors with exponential backoff (1s, 2s) up to
  /// [maxAttempts] (default 2: one initial attempt + one retry).
  static Future<T> retryWithBackoff<T>(
    Future<T> Function() operation, {
    int maxAttempts = 2,
    Duration initialDelay = const Duration(seconds: 1),
  }) async {
    int attempt = 0;
    var delay = initialDelay;
    while (true) {
      attempt++;
      try {
        return await operation();
      } catch (e) {
        if (attempt >= maxAttempts || !isRetryable5xx(e)) {
          rethrow;
        }
        await Future.delayed(delay);
        delay *= 2;
      }
    }
  }

  /// True when [e] carries a structured HTTP 5xx status code (e.g. `HTTP 503`,
  /// `status: 500`, `YTM_HTTP_502`), using [YtmErrorClassifier.httpStatusIn]
  /// rather than bare substring matching so numbers inside video IDs, byte
  /// counts or itags never trigger spurious retries.
  @visibleForTesting
  static bool isRetryable5xx(Object e) {
    final status = YtmErrorClassifier.httpStatusIn(e.toString());
    return status != null && status >= 500 && status <= 599;
  }

  String? userAgent;
  String? cookies;

  /// The streaming-quality bucket this source resolves at, which is part of the
  /// [YtmUrlCache] key. It was left at the default `high` on both the read and
  /// the write, so a `low` resolve was stored in — and later served from — the
  /// `high` slot, and a user on the low tier got 256kbps URLs off the cache.
  /// The resolver assigns it alongside [userAgent] / [cookies].
  String quality;

  LockCachingAudioSource? _inner;
  File? _innerCacheFile;
  Future<LockCachingAudioSource>? _pending;
  DateTime? _resolvedExpiresAt;

  /// Set when the next creation must bypass every URL cache. Consumed once.
  bool _forceNextRefresh = false;

  /// Set when resolution has permanently failed for this source (e.g. bot
  /// challenge, video unavailable). Once set, every subsequent [request] call
  /// re-throws immediately without touching the resolver, stopping the
  /// ExoPlayer → just_audio proxy → HTTP 500 → retry spiral that otherwise
  /// loops indefinitely during a bot-cooldown window.
  Object? _permanentFailure;
  DateTime? _permanentFailureAt;
  bool _cancelled = false;
  final Completer<void> _cancelCompleter = Completer<void>();

  /// Whether this source has been explicitly cancelled by a newer track load.
  bool get isCancelled => _cancelled;

  /// Immediately aborts any in-flight [request] awaiting stream resolution or
  /// byte fetching (e.g. when the user switches to a local track while a VPN
  /// request is stalled), without invoking [onError] or latching a failure.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    if (!_cancelCompleter.isCompleted) {
      _cancelCompleter.complete();
    }
    _discardInner();
  }

  Future<T> _raceCancel<T>(Future<T> future) {
    if (_cancelled) {
      future.then<void>((_) {}, onError: (_) {});
      return Future<T>.error(const _YtmSourceCancelledException());
    }
    final completer = Completer<T>();
    future.then(
      (value) {
        if (!completer.isCompleted) completer.complete(value);
      },
      onError: (Object err, StackTrace st) {
        if (!completer.isCompleted) completer.completeError(err, st);
      },
    );
    _cancelCompleter.future.then((_) {
      if (!completer.isCompleted) {
        completer.completeError(const _YtmSourceCancelledException());
      }
    });
    return completer.future;
  }

  /// How long a recorded permanent failure latches before the source is allowed
  /// one fresh resolve. Long enough to break ExoPlayer's every-few-seconds retry
  /// spiral, short enough that recovery (e.g. once a bot cooldown lapses) does
  /// not require rebuilding the whole queue.
  static const Duration _permanentFailureRetryAfter = Duration(seconds: 60);

  /// The permanent failure stored on this source, if any. Used by the audio
  /// handler to detect that a source error came from a known-permanent cause
  /// (e.g. BOT_CHALLENGE) so it can skip to the next track rather than pausing.
  Object? get permanentFailure => _permanentFailure;

  static final YtmCacheManager _cacheManager = YtmCacheManager();

  YtmUrlCache? get _effectiveUrlCache =>
      urlCache ??
      (getIt.isRegistered<YtmUrlCache>() ? getIt<YtmUrlCache>() : null);

  /// Whether a cached URL may be probed before it is handed to the byte cache.
  ///
  /// Off on both test seams — an explicitly supplied [urlCache], and
  /// [debugInnerFactory] — so host tests keep the pre-probe behaviour and never
  /// reach the network.
  bool get _probingEnabled => urlCache == null && debugInnerFactory == null;

  PlaybackLatencyTracker? get _latency =>
      getIt.isRegistered<PlaybackLatencyTracker>()
          ? getIt<PlaybackLatencyTracker>()
          : null;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    if (_cancelled) {
      throw const _YtmSourceCancelledException();
    }
    // Short-circuit immediately on permanent failures: a BOT_CHALLENGE or
    // VIDEO_GONE that already fired once cannot resolve on re-request. Without
    // this guard, ExoPlayer retries the just_audio proxy on every HTTP 500,
    // the proxy calls request() again, hits the bot cooldown, returns 500 again
    // — an infinite Release→Init→fail spiral every few seconds.
    final pf = _permanentFailure;
    if (pf != null) {
      final at = _permanentFailureAt;
      if (at != null &&
          DateTime.now().difference(at) >= _permanentFailureRetryAfter) {
        // The latch has aged out (the bot cooldown / transient block that set
        // it has likely lapsed). Clear it and allow exactly one fresh, cache-
        // bypassing resolve instead of throwing for the lifetime of the source.
        _permanentFailure = null;
        _permanentFailureAt = null;
        _forceNextRefresh = true;
      } else {
        throw pf;
      }
    }

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
      // Serialize initial byte-cache population per cache path when no download
      // has started yet, so two concurrent sources for the same videoId never
      // write the same `.part` file simultaneously.
      //
      // The lock covers ONLY the byte request. The retry below takes the same
      // per-path lock, and holding it across that retry made the caller wait on
      // itself for the lock's full 60 s timeout: on a first play whose URL
      // answered 403 immediately, the "single fast re-resolve" this class
      // exists for became a minute of silence.
      final inner = await _raceCancel(_ensureInner());
      try {
        return await _raceCancel(_withPathLockIfUncached(
            () => _requestOnce(inner, start, end)));
      } catch (byteErr) {
        if (_cancelled || byteErr is _YtmSourceCancelledException) {
          throw const _YtmSourceCancelledException();
        }
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
          } catch (e, st) {
            ErrorLogger.log('Failed to delete cache files for burned videoId',
                error: e, stackTrace: st, category: 'YtmResolvingSource');
          }
        }

        try {
          final freshInner =
              await _raceCancel(_ensureInner(forceRefresh: burned));
          // Outside the lock held above, so this acquisition is fresh rather
          // than a re-entry against ourselves.
          return await _raceCancel(_withPathLockIfUncached(
              () => _requestOnce(freshInner, start, end)));
        } catch (retryErr) {
          if (_cancelled || retryErr is _YtmSourceCancelledException) {
            throw const _YtmSourceCancelledException();
          }
          // Classify failure to ensure structured diagnostics
          final classified = YtmErrorClassifier.classify(retryErr);
          debugPrint(
              '[YtmResolvingSource] Retry resolution failed ($retryErr): ${classified.message}');
          // A freshly resolved URL that is rejected on its first fetch is as
          // final for this source as a bot challenge: re-entering the resolver
          // on every proxy retry is the Release→Init→fail spiral the latch
          // exists to stop. The verdict stays signal-less ("expired"), so the
          // audio handler does not arm a global cooldown for one dead
          // signature.
          final burnedAgain = isUrlBurned(retryErr);
          if (_isFatalSignal(classified) || burnedAgain) {
            final code = classified.signal?.wireCode ?? 'YTM_STREAM_EXPIRED';
            final fatalErr = retryErr is YtmException
                ? retryErr
                : YtmException(code, classified.message);
            _permanentFailure = fatalErr;
            _permanentFailureAt = DateTime.now();
            onError?.call(fatalErr);
            throw fatalErr;
          }
          onError?.call(retryErr);
          rethrow;
        }
      }
    } catch (err) {
      if (_cancelled || err is _YtmSourceCancelledException) rethrow;
      if (err == _permanentFailure) rethrow; // already recorded above
      _discardInner();
      final classified = YtmErrorClassifier.classify(err);
      debugPrint(
          '[YtmResolvingSource] Initial resolution failed ($err): ${classified.message}');
      // Mark permanent so ExoPlayer's retry loop doesn't re-enter the resolver.
      // Only fatal signals qualify: bot challenges and unavailable tracks won't
      // resolve on re-request; network blips should still get a retry.
      if (_isFatalSignal(classified)) {
        final code = classified.signal?.wireCode ?? 'UNKNOWN';
        final fatalErr =
            err is YtmException ? err : YtmException(code, classified.message);
        _permanentFailure = fatalErr;
        _permanentFailureAt = DateTime.now();
        onError?.call(fatalErr);
        throw fatalErr;
      }
      onError?.call(err);
      rethrow;
    }
  }

  /// Whether [info] represents a signal that will not resolve on a retry, so
  /// we should stop ExoPlayer from re-requesting through the local proxy.
  static bool _isFatalSignal(YtmErrorInfo info) {
    return info.signal == YtmBlockSignal.botChallenge ||
        info.signal == YtmBlockSignal.ipBlocked ||
        info.signal == YtmBlockSignal.videoGone ||
        info.signal == YtmBlockSignal.signInRequired ||
        info.signal == YtmBlockSignal.poTokenInvalid ||
        info.signal == YtmBlockSignal.geoBlocked ||
        // Age-restricted tracks and cancellations never resolve on a retry;
        // latching them stops ExoPlayer's proxy retry spiral.
        info.signal == YtmBlockSignal.ageRestricted ||
        info.signal == YtmBlockSignal.interrupted;
  }

  /// Whether the stream URL itself is dead, as opposed to the connection to it.
  ///
  /// The verdict lives in [YtmErrorClassifier] because the download path needs
  /// exactly the same one — `HTTP Status Error: 403` from the just_audio fork
  /// and `HTTP 403` from a chunk request mean the same thing, and a second copy
  /// of the rule would drift.
  StreamAudioResponse _wrapWithThroughputSampler(StreamAudioResponse res) {
    final stopwatch = Stopwatch()..start();
    int bytesReceived = 0;
    final sampleStream = res.stream.map((chunk) {
      bytesReceived += chunk.length;
      if (stopwatch.elapsedMilliseconds >= 500) {
        if (getIt.isRegistered<AdaptiveBufferEngine>()) {
          getIt<AdaptiveBufferEngine>()
              .sampleThroughput(bytesReceived, stopwatch.elapsed);
        }
        bytesReceived = 0;
        stopwatch.reset();
      }
      return chunk;
    });
    return StreamAudioResponse(
      rangeRequestsSupported: res.rangeRequestsSupported,
      sourceLength: res.sourceLength,
      contentLength: res.contentLength,
      offset: res.offset,
      stream: sampleStream,
      contentType: res.contentType,
    );
  }

  @visibleForTesting
  static bool isUrlBurned(Object byteErr) =>
      YtmErrorClassifier.isUrlBurned(byteErr);

  /// Drops the memoized [LockCachingAudioSource] so the next request rebuilds
  /// it. [invalidateUrl] additionally evicts the URL from [YtmUrlCache] and
  /// forces the next creation to re-resolve, for when the URL is the problem.
  void _discardInner({bool invalidateUrl = false}) {
    final old = _inner;
    _inner = null;
    _innerCacheFile = null;
    _pending = null;
    old?.dispose();
    if (invalidateUrl) {
      _forceNextRefresh = true;
      _effectiveUrlCache?.invalidate(videoId);
    }
  }

  void dispose() => _discardInner();

  bool _isExpiringSoon() {
    final expires = _resolvedExpiresAt;
    if (expires == null) return false;
    final now = DateTime.now();
    return expires.difference(now).inSeconds < 300;
  }

  Future<LockCachingAudioSource> _ensureInner(
      {bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final existing = _inner;
      if (existing != null && !_isExpiringSoon()) return existing;
    }
    final pending = _pending;
    if (pending != null) {
      try {
        return await pending;
      } catch (e, st) {
        // Stale failed future: fall through and create a fresh one instead
        // of handing every waiter the same cached failure (thundering herd).
        ErrorLogger.log(
            'Pending inner creation failed, clearing stale pending',
            error: e,
            stackTrace: st,
            category: 'YtmResolvingSource');
        _pending = null;
      }
    }
    final fut = _createInner(forceRefresh: forceRefresh);
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
    var skipCache = forceRefresh || _forceNextRefresh;
    _forceNextRefresh = false;

    // Check Task 2 in-memory URL cache first when not force refreshing.
    // `get` already drops an expired entry against the cache's own clock, so
    // re-checking here with `DateTime.now()` only added a second, disagreeing
    // opinion about what "now" is.
    if (!skipCache) {
      final urlCache = _effectiveUrlCache;
      final cachedEntry = urlCache?.get(videoId, quality: quality);
      if (cachedEntry != null && urlCache != null) {
        final cachedUrl = cachedEntry.url;
        final cachedUa = cachedEntry.userAgent ?? effectiveUa;
        final cachedCookies = cachedEntry.cookies ?? effectiveCookies;
        var usable = true;

        // A URL can sit inside the cache's TTL long after the CDN stopped
        // honouring its signature: restored from disk, minted for another
        // egress, or simply past `expire`. The byte request is the only thing
        // that finds out today, and it costs the whole re-resolve plus the
        // silence before it. One two-byte GET answers the question instead.
        // A completed byte-cache file is read straight off disk by
        // `request()`, which never consults the URL: probing in front of it
        // would add a round trip (two seconds offline) to a replay that needs
        // no network at all.
        if (_probingEnabled &&
            !urlCache.isVerified(videoId, quality: quality) &&
            !await _hasCompleteByteCache()) {
          // Same header set as the playback request, from the same helper: a
          // probe that asks as somebody else answers a question nobody asked.
          final headers = _playbackHeaders(cachedUrl,
              ua: cachedUa, cookieJar: cachedCookies);
          final verdict = await StreamUrlVerifier().probe(
            cachedUrl,
            userAgent: headers['User-Agent'],
            referer: headers['Referer'],
            cookie: headers['Cookie'],
          );
          if (verdict.isRejected) {
            debugPrint(
                '[YtmResolvingSource] Cached URL rejected (${verdict.statusCode}) for $videoId — '
                'ageMs=${DateTime.now().difference(cachedEntry.fetchedAt).inMilliseconds} '
                'mintUa=${cachedEntry.userAgent ?? 'none'} '
                'host=${_hostOf(cachedUrl)} '
                'hasPot=${_urlHasParam(cachedUrl, _potParams)} '
                'hasSig=${_urlHasParam(cachedUrl, _sigParams)}');
            _discardInner(invalidateUrl: true);
            // `_discardInner` armed the latch for the *next* request, but this
            // call already re-resolves through `skipCache` below: leaving it
            // set would make one rejection cost two resolves.
            _forceNextRefresh = false;
            skipCache = true;
            _resolvedExpiresAt = null;
            usable = false;
          } else if (verdict.isOk) {
            // A working URL must never be probed twice inside the window.
            urlCache.markVerified(videoId, quality: quality);
          }
          // An unknown verdict (timeout, DNS blip, 5xx) keeps the URL as-is: a
          // flaky probe must never cost the user a paid re-resolve.
        }

        if (usable) {
          url = cachedUrl;
          effectiveUa = cachedUa;
          effectiveCookies = cachedCookies;
          _resolvedExpiresAt = cachedEntry.expiresAt;
          try {
            // Cache hit skips pluginEntered and marks urlObtained directly
            _latency?.markStage(PlaybackStage.urlObtained);
          } catch (e, st) {
            ErrorLogger.log('Latency markStage failed',
                error: e, stackTrace: st, category: 'YtmResolvingSource');
          }
        }
      }
    }

    if (url == null) {
      try {
        _latency?.markStage(PlaybackStage.pluginEntered);
      } catch (e, st) {
        ErrorLogger.log('Latency markStage failed',
            error: e, stackTrace: st, category: 'YtmResolvingSource');
      }
      url = await retryWithBackoff(() => resolve(forceRefresh: skipCache));
      try {
        _latency?.markStage(PlaybackStage.urlObtained);
      } catch (e, st) {
        ErrorLogger.log('Latency markStage failed',
            error: e, stackTrace: st, category: 'YtmResolvingSource');
      }
      // The resolver assigns userAgent/cookies/quality as a side effect, so read
      // them back rather than keeping the values captured before the call.
      effectiveUa = userAgent ?? effectiveUa;
      effectiveCookies = cookies ?? effectiveCookies;

      // Both stamp forms, `?expire=` and `/expire/<epoch>/`. Reading only the
      // query form left path-form URLs with a null expiry, and with it
      // `_isExpiringSoon()` answers false forever and the proactive re-resolve
      // never fires — the URL simply dies mid-track instead.
      final stamp = YtmStream.expiryFromUrl(url!);
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

    final resolvedUrl = url;
    final cacheFile = await _cacheFileFor(videoId, resolvedUrl, quality);
    final headers =
        _playbackHeaders(resolvedUrl, ua: effectiveUa, cookieJar: effectiveCookies);

    // Serialize per cache path so two sources for the same videoId never
    // initialize or write the same cache file simultaneously.
    final pathKey = cacheFile.path;
    return _withPathLock(pathKey, () async {
      final existing = _inner;
      if (existing != null && !skipCache) return existing;
      try {
        final uri = Uri.parse(resolvedUrl);
        final inner = debugInnerFactory?.call(uri, headers, cacheFile) ??
            LockCachingAudioSource(
              uri,
              headers: headers,
              cacheFile: cacheFile,
            );
        _inner = inner;
        _innerCacheFile = cacheFile;
        try {
          _latency?.markStage(PlaybackStage.sourceSet);
        } catch (e, st) {
          ErrorLogger.log('Latency markStage failed',
              error: e, stackTrace: st, category: 'YtmResolvingSource');
        }

        // Trigger asynchronous background cache pruning if exceeding size limit
        _cacheManager.pruneIfExceedsLimit().ignore();

        return inner;
      } catch (e) {
        _inner = null;
        _innerCacheFile = null;
        _pending = null;
        rethrow;
      }
    });
  }

  /// Runs [action] under the per-path mutex when the byte-cache file does not
  /// yet exist on disk, preventing two concurrent [YtmResolvingSource] instances
  /// for the same track from racing on the initial `.part` file download.
  ///
  /// The predicate is deliberately `.part`-aware. `LockCachingAudioSource`
  /// streams into `<name>.part` and renames it only once the whole track has
  /// arrived, so testing the final file alone kept this lock handed out for the
  /// entire first download — minutes of mutual exclusion for a creation race
  /// that the first byte has already decided.
  Future<T> _withPathLockIfUncached<T>(Future<T> Function() action) async {
    final file = _innerCacheFile;
    if (file == null ||
        file.existsSync() ||
        File('${file.path}.part').existsSync()) {
      return action();
    }
    return _withPathLock(file.path, action);
  }

  /// Issues one byte request against [inner] and wraps the response for
  /// throughput sampling.
  ///
  /// Extracted so the byte-error retry runs after the per-path creation lock
  /// has been released instead of re-entering it (a 60 s self-deadlock).
  Future<StreamAudioResponse> _requestOnce(
      LockCachingAudioSource inner, int? start, int? end) async {
    final res = await inner.request(start, end);
    // A first byte that actually arrived is the strongest proof the whole
    // chain works: remember it so the next playback of this URL inside the
    // verification window skips the probe instead of re-measuring what just
    // worked. The read first keeps a seek-heavy playback from re-stamping the
    // entry on every range request.
    final urlCache = _effectiveUrlCache;
    if (urlCache != null && !urlCache.isVerified(videoId, quality: quality)) {
      urlCache.markVerified(videoId, quality: quality);
    }
    try {
      _latency?.markStage(PlaybackStage.firstBytesReady);
    } catch (e, st) {
      ErrorLogger.log('Latency markStage failed',
          error: e, stackTrace: st, category: 'YtmResolvingSource');
    }
    return _wrapWithThroughputSampler(res);
  }

  /// Acquires the per-path lock for [pathKey] and releases it in `finally` only
  /// when this invocation actually owns the lock (using identity comparison so
  /// a timed-out waiter never evicts another caller's active lock).
  static Future<T> _withPathLock<T>(
      String pathKey, Future<T> Function() action) async {
    _cleanStalePathCreationLocks();
    late final Completer<void> ownedCompleter;
    late final _PathLockEntry ownedEntry;
    var lockAcquired = false;
    try {
      while (true) {
        final completer = Completer<void>();
        final candidate = _PathLockEntry(completer.future, DateTime.now());
        final entry = _pathCreationLocks.putIfAbsent(pathKey, () => candidate);
        if (identical(entry, candidate)) {
          ownedCompleter = completer;
          ownedEntry = candidate;
          lockAcquired = true;
          break;
        }
        try {
          await entry.future.timeout(const Duration(seconds: 60));
        } catch (_) {
          if (identical(_pathCreationLocks[pathKey], entry)) {
            _pathCreationLocks.remove(pathKey);
          }
        }
      }
      return await action();
    } finally {
      if (lockAcquired) {
        if (identical(_pathCreationLocks[pathKey], ownedEntry)) {
          _pathCreationLocks.remove(pathKey);
        }
        if (!ownedCompleter.isCompleted) {
          ownedCompleter.complete();
        }
      }
    }
  }

  /// Test seam replacing the byte-cache probe guard.
  ///
  /// The guard keeps the probe off a replay that a completed cache file serves
  /// from disk. A host test needs the probe path while still seeding a cache
  /// file — the only way to keep the byte request local — so it pins the
  /// guard's answer instead of reproducing the on-disk layout.
  @visibleForTesting
  static Future<bool> Function(String videoId)?
      debugCompleteByteCacheOverride;

  /// Whether a completed byte-cache file already exists for this track.
  ///
  /// Consulted only to decide whether a cached URL is worth probing: a
  /// complete file means the byte cache answers from disk, so the URL is never
  /// read and a probe would be pure cost. A `.part` file deliberately does not
  /// count — that download restarts from byte zero, so the URL still has to
  /// work.
  Future<bool> _hasCompleteByteCache() async {
    final override = debugCompleteByteCacheOverride;
    if (override != null) return override(videoId);
    try {
      final dir = await _cacheManager.getCacheDirectory();
      final hash = _cacheManager.getHashForVideoId(videoId);
      for (final name in YtmCacheManager.allCacheFileNames(hash)) {
        if (File(p.join(dir.path, name)).existsSync()) return true;
      }
    } catch (e, st) {
      // An unreadable cache directory means "unknown": probe.
      ErrorLogger.log('Error reading cache directory during complete check',
          error: e, stackTrace: st, category: 'YtmResolvingSource');
    }
    return false;
  }

  /// Request headers for the one request that matters: the byte GET.
  ///
  /// Single source of truth for playback and for the pre-flight probe. A probe
  /// that sent a different User-Agent, Referer or Cookie would answer a
  /// question about a request nobody makes.
  Map<String, String> _playbackHeaders(String url,
      {String? ua, String? cookieJar}) {
    final isNativeClient = ua != null &&
        (ua.contains('com.google.android') ||
            ua.contains('com.google.ios') ||
            (ua.contains('Android') && !ua.contains('Mozilla')));

    return <String, String>{
      if (ua != null && ua.isNotEmpty)
        'User-Agent': ua
      else
        'User-Agent': EmbeddedBrowserUa.desktop,
      // The account cookie jar is scoped to youtube.com; a browser never sends
      // it to the media CDN, which authenticates the request from the signature
      // in the URL instead. Attaching it here leaked the live Google session
      // (SAPISID/SID/HSID) to every googlevideo edge node and made the fetch
      // look unlike the web player it claims to be.
      if (cookieJar != null &&
          cookieJar.isNotEmpty &&
          _cookiesBelongOn(url))
        'Cookie': cookieJar,
      // Native clients (e.g. ANDROID_VR, IOS_MUSIC) stream from googlevideo CDN
      // without a web Referer. Sending 'https://music.youtube.com/' with a native
      // app User-Agent flags the request as spoofed to CDN edge nodes and causes HTTP 403.
      if (!isNativeClient) 'Referer': 'https://music.youtube.com/',
    };
  }

  /// Host of [url], or `unknown` when it will not parse.
  static String _hostOf(String url) {
    try {
      return Uri.parse(url).host;
    } catch (e, st) {
      ErrorLogger.log('Failed to parse host from url',
          error: e, stackTrace: st, category: 'YtmResolvingSource');
      return 'unknown';
    }
  }

  /// poToken query parameters a resolved URL may carry.
  static const Set<String> _potParams = {'pot', 'potoken', 'po_token'};

  /// Signature query parameters a resolved URL may carry.
  static const Set<String> _sigParams = {'sig', 'signature', 'lsig'};

  /// Whether [url]'s query carries any of [names].
  ///
  /// Used only by the rejection diagnostic: the difference between a URL with
  /// a signature and one without is usually the difference between a 403 the
  /// resolver can fix and one it cannot.
  static bool _urlHasParam(String url, Set<String> names) {
    try {
      for (final key in Uri.parse(url).queryParameters.keys) {
        if (names.contains(key.toLowerCase())) return true;
      }
    } on FormatException {
      return false;
    }
    return false;
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
    } catch (e, st) {
      ErrorLogger.log('Failed to parse URI to check cookies',
          error: e, stackTrace: st, category: 'YtmResolvingSource');
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
    for (final name in YtmCacheManager.allCacheFileNames(hash)) {
      for (final suffix in const ['', '.part', '.mime']) {
        final f = File(p.join(dir.path, '$name$suffix'));
        if (await f.exists()) {
          try {
            await f.delete();
          } catch (e, st) {
            ErrorLogger.log('Failed to delete cache file',
                error: e, stackTrace: st, category: 'YtmResolvingSource');
          }
        }
      }
    }
  }

  static final LinkedHashMap<String, _PathLockEntry> _pathCreationLocks =
      LinkedHashMap<String, _PathLockEntry>();

  /// Test seam replacing the byte-caching inner source.
  ///
  /// Production always builds a [LockCachingAudioSource]; a host test cannot,
  /// because `TestWidgetsFlutterBinding` answers every real HTTP request with
  /// 400 and reports the failure on the zone as well as the future. Supplying a
  /// source whose `request()` fails deterministically lets the byte-error retry
  /// path — and its lock behaviour — be exercised without a network.
  @visibleForTesting
  static LockCachingAudioSource Function(
      Uri uri, Map<String, String> headers, File cacheFile)? debugInnerFactory;

  static void _cleanStalePathCreationLocks() {
    final now = DateTime.now();
    _pathCreationLocks.removeWhere((_, entry) =>
        now.difference(entry.createdAt) > const Duration(seconds: 60));
    while (_pathCreationLocks.length > 200) {
      _pathCreationLocks.remove(_pathCreationLocks.keys.first);
    }
  }

  static Future<File> _cacheFileFor(
      String videoId, String url, String quality) async {
    final dir = await _cacheManager.getCacheDirectory();
    final hash = _cacheManager.getHashForVideoId(videoId);
    // Container-aware extension: a webm/opus resolve must not reuse (or be
    // poisoned by) an m4a cache slot written for a different format.
    var ext = 'm4a';
    try {
      final mime = Uri.parse(url).queryParameters['mime'] ?? '';
      if (mime.contains('webm')) ext = 'webm';
    } catch (e, st) {
      ErrorLogger.log('Failed to parse mime from url',
          error: e, stackTrace: st, category: 'YtmResolvingSource');
    }
    // F9: quality-keyed too, through the one naming helper every reader and
    // sweeper shares rather than a second inline format string.
    return File(
        p.join(dir.path, YtmCacheManager.cacheFileName(hash, quality, ext)));
  }
}

class _PathLockEntry {
  final Future<void> future;
  final DateTime createdAt;
  _PathLockEntry(this.future, this.createdAt);
}

class _YtmSourceCancelledException implements Exception {
  const _YtmSourceCancelledException();

  @override
  String toString() => 'YtmResolvingSource cancelled (loading interrupted)';
}
