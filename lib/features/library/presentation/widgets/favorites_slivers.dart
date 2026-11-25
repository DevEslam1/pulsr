// lib/features/library/presentation/widgets/favorites_slivers.dart
import 'package:material_ui/material_ui.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/responsive/pulsr_layout_metrics.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/responsive/adaptive_grid.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/utils/pulsr_haptics.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../../../../core/widgets/pulsr_dismissible.dart';
import '../../../../core/widgets/pulsr_empty_state.dart';
import '../../../../core/widgets/shimmer_skeleton.dart';
import '../../../../core/widgets/song_tile.dart';
import '../../../../core/widgets/source_scope_switcher.dart';
import '../../../../core/widgets/staggered_reveal.dart';
import '../../../../data/db/app_database.dart';
import '../../../player/cubit/player_cubit.dart';
import '../../../sheets/song_options_sheet.dart';
import '../../../ytm_search/presentation/widgets/ytm_download_button.dart';
import '../../cubit/library_cubit.dart';
import '../library_quality_utils.dart';

/// Builds the shared sliver list consumed by both [FavoritesScreen] and
/// [LibraryFavoritesTab] so the two Favorites surfaces stay structurally and
/// behaviorally identical.
List<Widget> buildFavoritesSlivers({
  required BuildContext context,
  required List<SongsTableData> songs,
  required int localCount,
  required int onlineCount,
  required SourceScope scope,
  required ValueChanged<SourceScope> onScopeChanged,
  required bool isLoading,
  required bool isGrid,
  required bool isMultiSelectMode,
  required Set<int> selectedSongIds,
  required PlayerCubit playerCubit,
  required LibraryCubit libraryCubit,
  required String dismissKeyPrefix,
  VoidCallback? onViewAll,
  VoidCallback? onDownloadAll,
  VoidCallback? onSyncOnline,
  VoidCallback? onImportOnlineLink,
  String searchQuery = '',
  VoidCallback? onClearSearch,
  bool hasAnyInScope = true,
}) {
  final p = context.palette;
  final l10n = context.l10n;
  final pagePad = Adaptive.pagePadding(context);
  final isOnline = scope == SourceScope.online;
  final losslessCount = songs.where(isLosslessSong).length;
  final totalDurationMs = songs.fold<int>(0, (acc, s) => acc + s.durationMs);
  final hasOnlineTracks =
      songs.any((s) => s.remoteId != null && s.remoteId!.isNotEmpty);

  final isCenteredEmpty = (!hasAnyInScope && !isLoading) ||
      (songs.isEmpty && searchQuery.isNotEmpty);

  return [
    // ---------- Canonical Local / Online Scope Switcher ----------
    SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          pagePad,
          AppSpacing.sm,
          pagePad,
          AppSpacing.s14,
        ),
        child: SourceScopeSwitcher(
          persistKey: 'favorites',
          selectedScope: scope,
          onChanged: onScopeChanged,
          localCount: localCount,
          onlineCount: onlineCount,
        ),
      ),
    ),

    // ---------- Unified Summary & Quick-Actions Card ----------
    SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          pagePad,
          0,
          pagePad,
          AppSpacing.md,
        ),
        child: _FavoritesHeaderCard(
          songs: songs,
          isOnline: isOnline,
          losslessCount: losslessCount,
          totalDurationMs: totalDurationMs,
          hasOnlineTracks: hasOnlineTracks,
          onViewAll: onViewAll,
          onPlayAll: songs.isEmpty
              ? null
              : () => playerCubit.playSong(songs.first, queue: songs),
          onShuffle: songs.isEmpty
              ? null
              : () {
                  final shuffled = List<SongsTableData>.from(songs)..shuffle();
                  playerCubit.playSong(shuffled.first, queue: shuffled);
                },
          onDownloadAll: onDownloadAll,
          onSyncOnline: onSyncOnline,
          onImportOnlineLink: onImportOnlineLink,
        ),
      ),
    ),

    // ---------- Empty / Loading / Filtered / Grid / List Content ----------
    if (!hasAnyInScope)
      if (isLoading)
        SliverToBoxAdapter(
          child: SkeletonList(
            padding: EdgeInsetsDirectional.fromSTEB(
              pagePad,
              AppSpacing.xs,
              pagePad,
              PulsrLayoutMetrics.scrollBottom(context),
            ),
          ),
        )
      else
        SliverLayoutBuilder(
          builder: (context, constraints) {
            final dockReserve = PulsrLayoutMetrics.scrollBottom(context);
            final visibleHeight = (constraints.viewportMainAxisExtent -
                    constraints.precedingScrollExtent -
                    dockReserve -
                    AppSpacing.sm)
                .clamp(0.0, double.infinity);
            return SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsetsDirectional.only(
                  top: AppSpacing.sm,
                  bottom: dockReserve,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: visibleHeight),
                  child: Center(
                    child: PulsrEmptyState(
                      icon: isOnline
                          ? Icons.cloud_off_rounded
                          : Icons.favorite_border_rounded,
                      iconColor: isOnline ? p.accent : p.favorite,
                      title: isOnline
                          ? l10n.noOnlineFavorites
                          : l10n.noLocalFavorites,
                      subtitle: isOnline
                          ? l10n.browseSyncPullSubtitle
                          : l10n.noLocalFavoritesSubtitle,
                      primaryActionLabel: isOnline &&
                              AppConfig.ytmEnabled &&
                              onSyncOnline != null
                          ? l10n.syncYouTubeMusic
                          : null,
                      primaryActionIcon: isOnline &&
                              AppConfig.ytmEnabled &&
                              onSyncOnline != null
                          ? Icons.sync_rounded
                          : null,
                      onPrimaryAction: isOnline && AppConfig.ytmEnabled
                          ? onSyncOnline
                          : null,
                    ),
                  ),
                ),
              ),
            );
          },
        )
    else if (songs.isEmpty && searchQuery.isNotEmpty)
      SliverLayoutBuilder(
        builder: (context, constraints) {
          final dockReserve = PulsrLayoutMetrics.scrollBottom(context);
          final visibleHeight = (constraints.viewportMainAxisExtent -
                  constraints.precedingScrollExtent -
                  dockReserve -
                  AppSpacing.sm)
              .clamp(0.0, double.infinity);
          return SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsetsDirectional.only(
                top: AppSpacing.sm,
                bottom: dockReserve,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: visibleHeight),
                child: Center(
                  child: PulsrEmptyState(
                    icon: Icons.search_off_rounded,
                    title: l10n.browseNoSongsMatch,
                    subtitle: '"$searchQuery"',
                    primaryActionLabel:
                        onClearSearch != null ? l10n.clear : null,
                    primaryActionIcon:
                        onClearSearch != null ? Icons.clear_rounded : null,
                    onPrimaryAction: onClearSearch,
                  ),
                ),
              ),
            ),
          );
        },
      )
    else if (isGrid)
      SliverPadding(
        padding: EdgeInsetsDirectional.fromSTEB(
          pagePad,
          AppSpacing.xs,
          pagePad,
          0,
        ),
        sliver: SliverGrid.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: PulsrAdaptiveGrid.dynamicColumns(
              context,
              minItemWidth: 160,
              minColumns: 2,
              maxColumns: 5,
            ),
            crossAxisSpacing: 14,
            mainAxisSpacing: 16,
            childAspectRatio: 0.76,
          ),
          itemCount: songs.length,
          itemBuilder: (context, index) {
            final song = songs[index];
            return StaggeredReveal(
              index: index,
              groupKey:
                  songs.isEmpty ? '' : '${songs.first.id}-${songs.length}',
              child: _FavoriteGridCard(
                song: song,
                queue: songs,
                isMultiSelectMode: isMultiSelectMode,
                isSelected: selectedSongIds.contains(song.id),
                playerCubit: playerCubit,
                libraryCubit: libraryCubit,
              ),
            );
          },
        ),
      )
    else
      SliverList.builder(
        itemCount: songs.length,
        itemBuilder: (context, index) {
          final song = songs[index];
          return RepaintBoundary(
            child: PulsrDismissible(
              key: ValueKey('${dismissKeyPrefix}_${song.id}'),
              startToEndLabel: l10n.playNext,
              endToStartLabel: l10n.removeFromFavorites,
              backgroundBuilder: (context, isConfirming) =>
                  PulsrDismissible.buildActionBackground(
                context: context,
                icon: Icons.playlist_play_rounded,
                label: l10n.playNext,
                color: p.accent,
                backgroundColor: p.accentContainer,
                isConfirming: isConfirming,
              ),
              secondaryBackgroundBuilder: (context, isConfirming) =>
                  PulsrDismissible.buildActionBackground(
                context: context,
                icon: Icons.favorite_border_rounded,
                label: l10n.removeFromFavorites,
                color: p.favorite,
                backgroundColor: p.favorite.withValues(alpha: 0.2),
                isConfirming: isConfirming,
                isEnd: true,
              ),
              onConfirm: (direction) async {
                if (direction == DismissDirection.startToEnd) {
                  PulsrHaptics.lightImpact();
                  playerCubit.playNext(song);
                } else {
                  PulsrHaptics.mediumImpact();
                  libraryCubit.toggleFavorite(song.id);
                  if (context.mounted) {
                    final messenger = ScaffoldMessenger.of(context);
                    messenger.hideCurrentSnackBar();
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(context.l10n.removedFavorite(song.title)),
                        duration: const Duration(seconds: 4),
                        action: SnackBarAction(
                          label: context.l10n.undo,
                          onPressed: () => libraryCubit.toggleFavorite(song.id),
                        ),
                      ),
                    );
                  }
                }
                return false;
              },
              child: SongTile(
                song: song,
                index: index,
                selected: selectedSongIds.contains(song.id),
                onTap: () {
                  if (isMultiSelectMode) {
                    libraryCubit.toggleSongSelection(song.id);
                  } else {
                    playerCubit.playSong(song, queue: songs);
                  }
                },
                onLongPress: () => libraryCubit.toggleSongSelection(song.id),
                onMorePressed: () => SongOptionsSheet.show(
                  context,
                  song: song,
                  isFavoriteScreen: true,
                ),
                trailing: IconButton(
                  constraints: const BoxConstraints(
                    minWidth: AppSpacing.minTouchTarget,
                    minHeight: AppSpacing.minTouchTarget,
                  ),
                  tooltip: l10n.favorite,
                  icon: Icon(
                    song.isFavorite
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: song.isFavorite ? p.favorite : p.textTertiary,
                    size: 20,
                  ),
                  onPressed: () => libraryCubit.toggleFavorite(song.id),
                ),
              ),
            ),
          );
        },
      ),

    if (!isCenteredEmpty && !(isLoading && !hasAnyInScope))
      SliverToBoxAdapter(
        child: SizedBox(height: PulsrLayoutMetrics.scrollBottom(context)),
      ),
  ];
}

