// lib/core/widgets/cached_artwork.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'artwork_placeholder.dart';

/// LRU Memory Bitmap Cache for Artwork images.
/// Max items: 200 by default.
class ArtworkLruCache {
  static final ArtworkLruCache _instance = ArtworkLruCache._internal();
  factory ArtworkLruCache() => _instance;
  ArtworkLruCache._internal() : maxCapacity = 200;

  /// Constructor for custom capacity or testing
  ArtworkLruCache.withCapacity(this.maxCapacity);

  final int maxCapacity;
  final Map<String, Uint8List?> _cache = {};

  int get length => _cache.length;

  bool containsKey(String key) => _cache.containsKey(key);

  Uint8List? get(String key) {
    if (!_cache.containsKey(key)) return null;
    final value = _cache.remove(key);
    _cache[key] = value;
    return value;
  }

  void put(String key, Uint8List? bytes) {
    if (_cache.containsKey(key)) {
      _cache.remove(key);
    } else if (_cache.length >= maxCapacity) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = bytes;
  }

  void clear() {
    _cache.clear();
  }
}

class CachedArtwork extends StatefulWidget {
  final int id;
  final ArtworkType type;
  final double size;
  final double borderRadius;
  final IconData? fallbackIcon;
  final ArtworkLruCache? customCache;

  const CachedArtwork({
    super.key,
    required this.id,
    this.type = ArtworkType.AUDIO,
    this.size = 48.0,
    this.borderRadius = 12.0,
    this.fallbackIcon,
    this.customCache,
  });

  @override
  State<CachedArtwork> createState() => _CachedArtworkState();
}

class _CachedArtworkState extends State<CachedArtwork> {
  static final OnAudioQuery _audioQuery = OnAudioQuery();
  Uint8List? _cachedBytes;

  ArtworkLruCache get _cache => widget.customCache ?? ArtworkLruCache();

  String get _cacheKey => '${widget.type.name}_${widget.id}';

  @override
  void initState() {
    super.initState();
    _loadArtwork();
  }

  @override
  void didUpdateWidget(CachedArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id || oldWidget.type != widget.type) {
      _loadArtwork();
    }
  }

  void _loadArtwork() {
    final key = _cacheKey;
    if (_cache.containsKey(key)) {
      setState(() {
        _cachedBytes = _cache.get(key);
      });
    } else {
      _audioQuery
          .queryArtwork(
            widget.id,
            widget.type,
            format: ArtworkFormat.JPEG,
            size: 200,
            quality: 80,
          )
          .then((bytes) {
        if (mounted) {
          _cache.put(key, bytes);
          setState(() {
            _cachedBytes = bytes;
          });
        }
      }).catchError((_) {
        if (mounted) {
          _cache.put(key, null);
          setState(() {
            _cachedBytes = null;
          });
        }
      });
    }
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

        final content = _cachedBytes != null
            ? Image.memory(
                _cachedBytes!,
                width: isBounded ? effectiveSize : null,
                height: isBounded ? effectiveSize : null,
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
            child: content,
          ),
        );
      },
    );
  }
}
