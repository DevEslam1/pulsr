// lib/core/widgets/cached_artwork.dart
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'artwork_placeholder.dart';

class CachedArtwork extends StatelessWidget {
  final int id;
  final ArtworkType type;
  final double size;
  final double borderRadius;
  final IconData? fallbackIcon;

  const CachedArtwork({
    super.key,
    required this.id,
    this.type = ArtworkType.AUDIO,
    this.size = 48.0,
    this.borderRadius = 12.0,
    this.fallbackIcon,
  });

  @override
  Widget build(BuildContext context) {
    final isBounded = size.isFinite && size > 0;
    final effectiveBorderRadius = borderRadius.isFinite ? borderRadius : 12.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final effectiveSize = isBounded
            ? size
            : (constraints.biggest.shortestSide.isFinite && constraints.biggest.shortestSide > 0
                ? constraints.biggest.shortestSide
                : 200.0);

        return ClipRRect(
          borderRadius: BorderRadius.circular(effectiveBorderRadius),
          child: SizedBox(
            width: isBounded ? effectiveSize : null,
            height: isBounded ? effectiveSize : null,
            child: QueryArtworkWidget(
              id: id,
              type: type,
              artworkWidth: effectiveSize,
              artworkHeight: effectiveSize,
              artworkFit: BoxFit.cover,
              artworkQuality: FilterQuality.medium,
              artworkBorder: BorderRadius.circular(effectiveBorderRadius),
              nullArtworkWidget: ArtworkPlaceholder(
                size: isBounded ? effectiveSize : double.infinity,
                borderRadius: effectiveBorderRadius,
                icon: fallbackIcon,
              ),
            ),
          ),
        );
      },
    );
  }
}
