// lib/features/search/presentation/widgets/highlighted_song_tile.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../../../../core/widgets/highlighted_text.dart';
import '../../../../data/db/app_database.dart';
import '../../../player/cubit/player_cubit.dart';
import '../../../player/cubit/player_state.dart';

/// Search result row that highlights every occurrence of the active [query]
/// in the title and subtitle. Mirrors the standard song row layout (artwork,
/// title, subtitle, duration, trailing actions) with audiophile active-state
/// framing and tabular duration alignment.
class HighlightedSongTile extends StatelessWidget {
  final SongsTableData song;
  final String query;
  final String? subtitleOverride;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onMorePressed;
  final Widget? trailing;

  const HighlightedSongTile({
    super.key,
    required this.song,
    required this.query,
    required this.onTap,
    this.subtitleOverride,
    this.onLongPress,
    this.onMorePressed,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final subtitle = subtitleOverride ?? song.artist;
    final effectiveLongPress = onLongPress ?? onMorePressed;

    return BlocSelector<PlayerCubit, PlayerState, bool>(
      selector: (state) => state.currentSong?.id == song.id,
      builder: (context, isActive) {
        final titleStyle = TextStyle(
          color: isActive ? p.accent : p.textPrimary,
          fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
          fontSize: AppFontSize.body,
          height: 1.2,
        );
        final titleMatchStyle = TextStyle(
          color: p.accent,
          fontWeight: FontWeight.w800,
          fontSize: AppFontSize.body,
          height: 1.2,
        );
        final subtitleStyle = TextStyle(
          color: isActive ? p.textPrimary.withValues(alpha: 0.78) : p.textSecondary,
          fontSize: AppFontSize.label,
          fontWeight: FontWeight.w500,
          height: 1.25,
        );
        final subtitleMatchStyle = TextStyle(
          color: p.accent,
          fontWeight: FontWeight.w700,
          fontSize: AppFontSize.label,
          height: 1.25,
        );

        return Semantics(
          button: true,
          selected: isActive,
          label: context.l10n.songByArtist(song.title, song.artist),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.s2,
            ),
            child: AnimatedContainer(
              duration: context.motion(PulsrMotion.state),
              curve: context.motionCurve(PulsrMotion.enter),
              decoration: BoxDecoration(
                color: isActive
                    ? p.accent.withValues(alpha: 0.10)
                    : p.surface,
                borderRadius: AppRadii.r16All,
                border: Border.all(
                  color: isActive
                      ? p.accent.withValues(alpha: 0.35)
                      : Colors.transparent,
                  width: 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: AppRadii.r16All,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onTap();
                  },
                  onLongPress: effectiveLongPress != null
                      ? () {
                          HapticFeedback.mediumImpact();
                          effectiveLongPress();
                        }
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s10,
                      vertical: AppSpacing.s6,
                    ),
                    child: Row(
                      children: [
                        _ArtworkThumbnail(
                          song: song,
                          isActive: isActive,
                          palette: p,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              PulsrHighlightedText(
                                text: song.title,
                                query: query,
                                baseStyle: titleStyle,
                                matchStyle: titleMatchStyle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: AppSpacing.s2),
                              PulsrHighlightedText(
                                text: subtitle,
                                query: query,
                                baseStyle: subtitleStyle,
                                matchStyle: subtitleMatchStyle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        if (song.durationMs > 0) ...[
                          const SizedBox(width: AppSpacing.xs),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.s6,
                              vertical: AppSpacing.s2,
                            ),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? p.accent.withValues(alpha: 0.14)
                                  : p.surfaceContainer.withValues(alpha: 0.65),
                              borderRadius: AppRadii.circular(8),
                            ),
                            child: Text(
                              Formatters.formatDurationMs(song.durationMs),
                              style: TextStyle(
                                color: isActive ? p.accent : p.textTertiary,
                                fontSize: AppFontSize.tiny,
                                fontWeight: FontWeight.w700,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                        ],
                        if (trailing != null) ...[
                          const SizedBox(width: AppSpacing.xxs),
                          RepaintBoundary(child: trailing!),
                        ],
                        if (onMorePressed != null)
                          RepaintBoundary(
                            child: IconButton(
                              icon: Icon(
                                Icons.more_vert_rounded,
                                size: 20,
                                color: isActive ? p.accent : p.textTertiary,
                              ),
                              tooltip: MaterialLocalizations.of(context)
                                  .moreButtonTooltip,
                              onPressed: onMorePressed,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ArtworkThumbnail extends StatelessWidget {
  final SongsTableData song;
  final bool isActive;
  final PulsrPalette palette;

  const _ArtworkThumbnail({
    required this.song,
    required this.isActive,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 50,
      height: 50,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CachedArtwork(
            id: song.id,
            remoteUrl: song.remoteArtworkUrl ?? song.artworkUri,
            albumId: song.albumId,
            type: ArtworkType.AUDIO,
            size: 50,
            borderRadius: 12,
          ),
          if (isActive)
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: AppRadii.circular(12),
                border: Border.all(
                  color: palette.accent.withValues(alpha: 0.6),
                  width: 1.5,
                ),
              ),
              child: Center(
                child: Icon(
                  Icons.graphic_eq_rounded,
                  color: palette.accent,
                  size: 22,
                ),
              ),
            ),
        ],
      ),
    );
  }
}