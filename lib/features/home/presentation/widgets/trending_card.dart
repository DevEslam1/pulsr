import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/responsive/responsive_values.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/utils/track_display_info.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../../../../data/db/app_database.dart';
import '../../../ytm_search/cubit/ytm_download_cubit.dart';
import '../../../ytm_search/presentation/widgets/ytm_download_button.dart';
import 'home_card_metrics.dart';

class TrendingCard extends StatelessWidget {
  final SongsTableData song;
  final VoidCallback onTap;
  final bool isCurrent;
  final bool isPlaying;

  const TrendingCard({
    super.key,
    required this.song,
    required this.onTap,
    this.isCurrent = false,
    this.isPlaying = false,
  });

  bool _hasDownloadControl(BuildContext context) {
    if (!AppConfig.ytmEnabled) return false;
    final videoId = song.remoteId ?? '';
    if (videoId.isEmpty) return false;
    final provided = context.watch<YtmDownloadCubit?>();
    return provided != null || getIt.isRegistered<YtmDownloadCubit>();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final displayInfo = TrackDisplayInfo.resolve(
      rawTitle: song.title,
      rawArtist: song.artist,
    );
    final size = context.responsive
        .value(compact: 138.0, medium: 150.0, expanded: 158.0);
    final showDownload = _hasDownloadControl(context);

    Widget? downloadBadge;
    if (showDownload) {
      final badgeContent = DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.scrimAt(0.70),
          shape: BoxShape.circle,
          border: Border.all(
            color: AppColors.specularAt(0.30),
            width: 1.0,
          ),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: AppSpacing.minTouchTargetCompact,
            minHeight: AppSpacing.minTouchTargetCompact,
          ),
          child: Center(
            child: YtmDownloadButton(
              song: song,
              iconColor: AppColors.fadeStopOpaque,
            ),
          ),
        ),
      );
      downloadBadge = PositionedDirectional(
        top: AppSpacing.s6,
        end: AppSpacing.s6,
        child: ClipOval(child: badgeContent),
      );
    }

    return Padding(
      padding: const EdgeInsetsDirectional.only(end: AppSpacing.s14),
      child: Semantics(
        button: true,
        label: '${displayInfo.title}, ${displayInfo.artist}',
        hint: context.l10n.play,
        child: InkWell(
          borderRadius: AppRadii.r20All,
          onTap: onTap,
          child: SizedBox(
            width: size,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  children: [
                    HomeCardArtworkFrame(
                      radius: AppRadii.r18,
                      child: CachedArtwork(
                        id: song.id,
                        remoteUrl: song.remoteArtworkUrl ?? song.artworkUri,
                        albumId: song.albumId,
                        type: ArtworkType.AUDIO,
                        size: size,
                        borderRadius: AppRadii.r18,
                        title: displayInfo.title,
                        artist: displayInfo.artist,
                      ),
                    ),
                    if (downloadBadge != null) downloadBadge,
                    PositionedDirectional(
                      end: AppSpacing.xs,
                      bottom: AppSpacing.xs,
                      child: HomeCardPlayBadge(
                        isCurrent: isCurrent,
                        isPlaying: isPlaying,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                SizedBox(
                  height: scaledTitleBoxHeight(context),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      displayInfo.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isCurrent ? p.accent : p.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: AppFontSize.bodySmall,
                        letterSpacing: AppTracking.title,
                        height: 1.25,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  displayInfo.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.textSecondary,
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w500,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
