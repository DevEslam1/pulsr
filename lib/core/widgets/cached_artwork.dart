import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../di/injection.dart';
import '../motion/pulsr_motion.dart';
import '../services/artwork_cache_manager.dart';
import '../utils/error_logger.dart';
import '../utils/l10n_extensions.dart';
import 'artwork_placeholder.dart';

/// LRU Memory Bitmap Cache for Artwork images.
/// Delegates to [ArtworkCacheManager] for persistent disk storage and size bounds.
class ArtworkLruCache {
  static final ArtworkLruCache _instance = ArtworkLruCache._internal();
  factory ArtworkLruCache() => _instance;
  ArtworkLruCache._internal() : maxCapacity = 200;

  ArtworkLruCache.withCapacity(this.maxCapacity);

  final int maxCapacity;
  static const int maxBytes = 50 * 1024 * 1024; // 50MB cap
  static const int largePayloadThreshold = 512 * 1024; // 512 KB
  final Map<String, Uint8List> _cache = {};
  final Map<String, WeakReference<Uint8List>> _weakLargeCache = {};
  int _currentBytes = 0;

  int get length => _cache.length + _weakLargeCache.length;
  int get currentBytes => _currentBytes;

  /// Drops [WeakReference]s whose target has been reclaimed by the GC. Without
  /// this, a key inserted once for a large payload would linger in the map
  /// forever (the strong bytes are gone, but the map entry never is).
  void _sweepDeadWeakEntries() {
    _weakLargeCache.removeWhere((_, ref) => ref.target == null);
  }

  bool containsKey(String key) {
    if (_cache.containsKey(key)) return true;
    final weak = _weakLargeCache[key];
    if (weak != null && weak.target != null) return true;
    return false;
  }

  Uint8List? get(String key) {
    if (_cache.containsKey(key)) {
      final value = _cache.remove(key);
      if (value != null) {
        _cache[key] = value;
      }
      return value;
    }
    final weak = _weakLargeCache[key];
    if (weak != null) {
      final target = weak.target;
      if (target == null) {
        _weakLargeCache.remove(key);
        return null;
      }
      return target;
    }
    return null;
  }

  void put(String key, Uint8List? bytes, {bool persistToDisk = true}) {
    if (bytes == null || bytes.isEmpty) {
      remove(key);
      return;
    }
    // A single image larger than the whole byte budget can never fit; adding it
    // after the eviction loop would leave the cache permanently over cap.
    if (bytes.length > maxBytes) {
      remove(key);
      return;
    }

    // FIX-F2: Large payloads (>512KB) are held via WeakReference so memory pressure can reclaim them
    if (bytes.length > largePayloadThreshold) {
      // Re-inserting a key must not count against the weak-key cap.
      _weakLargeCache.remove(key);
      // Sweep reclaimed targets, then bound the number of live weak keys so a
      // stream of transient large payloads cannot leak map entries.
      _sweepDeadWeakEntries();
      while (_weakLargeCache.length >= maxCapacity &&
          _weakLargeCache.isNotEmpty) {
        _weakLargeCache.remove(_weakLargeCache.keys.first);
      }
      _weakLargeCache[key] = WeakReference(bytes);
      if (persistToDisk) {
        ArtworkCacheManager().put(key, bytes);
      }
      return;
    }

    final existing = _cache.remove(key);
    if (existing != null) {
      _currentBytes -= existing.length;
    }

    // Evict LRU until within both count and bytes bounds (maxCapacity is inclusive)
    while ((_cache.length >= maxCapacity ||
            _currentBytes + bytes.length > maxBytes) &&
        _cache.isNotEmpty) {
      final oldestKey = _cache.keys.first;
      final removed = _cache.remove(oldestKey);
      if (removed != null) {
        _currentBytes -= removed.length;
      }
    }

    _cache[key] = bytes;
    _currentBytes += bytes.length;
    if (persistToDisk) {
      ArtworkCacheManager().put(key, bytes);
    }
  }

  void remove(String key) {
    _weakLargeCache.remove(key);
    final removed = _cache.remove(key);
    if (removed != null) {
      _currentBytes -= removed.length;
    }
  }

