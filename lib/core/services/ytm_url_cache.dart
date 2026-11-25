// lib/core/services/ytm_url_cache.dart
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';
import 'package:path_provider/path_provider.dart';
import '../../domain/models/ytm_track.dart';
import '../constants/channels.dart';
import '../telemetry/clock.dart';
import '../utils/l10n_holder.dart';

import '../utils/error_logger.dart';

/// Representation of a cached direct stream URL for a YouTube Music track.
class YtmUrlCacheEntry {
  final String videoId;
  final String url;
  final DateTime fetchedAt;
  final DateTime expiresAt;
  final String? userAgent;
  final String? cookies;
  final YtmStream? stream;

  /// When a probe — or a first byte that actually arrived — confirmed this URL
  /// serves audio, or null when nothing has confirmed it yet.
  ///
  /// Never leaves the process: [YtmUrlCache.restore] deliberately drops it,
  /// because a URL that survived a launch may have been minted for a previous
  /// egress or attested by a previous run.
  final DateTime? verifiedAt;

  const YtmUrlCacheEntry({
    required this.videoId,
    required this.url,
    required this.fetchedAt,
    required this.expiresAt,
    this.userAgent,
    this.cookies,
    this.stream,
    this.verifiedAt,
  });

  /// Whether this entry carries a verification stamp. Age is not considered
  /// here; [YtmUrlCache.isVerified] owns the staleness rule.
  bool get isVerified => verifiedAt != null;

