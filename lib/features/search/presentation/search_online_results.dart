part of 'search_screen.dart';

// ==================== ONLINE TAB ====================
class _OnlineResults extends StatelessWidget {
  final ValueChanged<String>? onSelectTag;

  const _OnlineResults({this.onSelectTag});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final playerCubit = context.read<PlayerCubit>();

    return BlocBuilder<YtmSearchCubit, YtmSearchState>(
      builder: (context, state) {
        final isOffline =
            context.watch<SettingsCubit?>()?.state.offlineOnlyMode ?? false;
        if (isOffline) {
          return Semantics(
            liveRegion: true,
            child: PulsrEmptyState(
              icon: Icons.wifi_off_rounded,
              title: context.l10n.offlineOnlyMode,
              subtitle: context.l10n.browseYtmSearchScreenDesc,
            ),
          );
        }

        final cubit = context.read<YtmSearchCubit>();
        final pending = cubit.isDebouncing;

        if ((state.isLoading || pending) && state.results.isEmpty) {
          return const SkeletonList(
            padding: EdgeInsets.only(top: AppSpacing.xs),
          );
        }

        if (state.errorMessage != null) {
          return Semantics(
            liveRegion: true,
            child: PulsrEmptyState(
              icon: Icons.cloud_off_rounded,
              title: context.l10n.browseSearchFailed,
              subtitle: resolveUiErrorMessage(context, state.errorMessage!),
              primaryActionLabel: context.l10n.tryAgain,
              primaryActionIcon: Icons.refresh_rounded,
              onPrimaryAction: cubit.retryAfterCooldown,
            ),
          );
        }

        if (state.results.isEmpty) {
          if (state.hasSearched && !pending) {
            return Semantics(
              liveRegion: true,
              child: PulsrEmptyState(
                icon: Icons.search_off_rounded,
                title: context.l10n.browseNoResultsFound,
                subtitle:
                    '${context.l10n.browseNoYtmMatchesFor} "${state.query.trim()}".',
              ),
            );
          }

          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.xl,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExcludeSemantics(
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: p.accent.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.travel_explore_rounded,
                        size: 32,
                        color: p.accent,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Semantics(
                    header: true,
                    child: Text(
                      context.l10n.searchYtm,
                      style: TextStyle(
                        fontSize: AppFontSize.title,
                        fontWeight: FontWeight.w800,
                        color: p.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s6),
                  Text(
                    context.l10n.ytmSearchDesc,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: p.textSecondary,
                      fontSize: AppFontSize.bodySmall,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final tag in _onlineTags)
                        PulsrChip(
                          icon: Icons.trending_up_rounded,
                          label: _localizedTag(context, tag),
                          variant: PulsrChipVariant.action,
                          onTap: () => onSelectTag?.call(tag),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }

        final songs = [for (final track in state.results) track.toSongData()];
        return Column(
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: cubit.botCooldown,
              builder: (context, coolingDown, _) {
                final status = cubit.statusMessageFor(coolingDown);
                if (status == null) return const SizedBox.shrink();
                return Semantics(
                  liveRegion: true,
                  child: Container(
                    width: double.infinity,
                    margin: EdgeInsetsDirectional.fromSTEB(
                      Adaptive.pagePadding(context),
                      AppSpacing.xxs,
                      Adaptive.pagePadding(context),
                      AppSpacing.xxs,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: 0.12),
                      borderRadius: AppRadii.r12All,
                      border:
                          Border.all(color: p.accent.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      children: [
                        ExcludeSemantics(
                          child: Icon(
                            Icons.shield_outlined,
                            size: 16,
                            color: p.accent,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            status,
                            style: TextStyle(
                              fontSize: AppFontSize.label,
                              color: p.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            if (cubit.showingCachedResults)
              Semantics(
                liveRegion: true,
                child: Container(
                  width: double.infinity,
                  margin: EdgeInsetsDirectional.fromSTEB(
                    Adaptive.pagePadding(context),
                    AppSpacing.xxs,
                    Adaptive.pagePadding(context),
                    AppSpacing.xxs,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: p.surfaceContainer,
                    borderRadius: AppRadii.r12All,
                    border: Border.all(color: p.hairline),
                  ),
                  child: Row(
                    children: [
                      ExcludeSemantics(
                        child: Icon(
                          Icons.history_rounded,
                          size: 16,
                          color: p.accent,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          context.l10n.ytmCachedResults,
                          style: TextStyle(
                            fontSize: AppFontSize.label,
                            color: p.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: PulsrRefreshIndicator(
                onRefresh: () async {
                  await cubit.retry();
                },
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification.metrics.extentAfter < 400 &&
                        cubit.hasMore &&
                        !state.isLoading &&
                        !state.loadMoreFailed) {
                      unawaited(cubit.loadMore());
                    }
                    return false;
                  },
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: true,
                    padding: EdgeInsets.only(
                      bottom: PulsrLayoutMetrics.scrollBottom(context),
                      top: AppSpacing.xxs,
                    ),
                    itemCount: songs.length +
                        (state.isLoading || state.loadMoreFailed ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= songs.length) {
                        if (state.loadMoreFailed) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.sm,
                            ),
                            child: Center(
                              child: TextButton.icon(
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(
                                    AppSpacing.minTouchTarget,
                                    AppSpacing.minTouchTarget,
                                  ),
                                ),
                                onPressed: () => cubit.loadMore(),
                                icon: const Icon(
                                  Icons.refresh_rounded,
                                  size: 18,
                                ),
                                label: Text(context.l10n.retry),
                              ),
                            ),
                          );
                        }
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.sm,
                          ),
                          child: Center(
                            child: PulsrProgressBar.circular(
                              size: 22,
                              strokeWidth: 2.4,
                              color: p.accent,
                            ),
                          ),
                        );
                      }
                      final song = songs[index];
                      return HighlightedSongTile(
                        song: song,
                        query: state.query,
                        subtitleOverride: state.results[index].artist,
                        onTap: () {
                          cubit.commitQuery();
                          context.read<SearchCubit?>()?.recordPlayedSong(song);
                          playerCubit.playSong(song, queue: songs);
                        },
                        onLongPress: () =>
                            _showOnlineTrackActions(context, song, p),
                        onMorePressed: () =>
                            _showOnlineTrackActions(context, song, p),
                        trailing: YtmDownloadButton(song: song),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

Future<void> _showOnlineTrackActions(
  BuildContext context,
  SongsTableData song,
  PulsrPalette p,
) {
  return PulsrSheetHelper.showPulsrSheet<void>(
    context: context,
    builder: (sheetContext) => PulsrBottomSheet(
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
            minTileHeight: AppSpacing.minTouchTarget,
            leading: Icon(Icons.playlist_play_rounded, color: p.accent),
            title: Text(context.l10n.playNext),
            onTap: () {
              Navigator.of(sheetContext).pop();
              context.read<PlayerCubit>().playNext(song);
            },
          ),
          ListTile(
            minTileHeight: AppSpacing.minTouchTarget,
            leading: Icon(Icons.queue_music_rounded, color: p.accent),
            title: Text(context.l10n.addToQueue),
            onTap: () {
              Navigator.of(sheetContext).pop();
              context.read<PlayerCubit>().addAllToQueue([song]);
            },
          ),
          ListTile(
            minTileHeight: AppSpacing.minTouchTarget,
            leading: Icon(Icons.download_rounded, color: p.accent),
            title: Text(context.l10n.browseDownloadOffline),
            onTap: () {
              Navigator.of(sheetContext).pop();
              context.read<YtmDownloadCubit?>()?.download(song);
            },
          ),
          ListTile(
            minTileHeight: AppSpacing.minTouchTarget,
            leading: Icon(Icons.playlist_add_rounded, color: p.accent),
            title: Text(context.l10n.addToPlaylist),
            onTap: () {
              Navigator.of(sheetContext).pop();
              AddToPlaylistSheet.show(context, song: song);
            },
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
      ),
    ),
  );
}
