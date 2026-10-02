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
  static const int _maxRemoteBytes =
      10 * 1024 * 1024; // 10 MB max for HQ covers
  Uint8List? _cachedBytes;
  int _loadToken = 0;

  /// De-dupes concurrent cold-cache fetches: multiple widgets requesting the
  /// same resolved cache key share a single underlying bytes fetch instead of
  /// each issuing its own remote/device query.
  static final Map<String, Future<Uint8List?>> _inFlight = {};

  bool get _isHighRes =>
      widget.highQuality || (widget.size.isFinite && widget.size > 250);

  ArtworkLruCache get _cache => widget.customCache ?? ArtworkLruCache();

  String get _baseKey => widget.remoteUrl ?? '${widget.type.name}_${widget.id}';

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

    // 3. Fetch remote or query local storage.
    // In-flight dedupe: concurrent widgets requesting the same resolved cache
    // key share one underlying raw-bytes fetch. Each widget still applies its
    // own cache.put + setState under its own load token below.
    final remoteUrl = widget.remoteUrl;
    final isThumbnail = !isHq && widget.size <= 220;

    Future<Uint8List?> pending;
    final existingInFlight = _inFlight[key];
    if (existingInFlight != null) {
      pending = existingInFlight;
    } else {
      final Future<Uint8List?> fetch;
      if (remoteUrl != null && remoteUrl.isNotEmpty) {
        fetch = _fetchRemote(
          remoteUrl,
          highQuality: isHq,
          lowQuality: isThumbnail,
        ).then((remoteBytes) {
          if (remoteBytes != null && remoteBytes.isNotEmpty) return remoteBytes;
          if (widget.id > 0) {
            return _queryDeviceArtwork(
              widget.id,
              widget.type,
              isHq: isHq,
              isThumbnail: isThumbnail,
            );
          }
          return null;
        });
      } else {
        fetch = widget.id > 0
            ? _queryDeviceArtwork(
                widget.id,
                widget.type,
                isHq: isHq,
                isThumbnail: isThumbnail,
              )
            : Future<Uint8List?>.value(null);
      }
      pending = fetch.whenComplete(() => _inFlight.remove(key));
      _inFlight[key] = pending;
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

  Future<Uint8List?> _queryDeviceArtwork(
    int id,
    ArtworkType type, {
    required bool isHq,
    required bool isThumbnail,
  }) async {
    try {
      final res = await _audioQuery.queryArtwork(
        id,
        type,
        format: ArtworkFormat.JPEG,
        size: isHq ? 1000 : (isThumbnail ? 180 : 350),
        quality: isHq ? 100 : (isThumbnail ? 65 : 80),
      );
      if (res != null && res.isNotEmpty) return res;
      if (type == ArtworkType.AUDIO) {
        final albumRes = await _audioQuery.queryArtwork(
          id,
          ArtworkType.ALBUM,
          format: ArtworkFormat.JPEG,
          size: isHq ? 1000 : (isThumbnail ? 180 : 350),
          quality: isHq ? 100 : (isThumbnail ? 65 : 80),
        );
        if (albumRes != null && albumRes.isNotEmpty) return albumRes;
      }
    } catch (_) {}
    return null;
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

        // When the caller asked to fill the parent (`size: double.infinity`)
        // but the incoming constraints are unbounded, resolve a finite extent
        // so the RenderBox always receives a size. Without this the ClipRRect
        // and its child are left unlaid-out, cascading into
        // "RenderBox was not laid out" / "child.hasSize is not true" crashes.
        final double? extent = isBounded
            ? effectiveSize
            : (hasBoundedConstraints ? null : effectiveSize);

        final placeholder = ArtworkPlaceholder(
          size: extent ?? double.infinity,
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