  YtmUrlCacheEntry _withVerifiedAt(DateTime at) => YtmUrlCacheEntry(
        videoId: videoId,
        url: url,
        fetchedAt: fetchedAt,
        expiresAt: expiresAt,
        userAgent: userAgent,
        cookies: cookies,
        stream: stream,
        verifiedAt: at,
      );

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
    final baseQuality = quality.split(':').first.trim().toLowerCase();
    return YtmStream(
      videoId: videoId,
      url: url,
      mimeType: url.contains('mime=audio%2Fwebm') ? 'audio/webm' : 'audio/mp4',
      container: url.contains('mime=audio%2Fwebm') ? 'webm' : 'm4a',
      bitrateKbps:
          baseQuality == 'high' ? 256 : (baseQuality == 'medium' ? 128 : 64),
      duration: Duration.zero,
      title: L10nHolder.current?.ytmFallbackTrackTitle ?? 'YouTube Track',
      artist: L10nHolder.current?.browseYouTubeMusic ?? 'YouTube Music',
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
@lazySingleton
class YtmUrlCache {
  static const int defaultCapacity = 200;
  static const Duration defaultTtl = Duration(hours: 4);
  static const Duration expirySafetyMargin = Duration(minutes: 5);

  final Clock _clock;
  final int _capacity;
  final Duration _ttl;

  final LinkedHashMap<String, YtmUrlCacheEntry> _cache =
      LinkedHashMap<String, YtmUrlCacheEntry>();
  int _mutationGeneration = 0;

  static const String _diskFileName = 'ytm_url_cache_v1.json';
  static const MethodChannel _networkChannel =
      MethodChannel(PulsrChannels.proxy);

  static File _identityFile(File cacheFile) =>
      File('${cacheFile.path}.network');

  /// Stable hash of the active interface/addresses, or null off-device.
  Future<String?> _currentNetworkIdentity() async {
    try {
      final state = await _networkChannel
          .invokeMapMethod<String, dynamic>('getNetworkState')
          .timeout(const Duration(milliseconds: 750));
      final identity = state?['identity'];
      if (identity is String && identity.isNotEmpty && identity != 'offline') {
        return identity;
      }
    } catch (_) {
      // Missing plugin (tests/desktop) or a transient platform error: fall
      // back to the previous network-agnostic restore behavior.
    }
    return null;
  }

  /// Restored entries are only worth keeping if they have meaningful life left;
  /// a URL that expires moments after launch would just 403 on first play.
  static const Duration _restoreMinTtl = Duration(minutes: 10);
  static const Duration _persistDebounce = Duration(seconds: 3);
  static const int _maxRestoreBytes = 2 * 1024 * 1024;

  File? _diskFile;
  bool _restored = false;
  Future<void>? _restoreFuture;
  Timer? _persistTimer;

  @factoryMethod
  YtmUrlCache()
      : _clock = const SystemClock(),
        _capacity = defaultCapacity,
        _ttl = defaultTtl;

  @visibleForTesting
  YtmUrlCache.withClock(this._clock,
      {int capacity = defaultCapacity, Duration ttl = defaultTtl})
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
  ///
  /// Restored entries always come back **unverified**. Verification is a
  /// statement about the path a URL was fetched over, and a URL that survived a
  /// launch may have been minted for a previous egress or attested by a
  /// previous run: replaying its old stamp would skip the one probe that can
  /// tell whether the signature still works from here. Any `verifiedAt` an
  /// on-disk file happens to carry is therefore ignored, not restored.
  Future<void> restore() {
    if (_restored) return Future.value();
    return _restoreFuture ??= _restoreImpl().whenComplete(() {
      _restoreFuture = null;
    });
  }

  Future<void> _restoreImpl() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/$_diskFileName');
      _diskFile = file;
      if (!await file.exists()) {
        _restored = true;
        return;
      }

      // Signed googlevideo URLs are bound to the egress that minted them. A
      // restart on a different interface means the persisted body is dead.
      final identityFile = _identityFile(file);
      String? storedIdentity;
      try {
        if (await identityFile.exists()) {
          storedIdentity = (await identityFile.readAsString()).trim();
        }
      } catch (e, st) {
        ErrorLogger.log('Best-effort YtmUrlCache operation failed',
            error: e, stackTrace: st, category: 'YtmUrlCache');
      }
      final currentIdentity = await _currentNetworkIdentity();
      if (storedIdentity != null &&
          storedIdentity.isNotEmpty &&
          currentIdentity != null &&
          storedIdentity != currentIdentity) {
        debugPrint(
            '[YtmUrlCache] Network identity changed ($storedIdentity -> $currentIdentity); discarding persisted URLs');
        try {
          await file.delete();
        } catch (e, st) {
          ErrorLogger.log('Best-effort YtmUrlCache operation failed',
              error: e, stackTrace: st, category: 'YtmUrlCache');
        }
        try {
          await identityFile.delete();
        } catch (e, st) {
          ErrorLogger.log('Best-effort YtmUrlCache operation failed',
              error: e, stackTrace: st, category: 'YtmUrlCache');
        }
        _restored = true;
        return;
      }
      if (currentIdentity != null) {
        try {
          await identityFile.writeAsString(currentIdentity, flush: true);
        } catch (e, st) {
          ErrorLogger.log('Best-effort YtmUrlCache operation failed',
              error: e, stackTrace: st, category: 'YtmUrlCache');
        }
      }
      // Hygiene pass: cap persisted cache restore at 2 MB to avoid OOM/jank.
      final size = await file.length();
      if (size > _maxRestoreBytes) {
        debugPrint(
            '[YtmUrlCache] Ignoring and deleting oversized restore file ($size bytes)');
        unawaited(file.delete().catchError((_) => file));
        _restored = true;
        return;
      }
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        _restored = true;
        return;
      }
      final dynamic decoded;
      try {
        decoded = jsonDecode(raw);
      } catch (e) {
        debugPrint('[YtmUrlCache] Deleting corrupt cache file: $e');
        unawaited(file.delete().catchError((_) => file));
        _restored = true;
        return;
      }
      if (decoded is! List) {
        _restored = true;
        return;
      }
      final now = _clock.now();
      for (final item in decoded) {
        if (item is! Map) continue;
        final videoId = item['videoId'] as String?;
        final url = item['url'] as String?;
        final quality = item['quality']?.toString() ?? 'high';
        final expiryRaw = item['expiresAt'];
        final int? expiryMs = expiryRaw is int
            ? expiryRaw
            : int.tryParse(expiryRaw?.toString() ?? '');
        if (videoId == null || url == null || expiryMs == null) continue;
        final expiresAt = DateTime.fromMillisecondsSinceEpoch(expiryMs);
        if (expiresAt.difference(now) < _restoreMinTtl) continue;
        // Never clobber a fresher in-memory entry inserted while awaiting I/O.
        if (_cache.containsKey(_buildKey(videoId, quality))) continue;
        final userAgent = item['userAgent']?.toString();
        // Rebuild the rich stream from persisted metadata when present, so a
        // restored entry isn't served with Duration.zero and a guessed
        // container/bitrate.
        YtmStream? rebuilt;
        final mimeType = item['mimeType']?.toString();
        if (mimeType != null && mimeType.isNotEmpty) {
          final bitrate = (item['bitrateKbps'] is num)
              ? (item['bitrateKbps'] as num).toInt()
              : (int.tryParse(item['bitrateKbps']?.toString() ?? '') ?? 0);
          final durationMs = (item['durationMs'] is num)
              ? (item['durationMs'] as num).toInt()
              : (int.tryParse(item['durationMs']?.toString() ?? '') ?? 0);
          rebuilt = YtmStream(
            videoId: videoId,
            url: url,
            mimeType: mimeType,
            container: item['container']?.toString() ?? 'm4a',
            bitrateKbps: bitrate,
            duration: Duration(milliseconds: durationMs),
            title: item['title']?.toString() ?? 'YouTube Track',
            artist: item['artist']?.toString() ?? 'YouTube Music',
            userAgent: userAgent,
            expiresAt: expiresAt.millisecondsSinceEpoch,
          );
        }
        // Reuse the store so URL stamp parsing / safety margins stay
        // authoritative. `carryVerified: false` makes the drop unconditional
        // even if this exact URL is already in memory — see [restore].
        _store(videoId, url,
            quality: quality,
            explicitExpiry: expiresAt,
            userAgent: userAgent,
            stream: rebuilt,
            carryVerified: false);
      }
      _restored = true;
      debugPrint(
          '[YtmUrlCache] Restored ${_cache.length} cached stream URL(s)');
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
        // Quality is everything after the FIRST ':' — a videoId never contains
        // one, but a quality can (`high:m4a`), so lastIndexOf dropped the
        // leading segment and re-keyed restored m4a entries as `videoId:m4a`,
        // which the `high:m4a` lookup then never found.
        final sep = e.key.indexOf(':');
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
      final identity = await _currentNetworkIdentity();
      if (identity != null) {
        try {
          await _identityFile(file).writeAsString(identity, flush: false);
        } catch (e, st) {
          ErrorLogger.log('Best-effort YtmUrlCache operation failed',
              error: e, stackTrace: st, category: 'YtmUrlCache');
        }
      }
    } catch (e, st) {
      ErrorLogger.log('Best-effort YtmUrlCache operation failed',
          error: e, stackTrace: st, category: 'YtmUrlCache');
    }
  }

  String _buildKey(String videoId, String quality) =>
      '$videoId:${quality.toLowerCase()}';

  /// The quality slot a resolved stream belongs in.
  ///
  /// `preferM4a` selects a different container for the same video, and the two
  /// must never share a slot: a webm/Opus body served from an m4a slot (or the
  /// reverse) writes the wrong bytes into the wrong file. The rule used to be
  /// spelled out at each call site as `'$quality:m4a'`; keeping it here stops
  /// the next caller from inventing a fourth spelling.
  static String qualitySlot(String quality, {bool preferM4a = false}) =>
      preferM4a ? '${quality.toLowerCase()}:m4a' : quality.toLowerCase();

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

  /// Checks if entry is missing, expired, or expiring within [refreshThreshold] (default 10m).
  bool needsRefresh(
    String videoId, {
    String quality = 'high',
    Duration refreshThreshold = const Duration(minutes: 10),
  }) {
    final key = _buildKey(videoId, quality);
    final entry = _cache[key];
    if (entry == null) return true;
    final now = _clock.now();
    if (entry.isExpired(now)) {
      _cache.remove(key);
      return true;
    }
    return entry.remainingTtl(now) <= refreshThreshold;
  }

  /// Stores a resolved stream URL into the LRU cache.
  ///
  /// [verifiedAt] records that a probe, or a first byte that actually arrived,
  /// already confirmed this exact URL. Leave it null for a freshly resolved
  /// URL: an unverified entry costs one probe on first use, while a wrongly
  /// verified one serves a dead URL straight to the player.
  void put(
    String videoId,
    String url, {
    String quality = 'high',
    DateTime? explicitExpiry,
    String? userAgent,
    String? cookies,
    YtmStream? stream,
    DateTime? verifiedAt,
  }) {
    _store(
      videoId,
      url,
      quality: quality,
      explicitExpiry: explicitExpiry,
      userAgent: userAgent,
      cookies: cookies,
      stream: stream,
      verifiedAt: verifiedAt,
    );
  }

  /// Store shared by [put] and [putStream].
  ///
  /// [carryVerified] is false for [putStream]: a URL handed over by the
  /// resolver is a fresh mint and must not inherit an earlier verification
  /// merely because YouTube returned the same URL again.
  void _store(
    String videoId,
    String url, {
    required String quality,
    DateTime? explicitExpiry,
    String? userAgent,
    String? cookies,
    YtmStream? stream,
    DateTime? verifiedAt,
    bool carryVerified = true,
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
    final computedExpiry = candidates.reduce((a, b) => a.isBefore(b) ? a : b);

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
    final effectiveUserAgent =
        userAgent ?? (sameUrl ? previous.userAgent : null);
    final effectiveCookies = cookies ?? (sameUrl ? previous.cookies : null);
    YtmStream? effectiveStream;
    if (stream != null) {
      effectiveStream = stream;
    } else if (sameUrl) {
      effectiveStream = previous.stream;
    } else if (previous?.stream != null) {
      final ps = previous!.stream!;
      effectiveStream = YtmStream(
        videoId: ps.videoId,
        url: url,
        mimeType: ps.mimeType,
        container: ps.container,
        bitrateKbps: ps.bitrateKbps,
        duration: ps.duration,
        title: ps.title,
        artist: ps.artist,
        artworkUrl: ps.artworkUrl,
        userAgent: effectiveUserAgent,
        cookies: effectiveCookies,
        loudnessDb: ps.loudnessDb,
        expiresAt: ps.expiresAt,
      );
    }

    // A verification describes one URL, so it survives only a re-store of that
    // same URL. A different URL carries a different signature and starts
    // unproven, or the probe would be skipped for a URL nobody has fetched.
    // [carryVerified] only governs *inheritance*: an explicit [verifiedAt]
    // (a mint-time stamp) always wins.
    final inheritedVerifiedAt = sameUrl ? previous.verifiedAt : null;
    final effectiveVerifiedAt =
        verifiedAt ?? (carryVerified ? inheritedVerifiedAt : null);

    final entry = YtmUrlCacheEntry(
      videoId: videoId,
      url: url,
      fetchedAt: now,
      expiresAt: computedExpiry,
      userAgent: effectiveUserAgent,
      cookies: effectiveCookies,
      stream: effectiveStream,
      verifiedAt: effectiveVerifiedAt,
    );

    // Evict oldest if full
    if (_cache.containsKey(key)) {
      _cache.remove(key);
    } else if (_cache.length >= _capacity && _cache.isNotEmpty) {
      _cache.remove(_cache.keys.first);
    }

    _mutationGeneration++;
    _cache[key] = entry;
    _schedulePersist();
  }

  /// Stores a resolved [YtmStream] into the LRU cache.
  ///
  /// The entry is stamped as verified at mint time: a URL the resolver just
  /// obtained from YouTube is the freshest thing this app can hold, and probing
  /// it before the first play only added a round trip (a full TLS handshake to
  /// a new edge, up to the probe's 2 s budget) to every tap on a pre-resolved
  /// track. If the signature is dead anyway, the byte fetch 403s and the lazy
  /// source's one re-resolve repairs it — the same remedy a failed probe
  /// triggers, without paying the probe on the healthy path.
  void putStream(
    YtmStream stream, {
    String quality = 'high',
  }) {
    _store(
      stream.videoId,
      stream.url,
      quality: quality,
      explicitExpiry: stream.expiresAtDateTime,
      userAgent: stream.userAgent,
      cookies: stream.cookies,
      stream: stream,
      verifiedAt: _clock.now(),
      carryVerified: false,
    );
  }

  /// Records that [videoId]'s URL at [quality] answered a probe, or served its
  /// first byte, at [at] (default: now).
  ///
  /// A no-op for a missing or expired entry: there is no URL to vouch for, and
  /// re-inserting one would resurrect an entry the cache had already dropped.
  /// The stamp stays in memory — [restore] never brings it back — because a URL
  /// that survived a launch may be bound to a previous egress or a previous
  /// attestation.
  ///
  /// Deliberately does not reorder the LRU: verification says the URL works,
  /// not that the user played it, and eviction aging should follow playback.
  void markVerified(String videoId, {String quality = 'high', DateTime? at}) {
    final key = _buildKey(videoId, quality);
    final entry = _cache[key];
    if (entry == null) return;
    final now = _clock.now();
    if (entry.isExpired(now)) {
      _cache.remove(key);
      return;
    }
    // Updating an existing LinkedHashMap key keeps its position.
    _cache[key] = entry._withVerifiedAt(at ?? now);
  }

  /// Whether [videoId]'s entry at [quality] exists, is unexpired, and was
  /// verified within [maxAge].
  ///
  /// Missing, expired, never-verified and stale all answer false: the caller's
  /// only remaining option is a probe, so one boolean is the whole question. A
  /// stamp in the future (a clock stepped backwards) counts as fresh rather
  /// than as stale. Like [contains], this is a read and does not promote the
  /// entry to MRU.
  bool isVerified(
    String videoId, {
    String quality = 'high',
    Duration maxAge = const Duration(seconds: 90),
  }) {
    final key = _buildKey(videoId, quality);
    final entry = _cache[key];
    if (entry == null) return false;
    final now = _clock.now();
    if (entry.isExpired(now)) {
      _cache.remove(key);
      return false;
    }
    final verifiedAt = entry.verifiedAt;
    if (verifiedAt == null) return false;
    return now.difference(verifiedAt) <= maxAge;
  }

  /// Invalidates entry for [videoId]. If [quality] is specified, removes exact entry.
  /// If [quality] is omitted or null, invalidates all qualities for that video.
  void invalidate(String videoId, {String? quality}) {
    if (quality != null) {
      _cache.remove(_buildKey(videoId, quality));
    } else {
      final prefix = '$videoId:';
      final keysToRemove =
          _cache.keys.where((k) => k.startsWith(prefix)).toList();
      for (final k in keysToRemove) {
        _cache.remove(k);
      }
    }
    _mutationGeneration++;
    _schedulePersist();
  }

  /// Clears entire in-memory URL cache and flushes persisted cache.
  void clear() {
    final clearGen = ++_mutationGeneration;
    _cache.clear();
    _persistTimer?.cancel();
    _persistTimer = null;
    final file = _diskFile;
    if (file != null) {
      Future<void>.microtask(() async {
        if (_mutationGeneration == clearGen && _cache.isEmpty) {
          await _persistNow(file);
        }
      });
    }
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
    } catch (e, st) {
      ErrorLogger.log('Best-effort YtmUrlCache operation failed',
          error: e, stackTrace: st, category: 'YtmUrlCache');
    }
    return null;
  }

  DateTime? _parseUrlExpiryStamp(String url) => parseUrlExpiryStamp(url);

  @disposeMethod
  void dispose() {
    final hadPendingWrite = _persistTimer != null;
    _persistTimer?.cancel();
    _persistTimer = null;
    final file = _diskFile;
    // A debounced write is the only record of URLs resolved in the last three
    // seconds; cancelling it on shutdown meant the next launch re-resolved
    // tracks this launch had already paid for.
    if (hadPendingWrite && file != null) {
      unawaited(_persistNow(file));
    }
  }
}
