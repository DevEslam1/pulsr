part of '../library_screen.dart';

mixin LibrarySongsTab on State<LibraryScreen> {
  // ================= SONGS =================
  Widget _buildSongsTab(BuildContext context, LibraryState state,
      LibraryCubit cubit, PlayerCubit playerCubit) {
    final p = context.palette;
    final songs = state.songs;
    if (songs.isEmpty) {
      if (state.isLoading) {
        return SkeletonList(
          padding: EdgeInsets.fromLTRB(Adaptive.pagePadding(context), 16,
              Adaptive.pagePadding(context), 160),
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
        onRefresh: () => _handleRefresh(context),
        child: GridView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(Adaptive.pagePadding(context), 16,
              Adaptive.pagePadding(context), 160),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: Adaptive.gridColumns(context, minItemWidth: 155),
            crossAxisSpacing: 14,
            mainAxisSpacing: 18,
            childAspectRatio: 0.76,
          ),
          itemCount: songs.length,
          itemBuilder: (context, index) {
            final song = songs[index];
            final isSelected = state.selectedSongIds.contains(song.id);
            return InkWell(
              borderRadius: BorderRadius.circular(18),
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
                            remoteUrl: song.remoteArtworkUrl,
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
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: const Center(
                                child: Icon(Icons.check_circle_rounded,
                                    color: Colors.white, size: 36),
                              ),
                            ),
                          ),
                        Positioned(
                          right: 6,
                          top: 6,
                          child: Material(
                            color: Colors.black.withValues(alpha: 0.5),
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () => SongInfoSheet.show(context, song: song),
                              child: const Padding(
                                padding: EdgeInsets.all(6.0),
                                child: Icon(Icons.more_vert_rounded,
                                    color: Colors.white, size: 18),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.textSecondary, fontSize: 11.5),
                  ),
                ],
              ),
            );
          },
        ),
      );
    }

    // The A–Z rail only makes sense when the list is ordered by title.
    final showAlphabet = songs.length >= 15 && state.sortBy == 'title';
    final alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ#'.split('');

    final trackCols = context.trackGridColumns;
    final hasMore = cubit.hasMoreSongs;

    Widget buildLoadMoreTile() {
      return SizedBox(
        height: trackCols > 1 ? 72 : _LibraryScreenState._songRowExtent,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: p.accent),
            ),
          ),
        ),
      );
    }

    Widget buildSongItem(SongsTableData song, int index) {
      return PulsrDismissible(
        key: ValueKey('song_${song.id}'),
        startToEndLabel: context.l10n.playNext,
        endToStartLabel: context.l10n.favorite,
        backgroundBuilder: (context, isConfirming) => PulsrDismissible.buildActionBackground(
          context: context,
          icon: Icons.playlist_play_rounded,
          label: context.l10n.playNext,
          color: p.accent,
          backgroundColor: p.accentContainer,
          isConfirming: isConfirming,
        ),
        secondaryBackgroundBuilder: (context, isConfirming) => PulsrDismissible.buildActionBackground(
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

    return RefreshIndicator(
      onRefresh: () => _handleRefresh(context),
      child: Stack(
        children: [
          trackCols > 1
              ? GridView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  controller: _songsScrollController,
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: true,
                  padding: const EdgeInsets.only(
                      bottom: 160, top: 8, left: 6, right: 6),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: trackCols,
                    mainAxisExtent: 72,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 4,
                  ),
                  itemCount: songs.length + (hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= songs.length) return buildLoadMoreTile();
                    return buildSongItem(songs[index], index);
                  },
                )
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  controller: _songsScrollController,
                  itemExtent: songs.length > 500 ? _LibraryScreenState._songRowExtent : null,
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: true,
                  padding: const EdgeInsets.only(
                      bottom: 160, top: 8, left: 4, right: 4),
                  itemCount: songs.length + (hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= songs.length) return buildLoadMoreTile();
                    return buildSongItem(songs[index], index);
                  },
                ),
          if (showAlphabet)
            PositionedDirectional(
              end: 4,
              top: 8,
              bottom: 150,
              child: Container(
                width: 30,
                decoration: BoxDecoration(
                    color: p.surfaceContainer.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(15)),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: alphabet
                        .map((l) => Semantics(
                              button: true,
                              label: l,
                              excludeSemantics: true,
                              child: InkWell(
                                onTap: () => _scrollToLetter(l, songs),
                                child: SizedBox(
                                  width: 30,
                                  height: 18,
                                  child: Center(
                                    child: Text(l,
                                        style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            color: p.textTertiary)),
                                  ),
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
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
    final trackCols = context.trackGridColumns;

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
      onRefresh: () => _handleRefresh(context),
      child: Column(
        children: [
          // ---------- Header Card with Play All & Shuffle ----------
          Padding(
            padding: EdgeInsets.fromLTRB(Adaptive.pagePadding(context), 12,
                Adaptive.pagePadding(context), 8),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    p.accent.withValues(alpha: 0.15),
                    p.surfaceContainer,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: p.accent.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.download_done_rounded,
                        color: p.accent, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.offlineDownloads,
                          style: TextStyle(
                            color: p.textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          context.l10n.tracksCount(downloaded.length),
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: p.accent,
                      foregroundColor: p.onAccent,
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 24),
                    tooltip: context.l10n.playAll,
                    onPressed: () => playerCubit.playSong(downloaded.first,
                        queue: downloaded),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filledTonal(
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
                    padding: const EdgeInsets.only(
                        bottom: 160, top: 4, left: 6, right: 6),
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
                        backgroundBuilder: (context, isConfirming) => PulsrDismissible.buildActionBackground(
                          context: context,
                          icon: Icons.playlist_play_rounded,
                          label: context.l10n.playNext,
                          color: p.accent,
                          backgroundColor: p.accentContainer,
                          isConfirming: isConfirming,
                        ),
                        secondaryBackgroundBuilder: (context, isConfirming) => PulsrDismissible.buildActionBackground(
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
                          index: index + 1,
                          selected: state.selectedSongIds.contains(song.id),
                          onTap: () {
                            if (state.isMultiSelectMode) {
                              cubit.toggleSongSelection(song.id);
                            } else {
                              playerCubit.playSong(song, queue: downloaded);
                            }
                          },
                          onLongPress: () => cubit.toggleSongSelection(song.id),
                          onMorePressed: () => SongInfoSheet.show(context, song: song),
                        ),
                      );
                    },
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding:
                        const EdgeInsets.only(bottom: 160, top: 4, left: 4, right: 4),
                    itemCount: downloaded.length,
                    itemBuilder: (context, index) {
                      final song = downloaded[index];
                      return PulsrDismissible(
                        key: ValueKey('dl_${song.id}'),
                        startToEndLabel: context.l10n.playNext,
                        endToStartLabel: context.l10n.favorite,
                        backgroundBuilder: (context, isConfirming) => PulsrDismissible.buildActionBackground(
                          context: context,
                          icon: Icons.playlist_play_rounded,
                          label: context.l10n.playNext,
                          color: p.accent,
                          backgroundColor: p.accentContainer,
                          isConfirming: isConfirming,
                        ),
                        secondaryBackgroundBuilder: (context, isConfirming) => PulsrDismissible.buildActionBackground(
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
                          index: index + 1,
                          selected: state.selectedSongIds.contains(song.id),
                          onTap: () {
                            if (state.isMultiSelectMode) {
                              cubit.toggleSongSelection(song.id);
                            } else {
                              playerCubit.playSong(song, queue: downloaded);
                            }
                          },
                          onLongPress: () => cubit.toggleSongSelection(song.id),
                          onMorePressed: () => SongInfoSheet.show(context, song: song),
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
  Widget _buildEmpty( BuildContext context, { required String title, required String subtitle, required IconData icon, String? actionLabel, IconData? actionIcon, VoidCallback? onAction, });

  // Requires: provided by the composing class (same library).
  Future<void> _handleRefresh(BuildContext context);

  // Requires: provided by the composing class (same library).
  void _scrollToLetter(String letter, List<SongsTableData> songs);

  // Requires: provided by the composing class (same library).
  ScrollController get _songsScrollController;
}
