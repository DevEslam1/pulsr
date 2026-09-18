// lib/core/services/ytm_url_cache.dart
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:path_provider/path_provider.dart';
import '../../domain/models/ytm_track.dart';
import '../telemetry/clock.dart';

/// Representation of a cached direct stream URL for a YouTube Music track.
class YtmUrlCacheEntry {
  final String videoId;
  final String url;
  final DateTime fetchedAt;
  final DateTime expiresAt;
  final String? userAgent;
  final String? cookies;
  final YtmStream? stream;

  const YtmUrlCacheEntry({
    required this.videoId,
    required this.url,
    required this.fetchedAt,
    required this.expiresAt,
    this.userAgent,
    this.cookies,
    this.stream,
  });

  /// Checks if entry is expired relative to [now].
  bool isExpired([DateTime? now]) {
    final current = now ?? DateTime.now();
    return current.isAfter(expiresAt) || current.isAtSameMomentAs(expiresAt);
  }

  /// Calculates remaining lifetime duration.
  Duration remainingTtl([DateTime? now]) {
    final current = now ?? DateTime.now();
    final diff = expiresAt.difference(current);
    return diff.isNegative ? Duration.zero : diff;
  }

  /// Returns reconstituted [YtmStream] if cached, or constructs a minimal valid one.
  YtmStream toStream({String quality = 'high'}) {
    if (stream != null) return stream!;
    return YtmStream(
      videoId: videoId,
      url: url,
      mimeType: url.contains('mime=audio%2Fwebm') ? 'audio/webm' : 'audio/mp4',
      container: url.contains('mime=audio%2Fwebm') ? 'webm' : 'm4a',
      bitrateKbps: quality == 'high' ? 256 : (quality == 'medium' ? 128 : 64),
      duration: Duration.zero,
      title: 'YouTube Track',
      artist: 'YouTube Music',
      userAgent: userAgent,
      cookies: cookies,
      expiresAt: expiresAt.millisecondsSinceEpoch,
    );
  }
}

/// Task 2 — In-memory LRU Cache for resolved direct YouTube Music stream URLs.
///
/// Features:
/// - Keyed by `videoId + quality` with max capacity ~200 entries
/// - Default TTL of 4 hours (stream URLs live ~6 hours)
/// - Proactive expiry subtraction (5 min margin) if URL contains `expire` timestamp
/// - Deterministic time injection via [Clock] for testing
/// - Explicit single-track or full invalidation on HTTP 403 / 404
@singleton
class YtmUrlCache {
  static const int defaultCapacity = 200;
  static const Duration defaultTtl = Duration(hours: 4);
  static const Duration expirySafetyMargin = Duration(minutes: 5);

  final Clock _clock;
  final int _capacity;
  final Duration _ttl;

  final LinkedHashMap<String, YtmUrlCacheEntry> _cache =
      LinkedHashMap<String, YtmUrlCacheEntry>();

  static const String _diskFileName = 'ytm_url_cache_v1.json';
  /// Restored entries are only worth keeping if they have meaningful life left;
  /// a URL that expires moments after launch would just 403 on first play.
  static const Duration _restoreMinTtl = Duration(minutes: 10);
  static const Duration _persistDebounce = Duration(seconds: 3);

  File? _diskFile;
  bool _restored = false;
  Timer? _persistTimer;

  @factoryMethod
  YtmUrlCache()
      : _clock = const SystemClock(),
        _capacity = defaultCapacity,
        _ttl = defaultTtl;

  @visibleForTesting
  YtmUrlCache.withClock(this._clock, {int capacity = defaultCapacity, Duration ttl = defaultTtl})
      : _capacity = capacity,
        _ttl = ttl;

