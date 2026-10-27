// lib/core/widgets/pulsr_artwork_header.dart
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../constants/app_spacing.dart';
import '../constants/app_typography.dart';
import '../theme/aura_theme.dart';
import '../utils/adaptive.dart';
import 'cached_artwork.dart';

/// An artwork-led page header used by Library and Search.
///
/// A four-up album mosaic sits behind a theme-aware scrim, so the top of a
/// utility screen carries the same album-art identity as Now Playing without a
/// blurred image layer or an expensive backdrop filter. When there is no
/// artwork yet it degrades to a clean surface with the same type.
class PulsrArtworkHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<int> albumIds;
  final double height;

  const PulsrArtworkHeader({
    super.key,
    required this.title,
    required this.albumIds,
    this.subtitle,
    this.height = 112,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ids = albumIds.take(4).toList(growable: false);

    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.hardEdge,
        children: [
          if (ids.isEmpty)
            ColoredBox(color: p.surfaceContainer)
          else
            Row(
              children: [
                for (final id in ids)
                  Expanded(
                    child: CachedArtwork(
                      id: id,
                      type: ArtworkType.ALBUM,
                      size: height,
                      borderRadius: 0,
                    ),
                  ),
              ],
            ),
          // Theme-aware scrim: protects the actions at the top and gives the
          // title a solid surface to sit on at the bottom.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  p.bg.withValues(alpha: 0.55),
                  p.bg.withValues(alpha: 0.30),
                  p.bg,
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
          ),
          // A single soft accent bloom, matching the Now Playing glow.
          PositionedDirectional(
            top: -70,
            end: -40,
            child: IgnorePointer(
              child: Container(
                width: 220,
                height: 170,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      p.accent.withValues(alpha: 0.20),
                      p.accent.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              Adaptive.pagePadding(context),
              0,
              Adaptive.pagePadding(context),
              AppSpacing.s12,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.textPrimary,
                    fontSize: AppFontSize.headline,
                    fontWeight: FontWeight.w800,
                    letterSpacing: AppTracking.heading,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: p.textSecondary,
                      fontSize: AppFontSize.label,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