  void clear() {
    _cache.clear();
    _weakLargeCache.clear();
    _currentBytes = 0;
    ArtworkCacheManager().clearAllCache();
  }

  void trimForMemoryPressure() {
    _weakLargeCache.clear();
    // Evict half of cache on memory pressure (LOG-14 GC 14MB/59MB)
    while (_cache.length > maxCapacity ~/ 2 && _cache.isNotEmpty) {
      final oldest = _cache.keys.first;
      final removed = _cache.remove(oldest);
      if (removed != null) _currentBytes -= removed.length;
    }
    while (_currentBytes > maxBytes ~/ 2 && _cache.isNotEmpty) {
      final oldest = _cache.keys.first;
      final removed = _cache.remove(oldest);
      if (removed != null) _currentBytes -= removed.length;
    }
  }
}

/// Broadcasts an in-place artwork change so already-mounted [CachedArtwork]s
/// re-resolve their bitmap. Widgets whose cache key survived the invalidation
/// ignore the notification, so unrelated artwork is never blanked.
class ArtworkInvalidationBus {
  ArtworkInvalidationBus._();
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
}

class CachedArtwork extends StatefulWidget {
  final int id;
  final ArtworkType type;
  final double size;
  final double borderRadius;
  final IconData? fallbackIcon;
  final ArtworkLruCache? customCache;

  /// HTTPS cover art for a row that has no MediaStore id, i.e. a YouTube track
  /// that has not been downloaded yet. Takes precedence over [id].
  final String? remoteUrl;

  final bool highQuality;

  /// Explicit decode dimensions. Defaults to [decodeDim] computed from widget.size.
  final int? cacheWidth;
  final int? cacheHeight;

  /// MediaStore album ID used as a fallback when the song's own artwork query
  /// returns null. Must be [song.albumId] — NOT the song id.
  final int? albumId;

  const CachedArtwork({
    super.key,
    required this.id,
    this.type = ArtworkType.AUDIO,
    this.size = 48.0,
    this.borderRadius = 12.0,
    this.fallbackIcon,
    this.customCache,
    this.remoteUrl,
    this.highQuality = false,
    this.cacheWidth,
    this.cacheHeight,
    this.albumId,
  });

  /// Drops every cached quality tier for [type]/[id] and notifies mounted
  /// widgets. Call after rewriting a file's embedded cover so the new image is
  /// shown instead of the stale cached bitmap.
  static Future<void> invalidate({
    required int id,
    ArtworkType type = ArtworkType.AUDIO,
  }) async {
    final base = '${type.name}_$id';
    for (final key in [base, '${base}_hq']) {
      ArtworkLruCache().remove(key);
      // Best-effort disk eviction: never let an unresponsive platform path
      // provider stall the caller (e.g. the tag-save flow).
      await ArtworkCacheManager()
          .remove(key)
          .timeout(const Duration(seconds: 2), onTimeout: () {});
    }
    ArtworkInvalidationBus.revision.value++;
  }

  static String upgradeToHighResArtwork(String url) {
    var upgraded = url;
    if (upgraded.contains('googleusercontent.com') ||
        upgraded.contains('ggpht.com')) {
      upgraded = upgraded.replaceAll(RegExp(r'=w\d+-h\d+[^?]*'), '=s1200');
      upgraded = upgraded.replaceAll(RegExp(r'=s\d+[^?]*'), '=s1200');
    } else if (upgraded.contains('i.ytimg.com') ||
        upgraded.contains('img.youtube.com')) {
      upgraded = upgraded.replaceAll(
          RegExp(r'/(default|mqdefault|hqdefault|sddefault|hq720)\.jpg'),
          '/maxresdefault.jpg');
    }
    return upgraded;
  }

  @override
  State<CachedArtwork> createState() => _CachedArtworkState();
}

class _CachedArtworkState extends State<CachedArtwork> {
  static final OnAudioQuery _audioQuery = OnAudioQuery();
  static const int _maxRemoteBytes =
      10 * 1024 * 1024; // 10 MB max for HQ covers
  Uint8List? _cachedBytes;
  int _loadToken = 0;

