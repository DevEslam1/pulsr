import 'package:pulsr/core/responsive/pulsr_layout_metrics.dart';
// lib/features/ytm_browse/presentation/ytm_browse_screen.dart
import 'package:flutter/material.dart';
import '../../../core/utils/l10n_extensions.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/ytm_browse_service.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/widgets/pulsr_empty_state.dart';
import '../../../../core/widgets/pulsr_back_button.dart';
import '../../../../core/widgets/pulsr_page_pop_scope.dart';
import '../../../../core/widgets/shimmer_skeleton.dart';
import '../../../data/db/app_database.dart';
import '../../player/cubit/player_cubit.dart';
import '../../ytm_search/presentation/widgets/ytm_download_button.dart';
import '../cubit/ytm_browse_cubit.dart';
import '../cubit/ytm_browse_state.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/constants/app_colors.dart';

class YtmBrowseScreen extends StatelessWidget {
  const YtmBrowseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => YtmBrowseCubit(getIt<YtmBrowseService>())..load(),
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
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (updatedLabel != null)
                    Text(
                      updatedLabel,
                      style: TextStyle(
                        color: p.textTertiary,
                        fontSize: AppFontSize.caption,
                      ),
                    ),
                ],
              ),
              actions: [
                IconButton(
                  constraints: const BoxConstraints(
                      minWidth: AppSpacing.minTouchTarget,
                      minHeight: AppSpacing.minTouchTarget),
                  icon: Icon(Icons.refresh_rounded, color: p.textPrimary),
                  tooltip: context.l10n.refresh,
                  onPressed: busy ? null : () => cubit.load(force: true),
                ),
              ],
              bottom: busy
                  ? PreferredSize(
                      preferredSize: const Size.fromHeight(2.0),
                      child: LinearProgressIndicator(
                        color: p.accent,
                        backgroundColor: Colors.transparent,
                        minHeight: 2.0,
                      ),
                    )
                  : null,
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
          child: RefreshIndicator(
            onRefresh: () => cubit.load(force: true),
            color: p.accent,
            backgroundColor: p.surfaceContainer,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: Adaptive.contentConstraints(context),
                child: ListView.separated(
                  padding: EdgeInsets.only(
                      top: AppSpacing.md,
                      bottom: PulsrLayoutMetrics.scrollBottom(context)),
                  itemCount: state.sections.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.lg),
                  itemBuilder: (context, index) {
                    final section = state.sections[index];
                    final sectionFailure = state.sectionFailure(section.id);
                    final sectionRefreshing =
                        state.isSectionRefreshing(section.id);
                    // Build the queue once per section instead of once per card
                    // (was O(n^2) per horizontal row).
                    final queueSongs = [
                      for (final e in section.items) e.toYtmTrack().toSongData()
                    ];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.s20),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
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
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (section.subtitle != null) ...[
                                      const SizedBox(height: AppSpacing.s2),
                                      Text(
                                        section.subtitle!,
                                        style: TextStyle(
                                          color: p.textSecondary,
                                          fontSize: AppFontSize.label,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (section.id.isNotEmpty)
                                sectionRefreshing
                                    ? const Padding(
                                        padding: EdgeInsets.all(AppSpacing.s14),
                                        child: SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        ),
                                      )
                                    : IconButton(
                                        tooltip: context.l10n.refresh,
                                        constraints: const BoxConstraints(
                                          minWidth: AppSpacing.minTouchTarget,
                                          minHeight: AppSpacing.minTouchTarget,
                                        ),
                                        icon: Icon(
                                          Icons.refresh_rounded,
                                          size: 18,
                                          color: p.textSecondary,
                                        ),
                                        onPressed: busy
                                            ? null
                                            : () =>
                                                cubit.refreshSection(section),
                                      ),
                            ],
                          ),
                        ),
                        if (sectionFailure != null)
                          Padding(
                            padding: const EdgeInsetsDirectional.fromSTEB(
                                AppSpacing.s20,
                                AppSpacing.s2,
                                AppSpacing.s20,
                                0),
                            child: Row(
                              children: [
                                Icon(Icons.error_outline_rounded,
                                    size: 14, color: p.error),
                                const SizedBox(width: AppSpacing.xs),
                                Expanded(
                                  child: Text(
                                    _failureCopy(context, sectionFailure),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: p.textSecondary,
                                      fontSize: AppFontSize.caption,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: sectionRefreshing
                                      ? null
                                      : () => cubit.refreshSection(section),
                                  style: TextButton.styleFrom(
                                    minimumSize: const Size(
                                        48, AppSpacing.minTouchTarget),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.xs),
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
                        const SizedBox(height: AppSpacing.sm),
                        SizedBox(
                          height: Adaptive.isTablet(context) ? 260 : 210,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.s20),
                            itemCount: section.items.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: AppSpacing.s14),
                            itemBuilder: (context, i) {
                              final item = section.items[i];
                              return _buildBrowseCard(
                                  context, item, queueSongs, p);
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

  Widget _buildBrowseCard(BuildContext context, YtmBrowseItem item,
      List<SongsTableData> queueSongs, PulsrPalette p) {
    final song = item.toYtmTrack().toSongData();
    final cardWidth = Adaptive.isTablet(context) ? 180.0 : 140.0;
    final imgHeight = (cardWidth * 0.92).roundToDouble();

    return Semantics(
      button: true,
      label: context.l10n.songByArtist(item.title, item.subtitle),
      child: Container(
        width: cardWidth,
        decoration: BoxDecoration(
          color: p.surfaceCard,
          borderRadius: AppRadii.r16All,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            context.read<PlayerCubit>().playSong(song, queue: queueSongs);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  item.artworkUrl != null
                      ? Image.network(
                          item.artworkUrl!,
                          width: cardWidth,
                          height: imgHeight,
                          fit: BoxFit.cover,
                          cacheWidth: (cardWidth * 2).round(),
                          cacheHeight: (imgHeight * 2).round(),
                          loadingBuilder: (context, child, progress) =>
                              progress == null
                                  ? child
                                  : Container(
                                      width: cardWidth,
                                      height: imgHeight,
                                      color: p.surfaceContainer,
                                      child: Center(
                                        child: SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: p.accent,
                                          ),
                                        ),
                                      ),
                                    ),
                          errorBuilder: (_, __, ___) => Container(
                            width: cardWidth,
                            height: imgHeight,
                            color: p.surfaceContainer,
                            child: Icon(Icons.music_note_rounded,
                                color: p.primary, size: 36),
                          ),
                        )
                      : Container(
                          width: cardWidth,
                          height: imgHeight,
                          color: p.surfaceContainer,
                          child: Icon(Icons.music_note_rounded,
                              color: p.primary, size: 36),
                        ),
                  PositionedDirectional(
                    bottom: 6,
                    end: 6,
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.s6),
                      decoration: BoxDecoration(
                        color: AppColors.scrimAt(0.7),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.play_arrow_rounded,
                          color: Colors.white, size: 18),
                    ),
                  ),
                  PositionedDirectional(
                    top: 4,
                    end: 4,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.scrimAt(0.55),
                        shape: BoxShape.circle,
                      ),
                      child: YtmDownloadButton(song: song, iconSize: 16),
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
                        color: p.textPrimary,
                        fontSize: AppFontSize.bodySmall,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    Text(
                      item.hasKnownDuration
                          ? '${item.subtitle} • ${_formatDuration(item.duration)}'
                          : item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.textSecondary,
                        fontSize: AppFontSize.caption,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// "Updated 14:32" in the device's 12/24-hour convention, or null before the
  /// first successful load.
  String? _updatedLabel(BuildContext context, DateTime? at) {
    if (at == null) return null;
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(at),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return '${context.l10n.browseUpdatedPrefix} $time';
  }

  /// Turns the cubit's signal bucket into the localized line the user sees.
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

/// Non-blocking error strip shown when a refresh fails but a previous feed is
/// still on screen. The feed stays usable; retry replaces the whole banner on
/// success.
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
          AppSpacing.s20, AppSpacing.xs, AppSpacing.s20, 0),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.s6),
      decoration: BoxDecoration(
        color: p.error.withValues(alpha: 0.10),
        borderRadius: AppRadii.r12All,
        border: Border.all(color: p.error.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, color: p.error, size: 18),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              message,
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
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
