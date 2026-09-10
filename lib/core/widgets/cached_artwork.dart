import 'dart:io';
import 'dart:typed_data';
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

  void put(String key, Uint8List? bytes, {bool persistToDisk = true}) {
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
    if (persistToDisk) {
      ArtworkCacheManager().put(key, bytes);
    }
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

  /// Whether to fetch and render uncompressed/high-resolution artwork (e.g. for player screen).
  final bool highQuality;

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
  });

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
  static const int _maxRemoteBytes = 10 * 1024 * 1024; // 10 MB max for HQ covers
  Uint8List? _cachedBytes;
  int _loadToken = 0;

  bool get _isHighRes =>
      widget.highQuality || widget.size > 250 || widget.size == double.infinity;

  ArtworkLruCache get _cache => widget.customCache ?? ArtworkLruCache();

  String get _baseKey =>
      widget.remoteUrl ?? '${widget.type.name}_${widget.id}';

  String get _cacheKey => _isHighRes ? '${_baseKey}_hq' : _baseKey;

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
        oldWidget.remoteUrl != widget.remoteUrl ||
        oldWidget.highQuality != widget.highQuality ||
        oldWidget.size != widget.size) {
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

  static Future<Uint8List?> _fetchRemote(String url,
      {bool highQuality = false, bool lowQuality = false}) async {
    final targetUrl = highQuality
        ? CachedArtwork.upgradeToHighResArtwork(url)
        : (lowQuality
            ? ArtworkCacheManager.toLowQualityArtworkUrl(url,
                width: 220, height: 220)
            : url);

    var uri = Uri.tryParse(targetUrl);
    if (uri == null || !uri.isScheme('https')) return null;
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
          fallbackUrls.add(targetUrl.replaceAll('maxresdefault.jpg', 'sddefault.jpg'));
          fallbackUrls.add(targetUrl.replaceAll('maxresdefault.jpg', 'hqdefault.jpg'));
        }
        fallbackUrls.add(url);

        bool resolved = false;
        for (final candidate in fallbackUrls) {
          final candidateUri = Uri.tryParse(candidate);
          if (candidateUri == null) continue;
          try {
            request = await getIt<HttpClient>()
                .getUrl(candidateUri)
                .timeout(const Duration(seconds: 6));
            response =
                await request.close().timeout(const Duration(seconds: 6));
            if (response.statusCode == 200) {
              resolved = true;
              break;
            } else {
              await response.drain<void>();
            }
          } catch (_) {}
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
          } catch (_) {}
          return null;
        }
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      if (bytes.lengthInBytes > _maxRemoteBytes || bytes.isEmpty) return null;
      return bytes;
    } catch (_) {
      try {
        request?.abort();
      } catch (_) {}
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
      setState(() {
        _cachedBytes = _cache.get(key);
      });
      return;
    }

    // Progressive loading: if HQ requested, immediately show existing low-res thumbnail
    // to avoid any blank or flashing UI while HQ is asynchronously queried/decoded.
    if (isHq && _cache.containsKey(baseKey)) {
      _cachedBytes = _cache.get(baseKey);
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
      if (baseDiskBytes != null && baseDiskBytes.isNotEmpty && mounted && token == _loadToken) {
        _cache.put(baseKey, baseDiskBytes, persistToDisk: false);
        setState(() {
          _cachedBytes = baseDiskBytes;
        });
      }
    }

    // 3. Fetch remote or query local storage
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
      pending = widget.id > 0
          ? _audioQuery.queryArtwork(
              widget.id,
              widget.type,
              format: ArtworkFormat.JPEG,
              size: isHq ? 1000 : (isThumbnail ? 180 : 350),
              quality: isHq ? 100 : (isThumbnail ? 65 : 80),
            )
          : Future<Uint8List?>.value(null);
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
        final effectiveSize = isBounded
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

        final isHq = _isHighRes;
        final decodeDim = isHq
            ? null
            : (effectiveSize * 1.5).clamp(80, 800).round();

        final content = _cachedBytes != null
            ? Image.memory(
                _cachedBytes!,
                width: isBounded ? effectiveSize : null,
                height: isBounded ? effectiveSize : null,
                cacheWidth: decodeDim,
                cacheHeight: decodeDim,
                fit: BoxFit.cover,
                filterQuality:
                    isHq ? FilterQuality.high : FilterQuality.medium,
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