  /// De-dupes concurrent cold-cache fetches: multiple widgets requesting the
  /// same resolved cache key share a single underlying bytes fetch instead of
  /// each issuing its own remote/device query.
  // NOTE: _inFlight deduplication was removed — sharing a Future caused all
  // widgets to get null when the first fetch failed (e.g. slow network on
  // initial load), leaving every card stuck with a placeholder permanently.
  // Direct per-widget fetches are simpler and more reliable.

  bool get _isHighRes =>
      widget.highQuality || (widget.size.isFinite && widget.size > 250);

  ArtworkLruCache get _cache => widget.customCache ?? ArtworkLruCache();

  String get _baseKey => widget.remoteUrl ?? '${widget.type.name}_${widget.id}';

  String get _cacheKey => _isHighRes ? '${_baseKey}_hq' : _baseKey;

  int _lastArtworkRevision = 0;

  @override
  void initState() {
    super.initState();
    _lastArtworkRevision = ArtworkInvalidationBus.revision.value;
    ArtworkInvalidationBus.revision.addListener(_onArtworkInvalidated);
    _loadArtwork();
  }

  void _onArtworkInvalidated() {
    final revision = ArtworkInvalidationBus.revision.value;
    if (revision == _lastArtworkRevision) return;
    _lastArtworkRevision = revision;
    // Only widgets whose key was evicted need to reload; unaffected artwork
    // keeps its bitmap and skips the rebuild entirely.
    if (_cache.containsKey(_cacheKey)) return;
    _cachedBytes = null;
    _loadToken++;
    if (mounted) setState(() {});
    _loadArtwork();
  }

