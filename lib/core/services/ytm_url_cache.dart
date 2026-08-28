// lib/core/services/ytm_url_cache.dart
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
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

  @factoryMethod
  YtmUrlCache()
      : _clock = const SystemClock(),
        _capacity = defaultCapacity,
        _ttl = defaultTtl;

  @visibleForTesting
  YtmUrlCache.withClock(this._clock, {int capacity = defaultCapacity, Duration ttl = defaultTtl})
      : _capacity = capacity,
        _ttl = ttl;

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
  bool contains(String videoId, {String quality = 'high'}) {
    return get(videoId, quality: quality) != null;
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
    final key = _buildKey(videoId, quality);
    final now = _clock.now();

    // Determine expiration timestamp
    DateTime computedExpiry = explicitExpiry ?? _parseUrlExpiry(url, now) ?? now.add(_ttl);
    // Cap at now + ttl
    final maxAllowedExpiry = now.add(_ttl);
    if (computedExpiry.isAfter(maxAllowedExpiry)) {
      computedExpiry = maxAllowedExpiry;
    }

    final entry = YtmUrlCacheEntry(
      videoId: videoId,
      url: url,
      fetchedAt: now,
      expiresAt: computedExpiry,
      userAgent: userAgent,
      cookies: cookies,
      stream: stream,
    );

    // Evict oldest if full
    if (_cache.containsKey(key)) {
      _cache.remove(key);
    } else if (_cache.length >= _capacity && _cache.isNotEmpty) {
      _cache.remove(_cache.keys.first);
    }

    _cache[key] = entry;
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
  }

  /// Clears entire in-memory URL cache.
  void clear() {
    _cache.clear();
  }

  /// Current number of entries in the cache.
  int get length => _cache.length;

  /// Parses YouTube stream URL `expire` query parameter if present.
  DateTime? _parseUrlExpiry(String url, DateTime now) {
    try {
      final uri = Uri.parse(url);
      final expireParam = uri.queryParameters['expire'];
      if (expireParam != null) {
        final epochSeconds = int.tryParse(expireParam);
        if (epochSeconds != null && epochSeconds > 0) {
          final expiresAt = DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000);
          // Subtract safety margin (5 min) to prevent near-expiry stalls
          final safeExpiry = expiresAt.subtract(expirySafetyMargin);
          return safeExpiry.isAfter(now) ? safeExpiry : null;
        }
      }
    } catch (_) {}
    return null;
  }
}
