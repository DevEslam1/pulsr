part of '../library_screen.dart';

mixin LibrarySongsTab on State<LibraryScreen> {
  /// Ensures the list head is pre-resolved exactly once per screen, so the
  /// first online taps don't pay the network resolve. Warms the top few online
  /// tracks (staggered inside [warmStreams]) rather than just the first, since
  /// a user often taps a little way down a freshly opened list.
  bool _warmedHeadOnline = false;
  // BUG-04: identity signature of the list head, so a rescan that inserts new
  // online tracks at the top re-arms the pre-warm instead of short-circuiting
  // forever on `_warmedHeadOnline`.
  int? _warmedHeadSignature;

  void _warmHeadOnlineIfNeeded(
      List<SongsTableData> songs, PlayerCubit playerCubit) {
    if (songs.isEmpty) return;
    final signature = Object.hashAll(songs.take(20).map((s) => s.id));
    if (_warmedHeadOnline && _warmedHeadSignature == signature) return;
    _warmedHeadOnline = true;
    _warmedHeadSignature = signature;
    final online = [
      for (final s in songs)
        if (s.source == SongSource.youtube &&
            s.isDownloaded != true &&
            (s.remoteId?.isNotEmpty ?? false))
          s,
    ];
    if (online.isEmpty) return;
    playerCubit.warmStreams(online, count: 3);
  }

  // ================= SONGS =================
  Widget _buildSongsTab(BuildContext context, LibraryState state,
      LibraryCubit cubit, PlayerCubit playerCubit) {
    final p = context.palette;
    final songs = state.songs;
    _warmHeadOnlineIfNeeded(songs, playerCubit);
    if (songs.isEmpty) {
      if (state.isLoading) {
        return SkeletonList(
          padding: EdgeInsetsDirectional.fromSTEB(Adaptive.pagePadding(context),
              16, Adaptive.pagePadding(context), 160),
        );
      }
      return _buildEmpty(context,
          title: context.l10n.noSongsFound,
          subtitle: context.l10n.noSongsSubtitle,
          icon: Icons.music_note_rounded);
    }

    final isGrid = state.viewMode == LibraryViewMode.grid;

    if (isGrid) {
      return RefreshIndicator(
        color: p.accent,
        backgroundColor: p.surfaceContainer,
        onRefresh: () => _handleRefresh(context),
        child: GridView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: true,
          padding: EdgeInsetsDirectional.fromSTEB(Adaptive.pagePadding(context),
              16, Adaptive.pagePadding(context), 160),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: PulsrAdaptiveGrid.dynamicColumns(
              context,
              minItemWidth: 160,
              minColumns: 2,
              maxColumns: 6,
            ),
            crossAxisSpacing: 14,
            mainAxisSpacing: 18,
            childAspectRatio: 0.76,
          ),
          itemCount: songs.length,
          itemBuilder: (context, index) {
            final song = songs[index];
            final isSelected = state.selectedSongIds.contains(song.id);
            return Semantics(
              button: true,
              selected: isSelected,
              label: '${song.title}, ${song.artist}',
              child: InkWell(
                borderRadius: AppRadii.r18All,
                onTap: () {
                  if (state.isMultiSelectMode) {
                    cubit.toggleSongSelection(song.id);
                  } else {
                    playerCubit.playSong(song, queue: songs);
                  }
                },
                onLongPress: () => cubit.toggleSongSelection(song.id),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: CachedArtwork(
                              id: song.id,
                              remoteUrl:
                                  song.remoteArtworkUrl ?? song.artworkUri,
                              albumId: song.albumId,
                              type: ArtworkType.AUDIO,
                              size: double.infinity,
                              borderRadius: 18,
                            ),
                          ),
                          if (isSelected)
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: p.accent.withValues(alpha: 0.45),
                                  borderRadius: AppRadii.r18All,
                                ),
                                child: const Center(
                                  child: Icon(Icons.check_circle_rounded,
                                      color: Colors.white, size: 36),
                                ),
                              ),
                            ),
                          PositionedDirectional(
                            end: 6,
                            top: 6,
                            child: Material(
                              color: AppColors.scrimAt(0.5),
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () =>
                                    SongInfoSheet.show(context, song: song),
                                child: const Padding(
                                  padding: EdgeInsets.all(AppSpacing.s6),
                                  child: Icon(Icons.more_vert_rounded,
                                      color: Colors.white, size: 18),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: AppFontSize.bodySmall),
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
            );
          },
        ),
      );
    }

    final alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ#'.split('');

    final trackCols = PulsrAdaptiveGrid.songColumns(context);
    final hasMore = cubit.hasMoreSongs;

    Widget buildLoadMoreTile() {
      if (!state.isLoadingMore) return const SizedBox.shrink();
      return const SkeletonShimmer(
        child: SkeletonSongRow(artworkSize: 40),
      );
    }

    Widget buildSongItem(SongsTableData song, int index) {
      return PulsrDismissible(
        key: ValueKey('song_${song.id}'),
        startToEndLabel: context.l10n.playNext,
        endToStartLabel: context.l10n.favorite,
        backgroundBuilder: (context, isConfirming) =>
            PulsrDismissible.buildActionBackground(
          context: context,
          icon: Icons.playlist_play_rounded,
          label: context.l10n.playNext,
          color: p.accent,
          backgroundColor: p.accentContainer,
          isConfirming: isConfirming,
        ),
        secondaryBackgroundBuilder: (context, isConfirming) =>
            PulsrDismissible.buildActionBackground(
          context: context,
          icon: Icons.favorite_rounded,
          label: context.l10n.favorite,
          color: p.favorite,
          backgroundColor: p.favorite.withValues(alpha: 0.2),
          isConfirming: isConfirming,
          isEnd: true,
        ),
        onConfirm: (direction) async {
          if (direction == DismissDirection.startToEnd) {
            playerCubit.playNext(song);
          } else {
            cubit.toggleFavorite(song.id);
          }
          return false;
        },
        child: SongTile(
          song: song,
          selected: state.selectedSongIds.contains(song.id),
          onTap: () {
            if (state.isMultiSelectMode) {
              cubit.toggleSongSelection(song.id);
            } else {
              playerCubit.playSong(song, queue: songs);
            }
          },
          onLongPress: () => cubit.toggleSongSelection(song.id),
          onMorePressed: () => SongInfoSheet.show(context, song: song),
        ),
      );
    }

    // BUG-13: gate the A–Z rail on the space actually available to the list
    // area, not the full window height.
    return LayoutBuilder(builder: (context, constraints) {
      final showAlphabet = songs.length >= 15 &&
          state.sortBy == 'title' &&
          constraints.maxHeight >= 500;
      return RefreshIndicator(
        color: p.accent,
        backgroundColor: p.surfaceContainer,
        onRefresh: () => _handleRefresh(context),
        child: Stack(
          children: [
            trackCols > 1
                ? GridView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    controller: _songsScrollController,
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: true,
                    padding: const EdgeInsetsDirectional.only(
                        bottom: AppSpacing.scrollBottom,
                        top: AppSpacing.xs,
                        start: AppSpacing.s6,
                        end: AppSpacing.s6),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: trackCols,
                      mainAxisExtent: 72,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 4,
                    ),
                    itemCount: songs.length + (hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= songs.length) return buildLoadMoreTile();
                      return StaggeredReveal(
                        index: index,
                        groupKey: '${state.sortBy}-${state.ascending}',
                        child: buildSongItem(songs[index], index),
                      );
                    },
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    controller: _songsScrollController,
                    itemExtent: songs.length > 500
                        ? _LibraryScreenState._songRowExtent
                        : null,
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: true,
                    padding: const EdgeInsetsDirectional.only(
                        bottom: AppSpacing.scrollBottom,
                        top: AppSpacing.xs,
                        start: AppSpacing.xxs,
                        end: AppSpacing.xxs),
                    itemCount: songs.length + (hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= songs.length) return buildLoadMoreTile();
                      return StaggeredReveal(
                        index: index,
                        groupKey: '${state.sortBy}-${state.ascending}',
                        child: buildSongItem(songs[index], index),
                      );
                    },
                  ),
            if (showAlphabet)
              PositionedDirectional(
                end: 4,
                top: 8,
                bottom: 150,
                child: AlphabetQuickScroll(
                  availableLetters: alphabet,
                  onLetterSelected: (l) => _scrollToLetter(l, songs),
                ),
              ),
          ],
        ),
      );
    });
  }

  // ================= DOWNLOADED =================
  Widget _buildDownloadedTab(
    BuildContext context,
    LibraryState state,
    LibraryCubit cubit,
    PlayerCubit playerCubit,
  ) {
    final p = context.palette;
    final downloaded = state.songs.where((s) => _isOnlineDownload(s)).toList();
    final trackCols = PulsrAdaptiveGrid.songColumns(context);

    if (downloaded.isEmpty) {
      return _buildEmpty(
        context,
        icon: Icons.cloud_download_rounded,
        title: context.l10n.noDownloadsYet,
        subtitle: context.l10n.noDownloadsYetSubtitle,
        actionLabel: context.l10n.exploreOnlineMusic,
        actionIcon: Icons.travel_explore_rounded,
        onAction: () => context.go('/'),
      );
    }

    return RefreshIndicator(
      color: p.accent,
      backgroundColor: p.surfaceContainer,
      onRefresh: () => _handleRefresh(context),
      child: Column(
        children: [
          // ---------- Header Card with Play All & Shuffle ----------
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
                Adaptive.pagePadding(context),
                12,
                Adaptive.pagePadding(context),
                8),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    p.accent.withValues(alpha: 0.15),
                    p.surfaceContainer,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: AppRadii.r20All,
                border: Border.all(color: p.accent.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.s10),
                    decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.download_done_rounded,
                        color: p.accent, size: 24),
                  ),
                  const SizedBox(width: AppSpacing.s14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.offlineDownloads,
                          style: TextStyle(
                            color: p.textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: AppFontSize.callout,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s2),
                        Text(
                          context.l10n.tracksCount(downloaded.length),
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: AppFontSize.label,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filled(
                    constraints: const BoxConstraints(
                        minWidth: AppSpacing.minTouchTarget,
                        minHeight: AppSpacing.minTouchTarget),
                    style: IconButton.styleFrom(
                      backgroundColor: p.accent,
                      foregroundColor: p.onAccent,
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 24),
                    tooltip: context.l10n.playAll,
                    onPressed: () => playerCubit.playSong(downloaded.first,
                        queue: downloaded),
                  ),
                  const SizedBox(width: AppSpacing.s6),
                  IconButton.filledTonal(
                    constraints: const BoxConstraints(
                        minWidth: AppSpacing.minTouchTarget,
                        minHeight: AppSpacing.minTouchTarget),
                    style: IconButton.styleFrom(
                      backgroundColor: p.surfaceContainerHigh,
                      foregroundColor: p.textPrimary,
                    ),
                    icon: const Icon(Icons.shuffle_rounded, size: 20),
                    tooltip: context.l10n.shuffle,
                    onPressed: () {
                      final shuffled = List<SongsTableData>.from(downloaded)
                        ..shuffle();
                      playerCubit.playSong(shuffled.first, queue: shuffled);
                    },
                  ),
                ],
              ),
            ),
          ),

          // ---------- List of Downloaded Songs ----------
          Expanded(
            child: trackCols > 1
                ? GridView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: true,
                    padding: const EdgeInsetsDirectional.only(
                        bottom: AppSpacing.scrollBottom,
                        top: AppSpacing.xxs,
                        start: AppSpacing.s6,
                        end: AppSpacing.s6),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: trackCols,
                      mainAxisExtent: 72,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 4,
                    ),
                    itemCount: downloaded.length,
                    itemBuilder: (context, index) {
                      final song = downloaded[index];
                      return PulsrDismissible(
                        key: ValueKey('dl_${song.id}'),
                        startToEndLabel: context.l10n.playNext,
                        endToStartLabel: context.l10n.favorite,
                        backgroundBuilder: (context, isConfirming) =>
                            PulsrDismissible.buildActionBackground(
                          context: context,
                          icon: Icons.playlist_play_rounded,
                          label: context.l10n.playNext,
                          color: p.accent,
                          backgroundColor: p.accentContainer,
                          isConfirming: isConfirming,
                        ),
                        secondaryBackgroundBuilder: (context, isConfirming) =>
                            PulsrDismissible.buildActionBackground(
                          context: context,
                          icon: Icons.favorite_rounded,
                          label: context.l10n.favorite,
                          color: p.favorite,
                          backgroundColor: p.favorite.withValues(alpha: 0.2),
                          isConfirming: isConfirming,
                          isEnd: true,
                        ),
                        onConfirm: (direction) async {
                          if (direction == DismissDirection.startToEnd) {
                            playerCubit.playNext(song);
                          } else {
                            cubit.toggleFavorite(song.id);
                          }
                          return false;
                        },
                        child: SongTile(
                          song: song,
                          index: index,
                          selected: state.selectedSongIds.contains(song.id),
                          onTap: () {
                            if (state.isMultiSelectMode) {
                              cubit.toggleSongSelection(song.id);
                            } else {
                              playerCubit.playSong(song, queue: downloaded);
                            }
                          },
                          onLongPress: () => cubit.toggleSongSelection(song.id),
                          onMorePressed: () =>
                              SongInfoSheet.show(context, song: song),
                        ),
                      );
                    },
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: true,
                    padding: const EdgeInsetsDirectional.only(
                        bottom: AppSpacing.scrollBottom,
                        top: AppSpacing.xxs,
                        start: AppSpacing.xxs,
                        end: AppSpacing.xxs),
                    itemCount: downloaded.length,
                    itemBuilder: (context, index) {
                      final song = downloaded[index];
                      return PulsrDismissible(
                        key: ValueKey('dl_${song.id}'),
                        startToEndLabel: context.l10n.playNext,
                        endToStartLabel: context.l10n.favorite,
                        backgroundBuilder: (context, isConfirming) =>
                            PulsrDismissible.buildActionBackground(
                          context: context,
                          icon: Icons.playlist_play_rounded,
                          label: context.l10n.playNext,
                          color: p.accent,
                          backgroundColor: p.accentContainer,
                          isConfirming: isConfirming,
                        ),
                        secondaryBackgroundBuilder: (context, isConfirming) =>
                            PulsrDismissible.buildActionBackground(
                          context: context,
                          icon: Icons.favorite_rounded,
                          label: context.l10n.favorite,
                          color: p.favorite,
                          backgroundColor: p.favorite.withValues(alpha: 0.2),
                          isConfirming: isConfirming,
                          isEnd: true,
                        ),
                        onConfirm: (direction) async {
                          if (direction == DismissDirection.startToEnd) {
                            playerCubit.playNext(song);
                          } else {
                            cubit.toggleFavorite(song.id);
                          }
                          return false;
                        },
                        child: SongTile(
                          song: song,
                          index: index,
                          selected: state.selectedSongIds.contains(song.id),
                          onTap: () {
                            if (state.isMultiSelectMode) {
                              cubit.toggleSongSelection(song.id);
                            } else {
                              playerCubit.playSong(song, queue: downloaded);
                            }
                          },
                          onLongPress: () => cubit.toggleSongSelection(song.id),
                          onMorePressed: () =>
                              SongInfoSheet.show(context, song: song),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  bool _isOnlineDownload(SongsTableData s) => isDownloadedOnlineTrack(s);

  // Requires: provided by the composing class (same library).
  Widget _buildEmpty(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    String? actionLabel,
    IconData? actionIcon,
    VoidCallback? onAction,
  });

  // Requires: provided by the composing class (same library).
  Future<void> _handleRefresh(BuildContext context);

  // Requires: provided by the composing class (same library).
  void _scrollToLetter(String letter, List<SongsTableData> songs);

  // Requires: provided by the composing class (same library).
  ScrollController get _songsScrollController;
}
