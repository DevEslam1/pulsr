// lib/core/widgets/cached_artwork.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:pulsr/data/services/artwork_cache_manager.dart';
import '../di/injection.dart';
import 'artwork_placeholder.dart';

import '../utils/error_logger.dart';
/// LRU Memory Bitmap Cache for Artwork images.
/// Delegates to [ArtworkCacheManager] for persistent disk storage and size bounds.
class ArtworkLruCache {
  static final ArtworkLruCache _instance = ArtworkLruCache._internal();
  factory ArtworkLruCache() => _instance;
  ArtworkLruCache._internal() : _maxCapacity = 200;

  // FIX(B5): ArtworkLruCache.withCapacity mutates singleton capacity to prevent multiple disconnected caches
  factory ArtworkLruCache.withCapacity(int capacity) {
    _instance.maxCapacity = capacity;
    return _instance;
  }

  int _maxCapacity;
  int get maxCapacity => _maxCapacity;
  set maxCapacity(int capacity) {
    _maxCapacity = capacity;
    while (_cache.length > _maxCapacity && _cache.isNotEmpty) {
      final oldestKey = _cache.keys.first;
      final removed = _cache.remove(oldestKey);
      if (removed != null) {
        _currentBytes -= removed.length;
      }
    }
  }

  static const int maxBytes = 50 * 1024 * 1024; // 50MB cap
  final Map<String, Uint8List> _cache = {};
  int _currentBytes = 0;

  int get length => _cache.length;
  int get currentBytes => _currentBytes;

  bool containsKey(String key) => _cache.containsKey(key);

  Uint8List? get(String key) {
    if (!_cache.containsKey(key)) return null;
    final value = _cache.remove(key);
    if (value != null) {
      _cache[key] = value;
    }
    return value;
  }

  void put(String key, Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) {
      remove(key);
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
    ArtworkCacheManager().put(key, bytes);
  }

  void remove(String key) {
    final removed = _cache.remove(key);
    if (removed != null) {
      _currentBytes -= removed.length;
    }
  }

  void clear() {
    _cache.clear();
    _currentBytes = 0;
    ArtworkCacheManager().clearAllCache();
  }

  void trimForMemoryPressure() {
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

  const CachedArtwork({
    super.key,
    required this.id,
    this.type = ArtworkType.AUDIO,
    this.size = 48.0,
    this.borderRadius = 12.0,
    this.fallbackIcon,
    this.customCache,
    this.remoteUrl,
  });

  static String upgradeToHighResArtwork(String url) {
    var upgraded = url;
    if (upgraded.contains('googleusercontent.com') ||
        upgraded.contains('ggpht.com')) {
      upgraded = upgraded.replaceAll(RegExp(r'=w\d+-h\d+[^?]*'), '=s1200');
      upgraded = upgraded.replaceAll(RegExp(r'=s\d+[^?]*'), '=s1200');
    }
    return upgraded;
  }

  @override
  State<CachedArtwork> createState() => _CachedArtworkState();
}

class _CachedArtworkState extends State<CachedArtwork> {
  static final OnAudioQuery _audioQuery = OnAudioQuery();
  static const int _maxRemoteBytes = 2 * 1024 * 1024; // 2 MB max
  Uint8List? _cachedBytes;
  int _loadToken = 0;

  ArtworkLruCache get _cache => widget.customCache ?? ArtworkLruCache();

  String get _cacheKey =>
      widget.remoteUrl ?? '${widget.type.name}_${widget.id}';

  @override
  void initState() {
    super.initState();
    _loadArtwork();
  }

  @override
  void didUpdateWidget(CachedArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id ||
        oldWidget.type != widget.type ||
        oldWidget.remoteUrl != widget.remoteUrl) {
      _loadToken++;
      _loadArtwork();
    }
  }

  static Future<Uint8List?> _fetchRemote(
    String url, {
    bool lowQuality = true,
  }) async {
    final targetUrl =
        lowQuality
            ? ArtworkCacheManager.toLowQualityArtworkUrl(
              url,
              width: 220,
              height: 220,
            )
            : CachedArtwork.upgradeToHighResArtwork(url);

    var uri = Uri.tryParse(targetUrl);
    if (uri == null || !uri.isScheme('https')) return null;
    HttpClientRequest? request;
    try {
      // Respects proxy via AppHttpOverrides.global — getIt<HttpClient> is created
      // through AppHttpOverrides.createHttpClient so findProxy/authenticateProxy are applied.
      request = await getIt<HttpClient>()
          .getUrl(uri)
          .timeout(const Duration(seconds: 8));
      var response = await request.close().timeout(const Duration(seconds: 8));

      // Fall back to original URL if low-res or transformed URL returned non-200
      if (response.statusCode != 200 && targetUrl != url) {
        await response.drain<void>();
        final fallbackUri = Uri.tryParse(url);
        if (fallbackUri != null) {
          // Also respects proxy via AppHttpOverrides.global
          request = await getIt<HttpClient>()
              .getUrl(fallbackUri)
              .timeout(const Duration(seconds: 8));
          response = await request.close().timeout(const Duration(seconds: 8));
        }
      }

      if (response.statusCode != 200 ||
          response.contentLength > _maxRemoteBytes) {
        await response.drain<void>();
        return null;
      }
      final bytes = await consolidateHttpClientResponseBytes(
        response,
      ).timeout(const Duration(seconds: 8));
      if (bytes.lengthInBytes > _maxRemoteBytes) return null;
      return bytes;
    } catch (e, st) {
      ErrorLogger.log('_fetchRemote failed, using fallback', error: e, stackTrace: st, category: 'CachedArtwork');
      try {
        request?.abort();
      } catch (e, st) {
        ErrorLogger.log('_fetchRemote failed', error: e, stackTrace: st, category: 'CachedArtwork');
      }
      return null;
    }
  }