class _FavoritesHeaderCard extends StatelessWidget {
  final List<SongsTableData> songs;
  final bool isOnline;
  final int losslessCount;
  final int totalDurationMs;
  final bool hasOnlineTracks;
  final VoidCallback? onViewAll;
  final VoidCallback? onPlayAll;
  final VoidCallback? onShuffle;
  final VoidCallback? onDownloadAll;
  final VoidCallback? onSyncOnline;
  final VoidCallback? onImportOnlineLink;

  const _FavoritesHeaderCard({
    required this.songs,
    required this.isOnline,
    required this.losslessCount,
    required this.totalDurationMs,
    required this.hasOnlineTracks,
    required this.onViewAll,
    required this.onPlayAll,
    required this.onShuffle,
    required this.onDownloadAll,
    required this.onSyncOnline,
    required this.onImportOnlineLink,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l10n = context.l10n;
    final showActionsRow =
        songs.isNotEmpty || (isOnline && AppConfig.ytmEnabled);

    return Container(
      decoration: BoxDecoration(
        color: p.surfaceCard,
        borderRadius: AppRadii.r18All,
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: AppColors.fadeStopTransparent,
            child: InkWell(
              borderRadius: showActionsRow
                  ? const BorderRadius.vertical(
                      top: Radius.circular(AppRadii.r18),
                    )
                  : AppRadii.r18All,
              onTap: onViewAll,
              child: Padding(
                padding: const EdgeInsetsDirectional.all(AppSpacing.md),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final inlineAction =
                        onViewAll != null && constraints.maxWidth >= 480;
                    final stackedAction = onViewAll != null && !inlineAction;

                    Widget buildViewAllPill() {
                      return Container(
                        padding: const EdgeInsetsDirectional.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.s6,
                        ),
                        decoration: BoxDecoration(
                          color: p.accent.withValues(alpha: 0.14),
                          borderRadius: AppRadii.r10All,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                l10n.unifiedFavoritesViewAll,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: AppFontSize.caption,
                                  fontWeight: FontWeight.w700,
                                  color: p.accent,
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xxs),
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 11,
                              color: p.accent,
                            ),
                          ],
                        ),
                      );
                    }

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (songs.isNotEmpty)
                              CachedArtwork(
                                id: songs.first.id,
                                albumId: songs.first.albumId,
                                remoteUrl: songs.first.remoteArtworkUrl ??
                                    songs.first.artworkUri,
                                size: 46,
                                borderRadius: AppRadii.r12,
                              )
                            else
                              Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  color: (isOnline ? p.accent : p.favorite)
                                      .withValues(alpha: 0.15),
                                  borderRadius: AppRadii.r12All,
                                ),
                                child: Icon(
                                  isOnline
                                      ? Icons.cloud_rounded
                                      : Icons.favorite_rounded,
                                  color: isOnline ? p.accent : p.favorite,
                                  size: 22,
                                ),
                              ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l10n.unifiedFavoritesHeader,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: AppFontSize.callout,
                                      fontWeight: FontWeight.w800,
                                      color: p.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.s4),
                                  Text(
                                    songs.isNotEmpty
                                        ? '${l10n.tracksCount(songs.length)} • ${Formatters.formatDuration(Duration(milliseconds: totalDurationMs))}'
                                        : l10n.unifiedFavoritesHeaderSubtitle,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: AppFontSize.caption,
                                      color: p.textSecondary,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (inlineAction) ...[
                              const SizedBox(width: AppSpacing.md),
                              buildViewAllPill(),
                            ],
                          ],
                        ),
                        if (stackedAction) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: buildViewAllPill(),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          if (showActionsRow) ...[
            Divider(
              height: 1,
              color: p.hairline,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xxs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (losslessCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.s6,
                              vertical: AppSpacing.s2,
                            ),
                            decoration: BoxDecoration(
                              color: p.info.withValues(alpha: 0.14),
                              borderRadius: AppRadii.r6All,
                              border: Border.all(
                                color: p.info.withValues(alpha: 0.24),
                              ),
                            ),
                            child: Text(
                              context.l10n.losslessCountLabel(losslessCount),
                              style: TextStyle(
                                fontSize: AppFontSize.caption,
                                fontWeight: FontWeight.w800,
                                color: p.info,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xxs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (songs.isNotEmpty) ...[
                        FilledButton.icon(
                          onPressed: onPlayAll,
                          icon: const Icon(Icons.play_arrow_rounded, size: 18),
                          label: Text(l10n.playAll),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(
                              0,
                              AppSpacing.minTouchTarget,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical: AppSpacing.s10,
                            ),
                            backgroundColor: p.accent,
                            foregroundColor: p.onAccent,
                            elevation: 0,
                            shape: const StadiumBorder(),
                            textStyle: const TextStyle(
                              fontSize: AppFontSize.bodySmall,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton.filledTonal(
                          onPressed: onShuffle,
                          icon: const Icon(Icons.shuffle_rounded, size: 18),
                          style: IconButton.styleFrom(
                            minimumSize: const Size(
                              AppSpacing.minTouchTarget,
                              AppSpacing.minTouchTarget,
                            ),
                            backgroundColor: p.surfaceContainerHigh,
                            foregroundColor: p.textPrimary,
                            shape: CircleBorder(
                              side: BorderSide(color: p.hairline),
                            ),
                          ),
                          tooltip: l10n.shuffle,
                        ),
                        if (AppConfig.ytmEnabled &&
                            onDownloadAll != null &&
                            (hasOnlineTracks || !isOnline))
                          IconButton.filledTonal(
                            onPressed: onDownloadAll,
                            icon: const Icon(Icons.download_rounded, size: 18),
                            style: IconButton.styleFrom(
                              minimumSize: const Size(
                                AppSpacing.minTouchTarget,
                                AppSpacing.minTouchTarget,
                              ),
                              backgroundColor: p.surfaceContainerHigh,
                              foregroundColor: p.accent,
                              shape: CircleBorder(
                                side: BorderSide(color: p.hairline),
                              ),
                            ),
                            tooltip: l10n.browseDownloadAllLikedSongs,
                          ),
                      ],
                      if (isOnline && AppConfig.ytmEnabled) ...[
                        if (onSyncOnline != null)
                          IconButton.filledTonal(
                            onPressed: onSyncOnline,
                            icon: const Icon(Icons.sync_rounded, size: 18),
                            style: IconButton.styleFrom(
                              minimumSize: const Size(
                                AppSpacing.minTouchTarget,
                                AppSpacing.minTouchTarget,
                              ),
                              backgroundColor: p.surfaceContainerHigh,
                              foregroundColor: p.accent,
                              shape: CircleBorder(
                                side: BorderSide(color: p.hairline),
                              ),
                            ),
                            tooltip: l10n.syncYouTubeMusic,
                          ),
                        if (onImportOnlineLink != null)
                          IconButton.filledTonal(
                            onPressed: onImportOnlineLink,
                            icon: const Icon(Icons.link_rounded, size: 18),
                            style: IconButton.styleFrom(
                              minimumSize: const Size(
                                AppSpacing.minTouchTarget,
                                AppSpacing.minTouchTarget,
                              ),
                              backgroundColor: p.surfaceContainerHigh,
                              foregroundColor: p.textPrimary,
                              shape: CircleBorder(
                                side: BorderSide(color: p.hairline),
                              ),
                            ),
                            tooltip: l10n.importByPlaylistLink,
                          ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FavoriteGridCard extends StatelessWidget {
  final SongsTableData song;
  final List<SongsTableData> queue;
  final bool isMultiSelectMode;
  final bool isSelected;
  final PlayerCubit playerCubit;
  final LibraryCubit libraryCubit;

  const _FavoriteGridCard({
    required this.song,
    required this.queue,
    required this.isMultiSelectMode,
    required this.isSelected,
    required this.playerCubit,
    required this.libraryCubit,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l10n = context.l10n;
    final badge = songQualityBadge(song);

    return RepaintBoundary(
      child: Material(
        color: AppColors.fadeStopTransparent,
        borderRadius: AppRadii.r18All,
        child: InkWell(
          borderRadius: AppRadii.r18All,
          onTap: () {
            if (isMultiSelectMode) {
              libraryCubit.toggleSongSelection(song.id);
            } else {
              playerCubit.playSong(song, queue: queue);
            }
          },
          onLongPress: () => libraryCubit.toggleSongSelection(song.id),
          child: Container(
            decoration: BoxDecoration(
              color: p.surfaceCard,
              borderRadius: AppRadii.r18All,
              border: Border.all(
                color: isSelected ? p.accent : p.hairline,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(17),
                        ),
                        child: CachedArtwork(
                          id: song.id,
                          remoteUrl: song.remoteArtworkUrl ?? song.artworkUri,
                          albumId: song.albumId,
                          type: ArtworkType.AUDIO,
                          size: double.infinity,
                          borderRadius: 17,
                        ),
                      ),
                      if (isSelected)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: p.accent.withValues(alpha: 0.45),
                              borderRadius: AppRadii.r16All,
                            ),
                            child: Center(
                              child: Icon(
                                Icons.check_circle_rounded,
                                color: p.onAccent,
                                size: 36,
                              ),
                            ),
                          ),
                        ),
                      if (AppConfig.ytmEnabled &&
                          song.remoteId != null &&
                          song.remoteId!.isNotEmpty)
                        PositionedDirectional(
                          start: 6,
                          top: 6,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.scrimAt(0.55),
                              shape: BoxShape.circle,
                            ),
                            child: YtmDownloadButton(
                              song: song,
                              activeColor:
                                  context.playerSurfacePalette.highContrastInk,
                              iconColor:
                                  context.playerSurfacePalette.highContrastInk,
                              iconSize: 18,
                            ),
                          ),
                        ),
                      if (badge != null && isLosslessSong(song))
                        PositionedDirectional(
                          start: 8,
                          bottom: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.scrimAt(0.68),
                              borderRadius: AppRadii.r6All,
                            ),
                            child: Text(
                              badge,
                              style: const TextStyle(
                                fontSize: AppFontSize.caption,
                                fontWeight: FontWeight.w800,
                                color: AppColors.qualityBadgeCyan,
                              ),
                            ),
                          ),
                        ),
                      PositionedDirectional(
                        end: 6,
                        top: 6,
                        child: Semantics(
                          button: true,
                          label: l10n.favorite,
                          child: Tooltip(
                            message: l10n.favorite,
                            child: Material(
                              color: AppColors.scrimAt(0.55),
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () =>
                                    libraryCubit.toggleFavorite(song.id),
                                child: SizedBox(
                                  width: AppSpacing.minTouchTarget,
                                  height: AppSpacing.minTouchTarget,
                                  child: Center(
                                    child: Icon(
                                      Icons.favorite_rounded,
                                      color: p.favorite,
                                      size: 18,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.s6,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppFontSize.label,
                          fontWeight: FontWeight.w700,
                          color: p.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppFontSize.caption,
                          color: p.textSecondary,
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
  }
}
