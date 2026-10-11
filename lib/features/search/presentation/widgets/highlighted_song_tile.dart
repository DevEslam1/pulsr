// lib/features/search/presentation/widgets/highlighted_song_tile.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
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
/// title, subtitle, duration, trailing actions) so search rows keep the same
/// visual rhythm while making the match visible.
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

    return BlocSelector<PlayerCubit, PlayerState, bool>(
      selector: (state) => state.currentSong?.id == song.id,
      builder: (context, isActive) {
        final titleStyle = TextStyle(
          color: isActive ? p.accent : p.textPrimary,
          fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
          fontSize: AppFontSize.body,
        );
        final subtitleStyle = TextStyle(
          color: p.textSecondary,
          fontSize: AppFontSize.label,
        );
        final matchStyle = TextStyle(
          color: p.accent,
          fontWeight: FontWeight.w800,
          fontSize: AppFontSize.label,
        );

        return Semantics(
          button: true,
          label: context.l10n.songByArtist(song.title, song.artist),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs, vertical: AppSpacing.s2),
            child: Material(
              color: isActive ? p.surfaceContainer : p.surface,
              borderRadius: AppRadii.r16All,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                borderRadius: AppRadii.r16All,
                onTap: onTap,
                onLongPress: onLongPress,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s10, vertical: AppSpacing.s6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 52,
                        height: 52,
                        child: CachedArtwork(
                          id: song.id,
                          remoteUrl: song.remoteArtworkUrl ?? song.artworkUri,
                          albumId: song.albumId,
                          type: ArtworkType.AUDIO,
                          size: 52,
                          borderRadius: 13,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            PulsrHighlightedText(
                              text: song.title,
                              query: query,
                              baseStyle: titleStyle,
                              matchStyle: titleStyle.copyWith(color: p.accent),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: AppSpacing.s2),
                            PulsrHighlightedText(
                              text: subtitle,
                              query: query,
                              baseStyle: subtitleStyle,
                              matchStyle: matchStyle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (song.durationMs > 0) ...[
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          Formatters.formatDurationMs(song.durationMs),
                          style: TextStyle(
                            color: p.textTertiary,
                            fontSize: AppFontSize.label,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (trailing != null) RepaintBoundary(child: trailing!),
                      if (onMorePressed != null)
                        RepaintBoundary(
                          child: IconButton(
                            icon: Icon(Icons.more_vert_rounded,
                                size: 20, color: p.textTertiary),
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
        );
      },
    );
  }
}
