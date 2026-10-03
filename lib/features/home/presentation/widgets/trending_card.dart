import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../../../../core/responsive/responsive_values.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../../../../data/db/app_database.dart';
import '../../../ytm_search/presentation/widgets/ytm_download_button.dart';
import 'home_card_metrics.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/constants/app_colors.dart';

class TrendingCard extends StatelessWidget {
  final SongsTableData song;
  final VoidCallback onTap;

  const TrendingCard({super.key, required this.song, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final size = context.responsive
        .value(compact: 138.0, medium: 150.0, expanded: 158.0);

    return Padding(
      padding: const EdgeInsetsDirectional.only(end: AppSpacing.s14),
      child: Semantics(
        button: true,
        label: '${song.title}, ${song.artist}',
        hint: context.l10n.play,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.r20),
          onTap: onTap,
          child: SizedBox(
            width: size,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  children: [
                    CachedArtwork(
                      id: song.id,
                      remoteUrl: song.remoteArtworkUrl ?? song.artworkUri,
                      albumId: song.albumId,
                      type: ArtworkType.AUDIO,
                      size: size,
                      borderRadius: AppRadii.r18,
                    ),
                    // Scrim keeps the download icon legible over arbitrary artwork.
                    PositionedDirectional(
                      end: 6,
                      bottom: 6,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.scrimAt(0.5),
                          shape: BoxShape.circle,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minWidth: 44,
                            minHeight: 44,
                          ),
                          child: Center(
                            child: YtmDownloadButton(song: song),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                SizedBox(
                  height: scaledTitleBoxHeight(context),
                  child: Text(
                    song.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: AppFontSize.label,
                      height: 1.25,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.textSecondary, fontSize: AppFontSize.label),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