  /// Loads guest stream URLs persisted by a previous run so a replay or a
  /// skip-back after a restart is instant instead of a full resolve.
  ///
  /// Only entries **without cookies** are persisted: account-bound URLs carry
  /// credentials that must not land in a plaintext file, and their signed URLs
  /// are far more likely to be invalidated (IP/account binding) between runs.
  /// Guest URLs for public tracks are the overwhelmingly common case and the
  /// one worth caching across launches.
  Future<void> restore() async {
    if (_restored) return;
    _restored = true;
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/$_diskFileName');
      _diskFile = file;
      if (!await file.exists()) return;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final now = _clock.now();
      for (final item in decoded) {
        if (item is! Map) continue;
        final videoId = item['videoId'] as String?;
        final url = item['url'] as String?;
        final quality = item['quality'] as String? ?? 'high';
        final expiryRaw = item['expiresAt'];
        if (videoId == null || url == null || expiryRaw is! int) continue;
        final expiresAt = DateTime.fromMillisecondsSinceEpoch(expiryRaw);
        if (expiresAt.difference(now) < _restoreMinTtl) continue;
        final userAgent = item['userAgent'] as String?;
        // Rebuild the rich stream from persisted metadata when present, so a
        // restored entry isn't served with Duration.zero and a guessed
        // container/bitrate.
        YtmStream? rebuilt;
        final mimeType = item['mimeType'] as String?;
        if (mimeType != null) {
          rebuilt = YtmStream(
            videoId: videoId,
            url: url,
            mimeType: mimeType,
            container: item['container'] as String? ?? 'm4a',
            bitrateKbps: (item['bitrateKbps'] as num?)?.toInt() ?? 0,
            duration:
                Duration(milliseconds: (item['durationMs'] as num?)?.toInt() ?? 0),
            title: item['title'] as String? ?? 'YouTube Track',
            artist: item['artist'] as String? ?? 'YouTube Music',
            userAgent: userAgent,
            expiresAt: expiresAt.millisecondsSinceEpoch,
          );
        }
        // Reuse put() so URL stamp parsing / safety margins stay authoritative.
        put(videoId, url,
            quality: quality,
            explicitExpiry: expiresAt,
            userAgent: userAgent,
            stream: rebuilt);
      }
      debugPrint('[YtmUrlCache] Restored ${_cache.length} cached stream URL(s)');
    } catch (e) {
      debugPrint('[YtmUrlCache] restore failed: $e');
    }
  }

  void _schedulePersist() {
    final file = _diskFile;
    if (file == null) return;
    _persistTimer?.cancel();
    _persistTimer = Timer(_persistDebounce, () {
      unawaited(_persistNow(file));
    });
  }

  Future<void> _persistNow(File file) async {
    try {
      final list = <Map<String, dynamic>>[];
      for (final e in _cache.entries) {
        final entry = e.value;
        if (entry.cookies != null && entry.cookies!.isNotEmpty) continue;
        final sep = e.key.lastIndexOf(':');
        final quality = sep >= 0 ? e.key.substring(sep + 1) : 'high';
        final s = entry.stream;
        list.add({
          'videoId': entry.videoId,
          'url': entry.url,
          'quality': quality,
          'expiresAt': entry.expiresAt.millisecondsSinceEpoch,
          if (entry.userAgent != null) 'userAgent': entry.userAgent,
          // Persist the resolved stream metadata so a restored entry rebuilds a
          // faithful YtmStream instead of one with Duration.zero and a
          // container/bitrate guessed from the URL.
          if (s != null) ...{
            'mimeType': s.mimeType,
            'container': s.container,
            'bitrateKbps': s.bitrateKbps,
            'durationMs': s.duration.inMilliseconds,
            'title': s.title,
            'artist': s.artist,
          },
        });
      }
      await file.writeAsString(jsonEncode(list), flush: false);
    } catch (_) {}
  }

  String _buildKey(String videoId, String quality) => '$videoId:${quality.toLowerCase()}';

  /// Retrieves cached entry if present and not expired. Moves entry to MRU position.
  YtmUrlCacheEntry? get(String videoId, {String quality = 'high'}) {
    final key = _buildKey(videoId, quality);
    final entry = _cache[key];
    if (entry == null) return null;

    final now = _clock.now();
    if (entry.isExpired(now)) {
      _cache.remove(key);
      return null;
    }

    // Refresh LRU order (move to end)
    _cache.remove(key);
    _cache[key] = entry;
    return entry;
  }

  /// Returns valid cached URL string if available, null otherwise.
  String? getUrl(String videoId, {String quality = 'high'}) {
    return get(videoId, quality: quality)?.url;
  }

  /// Returns valid cached [YtmStream] if available, null otherwise.
  YtmStream? getStream(String videoId, {String quality = 'high'}) {
    return get(videoId, quality: quality)?.toStream(quality: quality);
  }

  /// Checks if a valid, unexpired entry exists in cache.
  ///
  /// Unlike [get], a pure existence check does not promote the entry to MRU —
  /// probing whether something is cached should not reset its eviction aging.
  bool contains(String videoId, {String quality = 'high'}) {
    final key = _buildKey(videoId, quality);
    final entry = _cache[key];
    if (entry == null) return false;
    if (entry.isExpired(_clock.now())) {
      _cache.remove(key);
      return false;
    }
    return true;
  }

  /// Stores a resolved stream URL into the LRU cache.
  void put(
    String videoId,
    String url, {
    String quality = 'high',
    DateTime? explicitExpiry,
    String? userAgent,
    String? cookies,
    YtmStream? stream,
  }) {
    if (videoId.trim().isEmpty || url.trim().isEmpty) return;
    if (Uri.tryParse(url.trim()) == null) return;
    final key = _buildKey(videoId, quality);
    final now = _clock.now();

    // Earliest known death wins, capped at now + ttl. The URL's own `expire`
    // stamp used to be ignored whenever an explicitExpiry was supplied, and a
    // stamp that had already passed was reported as "no stamp at all" — so a
    // dead URL was handed the full 4-hour default TTL and every later read
    // served it happily until googlevideo answered 403.
    final stampExpiry = _parseUrlExpiryStamp(url)?.subtract(expirySafetyMargin);
    final candidates = <DateTime>[
      now.add(_ttl),
      if (explicitExpiry != null) explicitExpiry,
      if (stampExpiry != null) stampExpiry,
    ];
    final computedExpiry =
        candidates.reduce((a, b) => a.isBefore(b) ? a : b);

    if (!computedExpiry.isAfter(now)) {
      // Already expired, or inside the safety margin: caching it would only
      // re-arm a stale entry. Drop whatever was stored under this key so the
      // next read misses and re-resolves instead of reusing a dead URL.
      _cache.remove(key);
      return;
    }

    // F1: a stream-less re-`put` for a URL already stored must not throw the
    // rich entry away. The lazy playback source (`YtmResolvingSource`) writes
    // one of these immediately after `YtmService.resolveStream` stored the real
    // container/MIME/bitrate/duration through `putStream`, so on every cache
    // miss the rich record was replaced by a URL-only one — and a later hit
    // then rebuilt the stream with `duration: Duration.zero` and a container
    // guessed from the URL. Same key plus same URL means the same body, so the
    // richer fields are carried forward.
    final previous = _cache[key];
    final sameUrl = previous != null && previous.url == url;
    final effectiveStream = stream ?? (sameUrl ? previous.stream : null);
    final effectiveUserAgent =
        userAgent ?? (sameUrl ? previous.userAgent : null);
    final effectiveCookies = cookies ?? (sameUrl ? previous.cookies : null);

    final entry = YtmUrlCacheEntry(
      videoId: videoId,
      url: url,
      fetchedAt: now,
      expiresAt: computedExpiry,
      userAgent: effectiveUserAgent,
      cookies: effectiveCookies,
      stream: effectiveStream,
    );

    // Evict oldest if full
    if (_cache.containsKey(key)) {
      _cache.remove(key);
    } else if (_cache.length >= _capacity && _cache.isNotEmpty) {
      _cache.remove(_cache.keys.first);
    }

    _cache[key] = entry;
    _schedulePersist();
  }

  /// Stores a resolved [YtmStream] into the LRU cache.
  void putStream(
    YtmStream stream, {
    String quality = 'high',
  }) {
    put(
      stream.videoId,
      stream.url,
      quality: quality,
      explicitExpiry: stream.expiresAtDateTime,
      userAgent: stream.userAgent,
      cookies: stream.cookies,
      stream: stream,
    );
  }

  /// Invalidates entry for [videoId]. If [quality] is specified, removes exact entry.
  /// If [quality] is omitted or null, invalidates all qualities for that video.
  void invalidate(String videoId, {String? quality}) {
    if (quality != null) {
      _cache.remove(_buildKey(videoId, quality));
    } else {
      final prefix = '$videoId:';
      final keysToRemove = _cache.keys.where((k) => k.startsWith(prefix)).toList();
      for (final k in keysToRemove) {
        _cache.remove(k);
      }
    }
    _schedulePersist();
  }

  /// Clears entire in-memory URL cache.
  void clear() {
    _cache.clear();
    _schedulePersist();
  }

  /// Current number of entries in the cache.
  int get length => _cache.length;

  /// Absolute expiry stamped on a googlevideo URL, or null when it carries none.
  ///
  /// The stamp is served either as a query parameter (`?expire=1712345678`) or
  /// as a path segment (`/expire/1712345678/`); reading only the query form let
  /// path-form URLs look stamp-less and take the full default TTL.
  ///
  /// A stamp in the past is returned as-is rather than as null: "no stamp" and
  /// "already dead" must not collapse into the same answer, or the caller
  /// cannot tell a fresh URL from an expired one.
  // FIX-C02: Handle both epoch seconds (< 1e11) and milliseconds (>= 1e11)
  @visibleForTesting
  static DateTime? parseUrlExpiryStamp(String url) {
    try {
      final uri = Uri.parse(url);
      var expireParam = uri.queryParameters['expire'];
      if (expireParam == null) {
        final segments = uri.pathSegments;
        final index = segments.indexOf('expire');
        if (index >= 0 && index + 1 < segments.length) {
          expireParam = segments[index + 1];
        }
      }
      final rawEpoch = int.tryParse(expireParam ?? '');
      if (rawEpoch != null && rawEpoch > 0) {
        final ms = rawEpoch >= 100000000000 ? rawEpoch : rawEpoch * 1000;
        return DateTime.fromMillisecondsSinceEpoch(ms);
      }
    } catch (_) {}
    return null;
  }

  DateTime? _parseUrlExpiryStamp(String url) => parseUrlExpiryStamp(url);
}