  @override
  void didUpdateWidget(CachedArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id ||
        oldWidget.type != widget.type ||
        oldWidget.remoteUrl != widget.remoteUrl ||
        oldWidget.highQuality != widget.highQuality ||
        oldWidget.size != widget.size ||
        oldWidget.albumId != widget.albumId) {
      _loadToken++;
      final nextKey = _cacheKey;
      if (_cache.containsKey(nextKey)) {
        _cachedBytes = _cache.get(nextKey);
      } else {
        _cachedBytes = null;
      }
      _loadArtwork();
    }
  }

  @override
  void dispose() {
    ArtworkInvalidationBus.revision.removeListener(_onArtworkInvalidated);
    super.dispose();
  }

  static Future<Uint8List?> _fetchRemote(String url,
      {bool highQuality = false, bool lowQuality = false}) async {
    if (url.startsWith('file://')) {
      try {
        final file = File(Uri.parse(url).toFilePath());
        if (await file.exists()) {
          return await file.readAsBytes();
        }
      } catch (_) {}
      return null;
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      try {
        final file = File(url);
        if (await file.exists()) {
          return await file.readAsBytes();
        }
      } catch (_) {}
    }

    final targetUrl = highQuality
        ? CachedArtwork.upgradeToHighResArtwork(url)
        : (lowQuality
            ? ArtworkCacheManager.toLowQualityArtworkUrl(url,
                width: 220, height: 220)
            : url);

    final uri = Uri.tryParse(targetUrl);
    if (uri == null || (!uri.isScheme('https') && !uri.isScheme('http'))) return null;
    HttpClientRequest? request;
    try {
      request = await getIt<HttpClient>()
          .getUrl(uri)
          .timeout(const Duration(seconds: 8));
      var response = await request.close().timeout(const Duration(seconds: 8));

      // Fall back through candidate URLs if high-res variant returned non-200
      if (response.statusCode != 200 && targetUrl != url) {
        await response.drain<void>();

        // If maxresdefault failed on YouTube, try sddefault then original
        final fallbackUrls = <String>[];
        if (targetUrl.contains('maxresdefault.jpg')) {
          fallbackUrls
              .add(targetUrl.replaceAll('maxresdefault.jpg', 'sddefault.jpg'));
          fallbackUrls
              .add(targetUrl.replaceAll('maxresdefault.jpg', 'hqdefault.jpg'));
        }
        fallbackUrls.add(url);

        bool resolved = false;
        for (final candidate in fallbackUrls) {
          final candidateUri = Uri.tryParse(candidate);
          if (candidateUri == null) continue;
          HttpClientRequest? fallbackReq;
          try {
            fallbackReq = await getIt<HttpClient>()
                .getUrl(candidateUri)
                .timeout(const Duration(seconds: 6));
            request = fallbackReq;
            response =
                await fallbackReq.close().timeout(const Duration(seconds: 6));
            if (response.statusCode == 200) {
              resolved = true;
              break;
            } else {
              await response.drain<void>();
            }
          } catch (e, st) {
            ErrorLogger.log('Candidate artwork URL failed',
                error: e, stackTrace: st, category: 'Artwork');
            try {
              fallbackReq?.abort();
            } catch (abortErr, abortSt) {
              ErrorLogger.log('Failed to abort fallback request',
                  error: abortErr, stackTrace: abortSt, category: 'Artwork');
            }
          }
        }
        if (!resolved || response.statusCode != 200) return null;
      }

      if (response.statusCode != 200 ||
          (response.contentLength > 0 &&
              response.contentLength > _maxRemoteBytes)) {
        await response.drain<void>();
        return null;
      }
      final builder = BytesBuilder(copy: false);
      var totalBytes = 0;
      await for (final chunk in response.timeout(const Duration(seconds: 8))) {
        totalBytes += chunk.length;
        if (totalBytes > _maxRemoteBytes) {
          try {
            request?.abort();
          } catch (abortErr, abortSt) {
            ErrorLogger.log('Failed to abort oversized request',
                error: abortErr, stackTrace: abortSt, category: 'Artwork');
          }
          return null;
        }
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      if (bytes.lengthInBytes > _maxRemoteBytes || bytes.isEmpty) return null;
      return bytes;
    } catch (e, st) {
      ErrorLogger.log('Remote artwork fetch failed',
          error: e, stackTrace: st, category: 'Artwork');
      try {
        request?.abort();
      } catch (abortErr, abortSt) {
        ErrorLogger.log('Failed to abort remote request',
            error: abortErr, stackTrace: abortSt, category: 'Artwork');
      }
      return null;
    }
  }

  Future<void> _loadArtwork() async {
    final key = _cacheKey;
    final baseKey = _baseKey;
    final token = ++_loadToken;
    final isHq = _isHighRes;

    // 1. Check in-memory LRU cache for target key
    if (_cache.containsKey(key)) {
      // Assign directly: if called from initState (before mount), setState would
      // be silently ignored, leaving _cachedBytes null and showing a placeholder.
      // The initial build() reads _cachedBytes directly after initState returns.
      // If called after mount (didUpdateWidget / invalidation), schedule rebuild.
      _cachedBytes = _cache.get(key);
      if (mounted) setState(() {});
      return;
    }

    // Progressive loading: if HQ requested, immediately show existing low-res thumbnail
    // to avoid any blank or flashing UI while HQ is asynchronously queried/decoded.
    if (isHq && _cache.containsKey(baseKey)) {
      _cachedBytes = _cache.get(baseKey);
      if (mounted) setState(() {});
    }

    // 2. Check persistent disk cache for target key
    final diskBytes = await ArtworkCacheManager().get(key);
    if (diskBytes != null && diskBytes.isNotEmpty) {
      if (mounted && token == _loadToken) {
        _cache.put(key, diskBytes, persistToDisk: false);
        setState(() {
          _cachedBytes = diskBytes;
        });
      }
      return;
    }

    // If HQ disk cache is empty, check base disk cache as intermediate preview
    if (isHq && _cachedBytes == null) {
      final baseDiskBytes = await ArtworkCacheManager().get(baseKey);
      if (baseDiskBytes != null &&
          baseDiskBytes.isNotEmpty &&
          mounted &&
          token == _loadToken) {
        _cache.put(baseKey, baseDiskBytes, persistToDisk: false);
        setState(() {
          _cachedBytes = baseDiskBytes;
        });
      }
    }

    // 3. Fetch remote or query local storage (each widget fetches independently
    //    — no shared in-flight Future — so a single failure does not block
    //    every other card on screen from eventually loading its artwork).
    final remoteUrl = widget.remoteUrl;
    final isThumbnail = !isHq && widget.size <= 220;

    Future<Uint8List?> pending;
    if (remoteUrl != null && remoteUrl.isNotEmpty) {
      pending = _fetchRemote(
        remoteUrl,
        highQuality: isHq,
        lowQuality: isThumbnail,
      ).then((remoteBytes) {
        if (remoteBytes != null && remoteBytes.isNotEmpty) return remoteBytes;
        if (widget.id > 0) {
          // Fallback to device artwork when remote fetch fails / returns empty.
          return _audioQuery.queryArtwork(
            widget.id,
            widget.type,
            format: ArtworkFormat.JPEG,
            size: isHq ? 1000 : (isThumbnail ? 180 : 350),
            quality: isHq ? 100 : (isThumbnail ? 65 : 80),
          );
        }
        return null;
      });
    } else {
      if (widget.id > 0) {
        pending = _audioQuery
            .queryArtwork(
              widget.id,
              widget.type,
              format: ArtworkFormat.JPEG,
              size: isHq ? 1000 : (isThumbnail ? 180 : 350),
              quality: isHq ? 100 : (isThumbnail ? 65 : 80),
            )
            .then((bytes) async {
          if (bytes != null && bytes.isNotEmpty) return bytes;
          // Fallback: try album artwork with the correct MediaStore album ID.
          final fallbackAlbumId = widget.albumId;
          if (widget.type == ArtworkType.AUDIO &&
              fallbackAlbumId != null &&
              fallbackAlbumId > 0) {
            return _audioQuery.queryArtwork(
              fallbackAlbumId,
              ArtworkType.ALBUM,
              format: ArtworkFormat.JPEG,
              size: isHq ? 1000 : (isThumbnail ? 180 : 350),
              quality: isHq ? 100 : (isThumbnail ? 65 : 80),
            );
          }
          return null;
        });
      } else {
        pending = Future<Uint8List?>.value(null);
      }
    }

    pending.then((bytes) {
      if (mounted && token == _loadToken) {
        if (bytes != null && bytes.isNotEmpty) {
          _cache.put(key, bytes);
          setState(() {
            _cachedBytes = bytes;
          });
        }
      }
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final isBounded = widget.size.isFinite && widget.size > 0;
    final effectiveBorderRadius =
        widget.borderRadius.isFinite ? widget.borderRadius : 12.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final hasBoundedConstraints =
            constraints.biggest.shortestSide.isFinite &&
                constraints.biggest.shortestSide > 0;
        final effectiveSize = isBounded
            ? widget.size
            : (hasBoundedConstraints
                ? constraints.biggest.shortestSide
                : 200.0);

        // Always resolve a finite extent. A null extent (unbounded parent or a
        // `size: double.infinity` request) left the ClipRRect/SizedBox without
        // a size, cascading into "RenderBox was not laid out" crashes. The
        // hundreds/tiny fallbacks keep the box finite in every context.
        final double extent = effectiveSize;

        final placeholder = ArtworkPlaceholder(
          size: extent,
          borderRadius: effectiveBorderRadius,
          icon: widget.fallbackIcon,
        );

        final isHq = _isHighRes;
        final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
        final decodeDim = isHq
            ? (effectiveSize * dpr).clamp(300, 1440).round()
            : (effectiveSize * dpr).clamp(80, 800).round();

        final content = AnimatedSwitcher(
          duration: context.motionMs(200),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: _cachedBytes != null
              ? Image.memory(
                  _cachedBytes!,
                  key: ValueKey(_cacheKey),
                  width: extent,
                  height: extent,
                  cacheWidth: widget.cacheWidth ?? decodeDim,
                  cacheHeight: widget.cacheHeight ?? decodeDim,
                  fit: BoxFit.cover,
                  filterQuality:
                      isHq ? FilterQuality.high : FilterQuality.medium,
                  errorBuilder: (context, error, stackTrace) => placeholder,
                )
              : SizedBox(
                  key: const ValueKey('artwork_placeholder'),
                  width: extent,
                  height: extent,
                  child: placeholder,
                ),
        );

        return ClipRRect(
          borderRadius: BorderRadius.circular(effectiveBorderRadius),
          child: SizedBox(
            width: extent,
            height: extent,
            child: Semantics(
              label: context.l10n.albumArtworkLabel,
              image: true,
              child: content,
            ),
          ),
        );
      },
    );
  }
}
