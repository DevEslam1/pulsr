import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/responsive/responsive_values.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/async_state_builder.dart';
import '../../../../core/widgets/pulsr_static_grid.dart';
import '../../../../core/widgets/pulsr_section_header.dart';
import '../../../../core/widgets/shimmer_skeleton.dart';
import '../../../../core/widgets/song_tile.dart';
import '../../../../core/widgets/staggered_reveal.dart';
import '../../../../domain/models/ytm_track.dart';
import '../../../player/cubit/player_cubit.dart';
import '../../../sheets/song_info_sheet.dart';
import '../../../ytm_search/cubit/ytm_download_cubit.dart';
import '../../../ytm_search/presentation/widgets/ytm_download_button.dart';
import 'home_card_metrics.dart';
import 'trending_card.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

class OnlineCategorySection extends StatefulWidget {
  final String title;
  final Future<List<YtmTrack>> future;
  final PlayerCubit playerCubit;
  final VoidCallback onRetry;

  const OnlineCategorySection({
    super.key,
    required this.title,
    required this.future,
    required this.playerCubit,
    required this.onRetry,
  });

  @override
  State<OnlineCategorySection> createState() => _OnlineCategorySectionState();
}

class _OnlineCategorySectionState extends State<OnlineCategorySection> {
  /// One background pre-resolve of the list head per loaded category, so the
  /// first tap doesn't pay the full network resolve.
  bool _warmedFirst = false;

  @override
  void didUpdateWidget(OnlineCategorySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.title != oldWidget.title || widget.future != oldWidget.future) {
      _warmedFirst = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isTablet = Adaptive.isTablet(context);
    final size = context.responsive
        .value(compact: 138.0, medium: 150.0, expanded: 158.0);

    return FutureBuilder<List<YtmTrack>>(
      future: widget.future,
      builder: (context, snapshot) {
        Widget buildUnavailable() => Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg, vertical: AppSpacing.lg),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.wifi_tethering_error_rounded,
                        color: p.textTertiary, size: 38),
                    const SizedBox(height: AppSpacing.s10),
                    Text(
                      context.l10n.loadSongsFailed(widget.title),
                      style: TextStyle(
                          color: p.textSecondary,
                          fontSize: AppFontSize.bodySmall),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    TextButton.icon(
                      onPressed: widget.onRetry,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(context.l10n.retry),
                    ),
                  ],
                ),
              ),
            );

        return AsyncStateBuilder<List<YtmTrack>>(
          snapshot: snapshot,
          loadingWidget: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PulsrSectionHeader(title: widget.title),
              SizedBox(
                height: scaledCarouselHeight(context, isTablet),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: true,
                  padding: EdgeInsets.symmetric(
                      horizontal: Adaptive.pagePadding(context)),
                  itemCount: 4,
                  itemBuilder: (context, index) => Padding(
                    padding:
                        const EdgeInsetsDirectional.only(end: AppSpacing.s14),
                    child: SizedBox(
                      width: size,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(
                              width: size, height: size, radius: AppRadii.r18),
                          const SizedBox(height: AppSpacing.xs),
                          SkeletonLine(width: size * 0.75, height: 12),
                          const SizedBox(height: AppSpacing.s6),
                          SkeletonLine(width: size * 0.45, height: 10),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          onError: (_) => buildUnavailable(),
          emptyWidget: buildUnavailable(),
          isEmpty: (tracks) => tracks.isEmpty,
          onData: (tracks) {
            final songs = [for (final track in tracks) track.toSongData()];
            if (!_warmedFirst && songs.isNotEmpty) {
              _warmedFirst = true;
              // Warm the top couple of a carousel (kept low: home renders several
              // carousels, so a larger count would burst resolves across them).
              widget.playerCubit.warmStreams(songs, count: 2);
            }
            final ytmCubit = getIt.isRegistered<YtmDownloadCubit>()
                ? getIt<YtmDownloadCubit>()
                : null;
            final content = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PulsrSectionHeader(title: widget.title),
                SizedBox(
                  height: scaledCarouselHeight(context, isTablet),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: true,
                    padding: EdgeInsets.symmetric(
                        horizontal: Adaptive.pagePadding(context)),
                    itemCount: songs.length,
                    itemBuilder: (context, index) {
                      final song = songs[index];
                      return StaggeredReveal(
                        index: index,
                        horizontal: true,
                        groupKey: songs.isEmpty ? '' : '${songs.first.id}',
                        child: TrendingCard(
                          song: song,
                          onTap: () =>
                              widget.playerCubit.playSong(song, queue: songs),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                PulsrSectionHeader(
                    title:
                        '${context.l10n.browseTopChartsSongs} (${songs.length})'),
                if (context.trackGridColumns > 1)
                  PulsrStaticGrid(
                    crossAxisCount: context.trackGridColumns,
                    mainAxisExtent: 72,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 4,
                    padding: EdgeInsets.symmetric(
                        horizontal: Adaptive.pagePadding(context)),
                    itemCount: songs.length,
                    itemBuilder: (context, i) => StaggeredReveal(
                      index: i,
                      groupKey: songs.isEmpty ? '' : '${songs.first.id}',
                      child: SongTile(
                        song: songs[i],
                        index: i,
                        onTap: () =>
                            widget.playerCubit.playSong(songs[i], queue: songs),
                        trailing: YtmDownloadButton(song: songs[i]),
                        onMorePressed: () =>
                            SongInfoSheet.show(context, song: songs[i]),
                      ),
                    ),
                  )
                else
                  for (int i = 0; i < songs.length; i++)
                    StaggeredReveal(
                      index: i,
                      groupKey: songs.isEmpty ? '' : '${songs.first.id}',
                      child: SongTile(
                        song: songs[i],
                        index: i,
                        onTap: () =>
                            widget.playerCubit.playSong(songs[i], queue: songs),
                        trailing: YtmDownloadButton(song: songs[i]),
                        onMorePressed: () =>
                            SongInfoSheet.show(context, song: songs[i]),
                      ),
                    ),
              ],
            );
            if (ytmCubit != null) {
              return BlocProvider<YtmDownloadCubit>.value(
                value: ytmCubit,
                child: content,
              );
            }
            return content;
          },
        );
      },
    );
  }
}
