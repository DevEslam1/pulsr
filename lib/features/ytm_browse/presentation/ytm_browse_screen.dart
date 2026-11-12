// lib/features/ytm_browse/presentation/ytm_browse_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/motion/pulsr_motion.dart';
import 'package:pulsr/core/responsive/pulsr_layout_metrics.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/services/ytm_browse_service.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../../../../core/widgets/pulsr_back_button.dart';
import '../../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../../core/widgets/pulsr_empty_state.dart';
import '../../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../../../core/widgets/pulsr_progress.dart';
import '../../../../core/widgets/pulsr_refresh_indicator.dart';
import '../../../../core/widgets/shimmer_skeleton.dart';
import '../../../data/db/app_database.dart';
import '../../player/cubit/player_cubit.dart';
import '../../player/cubit/player_state.dart';
import '../../sheets/add_to_playlist_sheet.dart';
import '../../ytm_search/cubit/ytm_download_cubit.dart';
import '../../ytm_search/presentation/widgets/ytm_download_button.dart';
import '../cubit/ytm_browse_cubit.dart';
import '../cubit/ytm_browse_state.dart';

import '../../../core/utils/pulsr_haptics.dart';
class YtmBrowseScreen extends StatelessWidget {
  const YtmBrowseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final browseProvider = BlocProvider(
      create: (_) => YtmBrowseCubit(getIt<YtmBrowseService>())..load(),
      child: const _YtmBrowseView(),
    );

    if (!getIt.isRegistered<YtmDownloadCubit>()) {
      return browseProvider;
    }

    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => YtmBrowseCubit(getIt<YtmBrowseService>())..load(),
        ),
        BlocProvider<YtmDownloadCubit>.value(
          value: getIt<YtmDownloadCubit>(),
        ),
      ],
      child: const _YtmBrowseView(),
    );
  }
}