  Future<void> _loadArtwork() async {
    final key = _cacheKey;
    final token = ++_loadToken;

    // 1. Check in-memory LRU cache
    if (_cache.containsKey(key)) {
      if (!mounted || token != _loadToken) return;
      final memBytes = _cache.get(key);
      // Guard: only set state when mounted and bytes are valid
      if (memBytes != null && memBytes.isNotEmpty) {
        setState(() {
          _cachedBytes = memBytes;
        });
      }
      return;
    }

    // 2. Check persistent disk cache
    final diskBytes = await ArtworkCacheManager().get(key);
    if (diskBytes != null && diskBytes.isNotEmpty) {
      if (!mounted || token != _loadToken) return;
      // Guard ArtworkLruCache.put with non-empty check (cache caps at 50MB/200 entries)
      _cache.put(key, diskBytes);
      if (mounted && token == _loadToken) {
        setState(() {
          _cachedBytes = diskBytes;
        });
      }
      return;
    }

    // 3. Fetch remote or query local storage in low-medium quality
    final remoteUrl = widget.remoteUrl;
    final isThumbnail = widget.size <= 220;

    Future<Uint8List?> pending;
    if (remoteUrl != null && remoteUrl.isNotEmpty) {
      pending = _fetchRemote(remoteUrl, lowQuality: isThumbnail).then((
        remoteBytes,
      ) {
        if (remoteBytes != null && remoteBytes.isNotEmpty) return remoteBytes;
        if (widget.id > 0) {
          return _audioQuery.queryArtwork(
            widget.id,
            widget.type,
            format: ArtworkFormat.JPEG,
            size: isThumbnail ? 180 : 350,
            quality: isThumbnail ? 65 : 80,
          );
        }
        return null;
      });
    } else {
      pending = _audioQuery.queryArtwork(
        widget.id,
        widget.type,
        format: ArtworkFormat.JPEG,
        size: isThumbnail ? 180 : 350,
        quality: isThumbnail ? 65 : 80,
      );
    }

    unawaited(
      pending
          .then((bytes) {
            if (!mounted || token != _loadToken) return;
            // Guard ArtworkLruCache.put: only cache valid non-empty artwork
            if (bytes != null && bytes.isNotEmpty) {
              _cache.put(key, bytes);
            }
            if (mounted && token == _loadToken) {
              setState(() {
                _cachedBytes = bytes;
              });
            }
          })
          .catchError((_) {
            if (!mounted || token != _loadToken) return;
            if (mounted && token == _loadToken) {
              setState(() {
                _cachedBytes = null;
              });
            }
          }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isBounded = widget.size.isFinite && widget.size > 0;
    final effectiveBorderRadius =
        widget.borderRadius.isFinite ? widget.borderRadius : 12.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final effectiveSize =
            isBounded
                ? widget.size
                : (constraints.biggest.shortestSide.isFinite &&
                        constraints.biggest.shortestSide > 0
                    ? constraints.biggest.shortestSide
                    : 200.0);

        final placeholder = ArtworkPlaceholder(
          size: isBounded ? effectiveSize : double.infinity,
          borderRadius: effectiveBorderRadius,
          icon: widget.fallbackIcon,
        );

        // Fine-grained DPR dependency (F-11): full MediaQuery.of here would
        // rebuild every artwork item on any MediaQuery change.
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final decodeDim = (effectiveSize * dpr).clamp(80, 600).round();

        final content =
            _cachedBytes != null
                ? Image.memory(
                  _cachedBytes!,
                  width: isBounded ? effectiveSize : null,
                  height: isBounded ? effectiveSize : null,
                  cacheWidth: decodeDim,
                  cacheHeight: decodeDim,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                  // Keep the previous frame while the new one decodes (F-11):
                  // no flicker on song change in NowPlaying.
                  gaplessPlayback: true,
                  errorBuilder: (context, error, stackTrace) => placeholder,
                )
                : placeholder;

        return ClipRRect(
          borderRadius: BorderRadius.circular(effectiveBorderRadius),
          child: SizedBox(
            width: isBounded ? effectiveSize : null,
            height: isBounded ? effectiveSize : null,
            child: Semantics(
              label: 'Album artwork',
              image: true,
              child: content,
            ),
          ),
        );
      },
    );
  }
}
