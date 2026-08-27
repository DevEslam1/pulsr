// lib/core/widgets/cached_artwork.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../di/injection.dart';
import '../services/artwork_cache_manager.dart';
import 'artwork_placeholder.dart';

/// LRU Memory Bitmap Cache for Artwork images.
/// Delegates to [ArtworkCacheManager] for persistent disk storage and size bounds.
class ArtworkLruCache {
  static final ArtworkLruCache _instance = ArtworkLruCache._internal();
  factory ArtworkLruCache() => _instance;
  ArtworkLruCache._internal() : maxCapacity = 200;

  ArtworkLruCache.withCapacity(this.maxCapacity);

  final int maxCapacity;
  final Map<String, Uint8List?> _cache = {};

  int get length => _cache.length;

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
      _cache.remove(key);
      return;
    }
    if (_cache.containsKey(key)) {
      _cache.remove(key);
    } else if (_cache.length >= maxCapacity) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = bytes;
    ArtworkCacheManager().put(key, bytes);
  }

  void remove(String key) {
    _cache.remove(key);
  }

  void clear() {
    _cache.clear();
    ArtworkCacheManager().clearAllCache();
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
    if (upgraded.contains('googleusercontent.com') || upgraded.contains('ggpht.com')) {
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

  String get _cacheKey => widget.remoteUrl ?? '${widget.type.name}_${widget.id}';

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
      _loadArtwork();
    }
  }

  static Future<Uint8List?> _fetchRemote(String url, {bool lowQuality = true}) async {
    final targetUrl = lowQuality
        ? ArtworkCacheManager.toLowQualityArtworkUrl(url, width: 220, height: 220)
        : CachedArtwork.upgradeToHighResArtwork(url);

    var uri = Uri.tryParse(targetUrl);
    if (uri == null || !uri.isScheme('https')) return null;
    try {
      var request = await getIt<HttpClient>().getUrl(uri);
      var response = await request.close().timeout(const Duration(seconds: 8));

      // Fall back to original URL if low-res or transformed URL returned non-200
      if (response.statusCode != 200 && targetUrl != url) {
        await response.drain<void>();
        final fallbackUri = Uri.tryParse(url);
        if (fallbackUri != null) {
          request = await getIt<HttpClient>().getUrl(fallbackUri);
          response = await request.close().timeout(const Duration(seconds: 8));
        }
      }

      if (response.statusCode != 200 || response.contentLength > _maxRemoteBytes) {
        await response.drain<void>();
        return null;
      }
      return consolidateHttpClientResponseBytes(response);
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadArtwork() async {
    final key = _cacheKey;
    final token = ++_loadToken;

    // 1. Check in-memory LRU cache
    if (_cache.containsKey(key)) {
      setState(() {
        _cachedBytes = _cache.get(key);
      });
      return;
    }

    // 2. Check persistent disk cache
    final diskBytes = await ArtworkCacheManager().get(key);
    if (diskBytes != null && diskBytes.isNotEmpty) {
      if (mounted && token == _loadToken) {
        _cache.put(key, diskBytes);
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
      pending = _fetchRemote(remoteUrl, lowQuality: isThumbnail).then((remoteBytes) {
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

    pending.then((bytes) {
      if (mounted && token == _loadToken) {
        if (bytes != null && bytes.isNotEmpty) {
          _cache.put(key, bytes);
          ArtworkCacheManager().put(key, bytes);
        }
        setState(() {
          _cachedBytes = bytes;
        });
      }
    }).catchError((_) {
      if (mounted && token == _loadToken) {
        setState(() {
          _cachedBytes = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isBounded = widget.size.isFinite && widget.size > 0;
    final effectiveBorderRadius = widget.borderRadius.isFinite ? widget.borderRadius : 12.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final effectiveSize = isBounded
            ? widget.size
            : (constraints.biggest.shortestSide.isFinite && constraints.biggest.shortestSide > 0
                ? constraints.biggest.shortestSide
                : 200.0);

        final placeholder = ArtworkPlaceholder(
          size: isBounded ? effectiveSize : double.infinity,
          borderRadius: effectiveBorderRadius,
          icon: widget.fallbackIcon,
        );

        final decodeDim = (effectiveSize * 1.5).clamp(80, 800).round();

        final content = _cachedBytes != null
            ? Image.memory(
                _cachedBytes!,
                width: isBounded ? effectiveSize : null,
                height: isBounded ? effectiveSize : null,
                cacheWidth: decodeDim,
                cacheHeight: decodeDim,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
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