class _YtmBrowseView extends StatelessWidget {
  const _YtmBrowseView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<YtmBrowseCubit, YtmBrowseState>(
      builder: (context, state) {
        final p = context.palette;
        final cubit = context.read<YtmBrowseCubit>();
        final busy = state.isLoading || state.isRefreshing;
        final updatedLabel = _updatedLabel(context, state.lastUpdatedAt);

        return PulsrPagePopScope(
          child: Scaffold(
            backgroundColor: p.surface,
            appBar: AppBar(
              backgroundColor: p.surface,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              leading: const PulsrBackButton(),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.l10n.ytmExplore,
                    style: TextStyle(
                      color: p.textPrimary,
                      fontSize: AppFontSize.titleLarge,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  if (updatedLabel != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: state.hasStaleFailure ? p.error : p.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.s6),
                        Flexible(
                          child: Text(
                            updatedLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: p.textTertiary,
                              fontSize: AppFontSize.caption,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              actions: [
                Container(
                  margin: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: p.surfaceContainerHigh.withValues(alpha: 0.65),
                    border: Border.all(
                      color: p.hairline.withValues(alpha: 0.65),
                    ),
                  ),
                  child: IconButton(
                    constraints: const BoxConstraints(
                      minWidth: AppSpacing.minTouchTarget,
                      minHeight: AppSpacing.minTouchTarget,
                    ),
                    icon: busy
                        ? PulsrProgressBar.circular(
                            size: 18,
                            strokeWidth: 2,
                            color: p.accent,
                          )
                        : Icon(
                            Icons.refresh_rounded,
                            color: p.textPrimary,
                            size: 20,
                          ),
                    tooltip: context.l10n.refresh,
                    onPressed: busy
                        ? null
                        : () {
                            PulsrHaptics.lightImpact();
                            cubit.load(force: true);
                          },
                  ),
                ),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(2.5),
                child: SizedBox(
                  height: 2.5,
                  child: busy
                      ? PulsrProgressBar.indeterminate(
                          height: 2.5,
                          color: p.accent,
                          backgroundColor: Colors.transparent,
                        )
                      : null,
                ),
              ),
            ),
            body: _buildBody(context, state, cubit),
          ),
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    YtmBrowseState state,
    YtmBrowseCubit cubit,
  ) {
    final p = context.palette;
    final busy = state.isLoading || state.isRefreshing;

    if (state.isLoading && state.sections.isEmpty) {
      return const SkeletonList(padding: EdgeInsets.only(top: AppSpacing.xs));
    }

    if (state.hasFailure && state.sections.isEmpty) {
      return PulsrEmptyState(
        icon: Icons.cloud_off_rounded,
        iconColor: p.error,
        title: context.l10n.browseFailedLoadFeed,
        subtitle: _failureCopy(context, state.failureReason),
        primaryActionLabel: context.l10n.retry,
        primaryActionIcon: Icons.refresh_rounded,
        onPrimaryAction: () => cubit.load(),
      );
    }

    if (state.sections.isEmpty) {
      return PulsrEmptyState(
        icon: Icons.explore_off_rounded,
        title: context.l10n.browseNoRecommendations,
        subtitle: context.l10n.browseSearchSongsHint,
        primaryActionLabel: context.l10n.retry,
        primaryActionIcon: Icons.refresh_rounded,
        onPrimaryAction: () => cubit.load(force: true),
      );
    }

    return Column(
      children: [
        if (state.hasStaleFailure)
          _StaleFeedBanner(
            message: _failureCopy(context, state.failureReason),
            retryLabel: context.l10n.retry,
            onRetry: () => cubit.load(force: true),
          ),
        Expanded(
          child: PulsrRefreshIndicator(
            onRefresh: () => cubit.load(force: true),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: Adaptive.contentConstraints(context),
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: EdgeInsets.only(
                    top: AppSpacing.md,
                    bottom: PulsrLayoutMetrics.scrollBottom(context),
                  ),
                  itemCount: state.sections.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.lg),
                  itemBuilder: (context, index) {
                    final section = state.sections[index];
                    final sectionFailure = state.sectionFailure(section.id);
                    final sectionRefreshing =
                        state.isSectionRefreshing(section.id);
                    // Build the queue once per section instead of once per card
                    final queueSongs = [
                      for (final e in section.items)
                        e.toYtmTrack().toSongData(),
                    ];

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.s20,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      section.title,
                                      style: TextStyle(
                                        color: p.textPrimary,
                                        fontSize: AppFontSize.title,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                    if (section.subtitle != null) ...[
                                      const SizedBox(height: AppSpacing.s2),
                                      Text(
                                        section.subtitle!,
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
                              if (queueSongs.isNotEmpty) ...[
                                _SectionIconButton(
                                  icon: Icons.play_arrow_rounded,
                                  iconColor: p.accent,
                                  palette: p,
                                  onPressed: () {
                                    PulsrHaptics.selectionClick();
                                    context.read<PlayerCubit>().playSong(
                                          queueSongs.first,
                                          queue: queueSongs,
                                        );
                                  },
                                ),
                                const SizedBox(width: AppSpacing.xs),
                              ],
                              if (section.id.isNotEmpty)
                                sectionRefreshing
                                    ? Padding(
                                        padding:
                                            const EdgeInsets.all(AppSpacing.xs),
                                        child: PulsrProgressBar.circular(
                                          size: 18,
                                          strokeWidth: 2,
                                          color: p.accent,
                                        ),
                                      )
                                    : _SectionIconButton(
                                        icon: Icons.refresh_rounded,
                                        iconColor: p.textSecondary,
                                        tooltip: context.l10n.refresh,
                                        palette: p,
                                        onPressed: busy
                                            ? null
                                            : () {
                                                PulsrHaptics.lightImpact();
                                                cubit.refreshSection(section);
                                              },
                                      ),
                            ],
                          ),
                        ),
                        if (sectionFailure != null)
                          Padding(
                            padding: const EdgeInsetsDirectional.fromSTEB(
                              AppSpacing.s20,
                              AppSpacing.xs,
                              AppSpacing.s20,
                              0,
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: AppSpacing.xxs,
                              ),
                              decoration: BoxDecoration(
                                color: p.error.withValues(alpha: 0.08),
                                borderRadius: AppRadii.r12All,
                                border: Border.all(
                                  color: p.error.withValues(alpha: 0.28),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.error_outline_rounded,
                                    size: 15,
                                    color: p.error,
                                  ),
                                  const SizedBox(width: AppSpacing.xs),
                                  Expanded(
                                    child: Text(
                                      _failureCopy(context, sectionFailure),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: p.textSecondary,
                                        fontSize: AppFontSize.caption,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: sectionRefreshing
                                        ? null
                                        : () => cubit.refreshSection(section),
                                    style: TextButton.styleFrom(
                                      minimumSize: const Size(48, 32),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.xs,
                                      ),
                                    ),
                                    child: Text(
                                      context.l10n.retry,
                                      style: TextStyle(
                                        color: p.error,
                                        fontSize: AppFontSize.caption,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        const SizedBox(height: AppSpacing.sm),
                        SizedBox(
                          height: Adaptive.isTablet(context) ? 264 : 214,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.s20,
                            ),
                            itemCount: section.items.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: AppSpacing.s14),
                            itemBuilder: (context, i) {
                              final item = section.items[i];
                              final song = queueSongs[i];
                              return _BrowseTrackCard(
                                item: item,
                                song: song,
                                queueSongs: queueSongs,
                                palette: p,
                                formatDuration: _formatDuration,
                                onLongPress: () =>
                                    _showBrowseItemSheet(context, song, p),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showBrowseItemSheet(
    BuildContext context,
    SongsTableData song,
    PulsrPalette p,
  ) {
    PulsrHaptics.mediumImpact();
    return PulsrSheetHelper.showPulsrSheet<void>(
      context: context,
      builder: (sheetCtx) => PulsrBottomSheet(
        leading: SizedBox(
          width: 44,
          height: 44,
          child: CachedArtwork(
            id: song.id,
            remoteUrl: song.remoteArtworkUrl ?? song.artworkUri,
            albumId: song.albumId,
            type: ArtworkType.AUDIO,
            size: 44,
            borderRadius: 10,
          ),
        ),
        title: Text(
          song.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          song.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.playlist_play_rounded, color: p.accent),
              title: Text(context.l10n.playNext),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                context.read<PlayerCubit>().playNext(song);
              },
            ),
            ListTile(
              leading: Icon(Icons.queue_music_rounded, color: p.accent),
              title: Text(context.l10n.addToQueue),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                context.read<PlayerCubit>().addAllToQueue([song]);
              },
            ),
            if (getIt.isRegistered<YtmDownloadCubit>())
              ListTile(
                leading: Icon(Icons.download_rounded, color: p.accent),
                title: Text(context.l10n.browseDownloadOffline),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  getIt<YtmDownloadCubit>().download(song);
                },
              ),
            ListTile(
              leading: Icon(Icons.playlist_add_rounded, color: p.accent),
              title: Text(context.l10n.addToPlaylist),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                AddToPlaylistSheet.show(context, song: song);
              },
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String? _updatedLabel(BuildContext context, DateTime? at) {
    if (at == null) return null;
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(at),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return '${context.l10n.browseUpdatedPrefix} $time';
  }

  String _failureCopy(BuildContext context, YtmBrowseFailureReason? reason) {
    switch (reason) {
      case YtmBrowseFailureReason.offline:
        return context.l10n.errYtmNoConnection;
      case YtmBrowseFailureReason.geoBlocked:
        return context.l10n.errYtmRegionRestricted;
      case YtmBrowseFailureReason.botBlocked:
        return context.l10n.errYtmVerify;
      case YtmBrowseFailureReason.unavailable:
        return context.l10n.errYtmUnavailable;
      case YtmBrowseFailureReason.unknown:
      case null:
        return context.l10n.downloadErrorNetwork;
    }
  }
}

class _SectionIconButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final PulsrPalette palette;
  final String? tooltip;
  final VoidCallback? onPressed;

  const _SectionIconButton({
    required this.icon,
    required this.iconColor,
    required this.palette,
    this.tooltip,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: palette.surfaceContainerHighest.withValues(alpha: 0.55),
        border: Border.all(
          color: palette.hairline.withValues(alpha: 0.6),
        ),
      ),
      child: IconButton(
        tooltip: tooltip,
        constraints: const BoxConstraints(
          minWidth: 38,
          minHeight: 38,
        ),
        visualDensity: VisualDensity.compact,
        icon: Icon(icon, size: 18, color: iconColor),
        onPressed: onPressed,
      ),
    );
  }
}

class _BrowseTrackCard extends StatelessWidget {
  final YtmBrowseItem item;
  final SongsTableData song;
  final List<SongsTableData> queueSongs;
  final PulsrPalette palette;
  final String Function(Duration) formatDuration;
  final VoidCallback onLongPress;

  const _BrowseTrackCard({
    required this.item,
    required this.song,
    required this.queueSongs,
    required this.palette,
    required this.formatDuration,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final cardWidth = Adaptive.isTablet(context) ? 180.0 : 142.0;
    final imgHeight = (cardWidth * 0.92).roundToDouble();

    return BlocSelector<PlayerCubit, PlayerState, bool>(
      selector: (state) {
        final current = state.currentSong;
        if (current == null) return false;
        if (current.id == song.id) return true;
        return current.remoteId != null &&
            current.remoteId!.isNotEmpty &&
            current.remoteId == song.remoteId;
      },
      builder: (context, isActive) {
        return Semantics(
          button: true,
          selected: isActive,
          label: context.l10n.songByArtist(item.title, item.subtitle),
          child: AnimatedContainer(
            duration: context.motion(PulsrMotion.state),
            curve: context.motionCurve(PulsrMotion.enter),
            width: cardWidth,
            decoration: BoxDecoration(
              color: isActive
                  ? Color.alphaBlend(
                      p.accent.withValues(alpha: 0.10),
                      p.surfaceCard,
                    )
                  : p.surfaceCard,
              borderRadius: AppRadii.r16All,
              border: Border.all(
                color: isActive
                    ? p.accent.withValues(alpha: 0.65)
                    : p.hairline.withValues(alpha: 0.65),
                width: isActive ? 1.5 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: isActive
                      ? p.accent.withValues(alpha: p.isDark ? 0.22 : 0.12)
                      : Colors.black.withValues(alpha: p.isDark ? 0.22 : 0.05),
                  blurRadius: isActive ? 14 : 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () {
                  PulsrHaptics.selectionClick();
                  context.read<PlayerCubit>().playSong(song, queue: queueSongs);
                },
                onLongPress: onLongPress,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      children: [
                        if (item.artworkUrl != null)
                          Image.network(
                            item.artworkUrl!,
                            width: cardWidth,
                            height: imgHeight,
                            fit: BoxFit.cover,
                            cacheWidth: (cardWidth * 2).round(),
                            cacheHeight: (imgHeight * 2).round(),
                            frameBuilder: (context, child, frame,
                                wasSynchronouslyLoaded) {
                              if (wasSynchronouslyLoaded) return child;
                              return AnimatedOpacity(
                                opacity: frame == null ? 0.0 : 1.0,
                                duration: context.motion(PulsrMotion.state),
                                curve: context.motionCurve(Curves.easeOut),
                                child: child,
                              );
                            },
                            loadingBuilder: (context, child, progress) =>
                                progress == null
                                    ? child
                                    : Container(
                                        width: cardWidth,
                                        height: imgHeight,
                                        color: p.surfaceContainer,
                                        child: Center(
                                          child: PulsrProgressBar.circular(
                                            size: 22,
                                            strokeWidth: 2,
                                            color: p.accent,
                                          ),
                                        ),
                                      ),
                            errorBuilder: (_, __, ___) => _ArtworkFallback(
                              width: cardWidth,
                              height: imgHeight,
                              palette: p,
                            ),
                          )
                        else
                          _ArtworkFallback(
                            width: cardWidth,
                            height: imgHeight,
                            palette: p,
                          ),
                        // Bottom gradient for badge legibility
                        PositionedDirectional(
                          start: 0,
                          end: 0,
                          bottom: 0,
                          height: 42,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.55),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (item.hasKnownDuration)
                          PositionedDirectional(
                            bottom: 6,
                            start: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.s6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.scrimAt(0.70),
                                borderRadius: AppRadii.circular(6),
                              ),
                              child: Text(
                                formatDuration(item.duration),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: AppFontSize.tiny,
                                  fontWeight: FontWeight.w700,
                                  fontFeatures: [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        PositionedDirectional(
                          bottom: 6,
                          end: 6,
                          child: Container(
                            padding: const EdgeInsets.all(AppSpacing.s6),
                            decoration: BoxDecoration(
                              color:
                                  isActive ? p.accent : AppColors.scrimAt(0.75),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                            child: Icon(
                              isActive
                                  ? Icons.graphic_eq_rounded
                                  : Icons.play_arrow_rounded,
                              color: isActive
                                  ? (ThemeData.estimateBrightnessForColor(
                                              p.accent) ==
                                          Brightness.dark
                                      ? Colors.white
                                      : Colors.black)
                                  : Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                        PositionedDirectional(
                          top: 4,
                          end: 4,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.scrimAt(0.60),
                              shape: BoxShape.circle,
                            ),
                            child: YtmDownloadButton(
                              song: song,
                              iconSize: 16,
                              iconColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isActive ? p.accent : p.textPrimary,
                              fontSize: AppFontSize.bodySmall,
                              fontWeight:
                                  isActive ? FontWeight.w800 : FontWeight.w700,
                              letterSpacing: -0.15,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.s2),
                          Text(
                            item.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: p.textSecondary,
                              fontSize: AppFontSize.caption,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ArtworkFallback extends StatelessWidget {
  final double width;
  final double height;
  final PulsrPalette palette;

  const _ArtworkFallback({
    required this.width,
    required this.height,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            palette.surfaceContainerHigh,
            palette.surfaceContainer,
          ],
        ),
      ),
      child: Icon(
        Icons.music_note_rounded,
        color: palette.accent.withValues(alpha: 0.65),
        size: 36,
      ),
    );
  }
}

/// Non-blocking error strip shown when a refresh fails but a previous feed is
/// still on screen.
class _StaleFeedBanner extends StatelessWidget {
  const _StaleFeedBanner({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      margin: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.s20,
        AppSpacing.xs,
        AppSpacing.s20,
        0,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.s6,
      ),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          p.error.withValues(alpha: p.isDark ? 0.14 : 0.08),
          p.surfaceContainerHigh,
        ),
        borderRadius: AppRadii.r16All,
        border: Border.all(color: p.error.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: p.error.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: p.error.withValues(alpha: 0.15),
            ),
            child: Icon(Icons.cloud_off_rounded, color: p.error, size: 16),
          ),
          const SizedBox(width: AppSpacing.s10),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: p.textPrimary,
                fontSize: AppFontSize.caption,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              minimumSize: const Size(AppSpacing.minTouchTarget, 32),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            ),
            child: Text(
              retryLabel,
              style: TextStyle(
                color: p.error,
                fontSize: AppFontSize.caption,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
