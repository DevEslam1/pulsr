part of '../library_screen.dart';

mixin LibraryFavoritesTab on State<LibraryScreen> {
  // ================= FAVORITES =================
  Widget _buildFavoritesTab(
      BuildContext context, LibraryState state, PlayerCubit playerCubit) {
    final p = context.palette;
    final cubit = context.read<LibraryCubit>();
    final allFavorites = state.favorites;
    final localFavorites =
        allFavorites.where((s) => !_isOnlineFavorite(s)).toList();
    final onlineFavorites =
        allFavorites.where((s) => _isOnlineFavorite(s)).toList();

    final currentFavorites =
        _favTabFilter == 0 ? localFavorites : onlineFavorites;
    final isGrid = state.viewMode == LibraryViewMode.grid;

    return RefreshIndicator(
      color: p.accent,
      backgroundColor: p.surfaceContainer,
      onRefresh: () => _favTabFilter == 1 && AppConfig.ytmEnabled
          ? _syncYtmLikes(context)
          : _handleRefresh(context),
      child: Column(
        children: [
          // ---------- Sub Tabs Switcher (Local / Online) ----------
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(Adaptive.pagePadding(context), 12,
                Adaptive.pagePadding(context), 8),
            child: PulsrSegmentedControl(
              selectedIndex: _favTabFilter,
              onChanged: (i) => setState(() => _favTabFilter = i),
              segments: [
                PulsrSegment(
                  label: context.l10n.local,
                  icon: Icons.folder_rounded,
                  count: localFavorites.length,
                ),
                PulsrSegment(
                  label: context.l10n.online,
                  icon: Icons.cloud_rounded,
                  count: onlineFavorites.length,
                ),
              ],
            ),
          ),

          // ---------- Quick Play Header (if songs exist in current tab) ----------
          if (currentFavorites.isNotEmpty)
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: Adaptive.pagePadding(context),
                vertical: 4,
              ),
              child: Row(
                children: [
                  Text(
                    context.l10n.tracksCount(currentFavorites.length),
                    style: TextStyle(
                      color: p.textSecondary,
                      fontSize: AppFontSize.bodySmall,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  FilledButton.tonalIcon(
                    onPressed: () => playerCubit.playSong(
                        currentFavorites.first,
                        queue: currentFavorites),
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    label: Text(context.l10n.playAll),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: p.accent.withValues(alpha: 0.15),
                      foregroundColor: p.accent,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  IconButton.filledTonal(
                    onPressed: () {
                      final shuffled =
                          List<SongsTableData>.from(currentFavorites)
                            ..shuffle();
                      playerCubit.playSong(shuffled.first, queue: shuffled);
                    },
                    icon: const Icon(Icons.shuffle_rounded, size: 18),
                    style: IconButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: p.surfaceContainerHigh,
                      foregroundColor: p.textPrimary,
                    ),
                    tooltip: context.l10n.shuffle,
                  ),
                  if (AppConfig.ytmEnabled) ...[
                    const SizedBox(width: AppSpacing.xs),
                    IconButton.filledTonal(
                      onPressed: () =>
                          _downloadFavorites(context, currentFavorites),
                      icon: const Icon(Icons.download_rounded, size: 20),
                      style: IconButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: p.accent.withValues(alpha: 0.15),
                        foregroundColor: p.accent,
                      ),
                      tooltip: context.l10n.browseDownloadAllLikedSongs,
                    ),
                  ],
                  if (_favTabFilter == 1 && AppConfig.ytmEnabled) ...[
                    const SizedBox(width: AppSpacing.xs),
                    IconButton.filledTonal(
                      onPressed: () => _syncYtmLikes(context),
                      icon: const Icon(Icons.sync_rounded, size: 20),
                      style: IconButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: p.accent.withValues(alpha: 0.15),
                        foregroundColor: p.accent,
                      ),
                      tooltip: context.l10n.syncYouTubeMusic,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    IconButton.filledTonal(
                      onPressed: () => _showImportYtmFavoritesDialog(context),
                      icon: const Icon(Icons.link_rounded, size: 20),
                      style: IconButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: p.surfaceContainerHigh,
                        foregroundColor: p.textPrimary,
                      ),
                      tooltip: context.l10n.importByPlaylistLink,
                    ),
                  ],
                ],
              ),
            ),

          // ---------- Content (List / Grid or Empty State) ----------
          Expanded(
            child: currentFavorites.isEmpty
                ? CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _buildFavoritesEmptyState(
                            context, p, _favTabFilter),
                      ),
                    ],
                  )
                : (isGrid
                    ? GridView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        addAutomaticKeepAlives: false,
                        addRepaintBoundaries: true,
                        padding: EdgeInsetsDirectional.fromSTEB(
                          Adaptive.pagePadding(context),
                          8,
                          Adaptive.pagePadding(context),
                          160,
                        ),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount:
                              Adaptive.gridColumns(context, minItemWidth: 155),
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 18,
                          childAspectRatio: 0.76,
                        ),
                        itemCount: currentFavorites.length,
                        itemBuilder: (context, index) {
                          final song = currentFavorites[index];
                          return StaggeredReveal(
                            index: index,
                            groupKey: currentFavorites.isEmpty
                                ? ''
                                : '${currentFavorites.first.id}-${currentFavorites.length}',
                            child: _buildFavoriteGridCard(
                                context, song, currentFavorites, p, playerCubit),
                          );
                        },
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        addAutomaticKeepAlives: false,
                        addRepaintBoundaries: true,
                        padding: const EdgeInsetsDirectional.only(
                            bottom: AppSpacing.scrollBottom, top: AppSpacing.xxs, start: AppSpacing.xxs, end: AppSpacing.xxs),
                        itemCount: currentFavorites.length,
                        itemBuilder: (context, index) {
                          final song = currentFavorites[index];
                          return StaggeredReveal(
                            index: index,
                            groupKey: currentFavorites.isEmpty
                                ? ''
                                : '${currentFavorites.first.id}-${currentFavorites.length}',
                            child: PulsrDismissible(
                            key: ValueKey('fav_${song.id}'),
                            startToEndLabel: context.l10n.playNext,
                            endToStartLabel: context.l10n.delete,
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
                              icon: Icons.delete_outline_rounded,
                              label: context.l10n.delete,
                              color: p.error,
                              backgroundColor: p.error.withValues(alpha: 0.2),
                              isConfirming: isConfirming,
                              isEnd: true,
                            ),
                            onConfirm: (direction) async {
                              if (direction == DismissDirection.startToEnd) {
                                HapticFeedback.lightImpact();
                                playerCubit.playNext(song);
                              } else {
                                HapticFeedback.mediumImpact();
                                cubit.toggleFavorite(song.id);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(context.l10n
                                          .removedFavorite(song.title)),
                                      duration: const Duration(seconds: 4),
                                      action: SnackBarAction(
                                        label: context.l10n.undo,
                                        onPressed: () {
                                          cubit.toggleFavorite(song.id);
                                        },
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
                              selected: state.selectedSongIds.contains(song.id),
                              onTap: () {
                                if (state.isMultiSelectMode) {
                                  cubit.toggleSongSelection(song.id);
                                } else {
                                  playerCubit.playSong(song,
                                      queue: currentFavorites);
                                }
                              },
                              onLongPress: () =>
                                  cubit.toggleSongSelection(song.id),
                              onMorePressed: () => SongInfoSheet.show(context, song: song),
                            ),
                          ));
                        },
                      )),
          ),
        ],
      ),
    );
  }

  bool _isOnlineFavorite(SongsTableData s) => isOnlineFavorite(s);

  Widget _buildFavoritesEmptyState(
      BuildContext context, PulsrPalette p, int tabIndex) {
    if (tabIndex == 0) {
      return EmptyStateWidget(
        icon: Icons.favorite_border_rounded,
        iconColor: p.favorite,
        title: context.l10n.noLocalFavorites,
        subtitle: context.l10n.noLocalFavoritesSubtitle,
        primaryActionLabel: context.l10n.songs,
        primaryActionIcon: Icons.library_music_rounded,
        onPrimaryAction: () => _tabController.animateTo(0),
      );
    } else {
      final ytmAccount = getIt<YtmAccountService>();
      final isYtmLoggedIn = ytmAccount.isLoggedIn;

      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          EmptyStateWidget(
            icon: Icons.cloud_sync_rounded,
            iconColor: p.accent,
            title: isYtmLoggedIn
                ? context.l10n.ytmConnected
                : context.l10n.noOnlineFavorites,
            subtitle: isYtmLoggedIn
                ? context.l10n.browseSyncPullSubtitle
                : context.l10n.connectYtmSubtitle,
            primaryActionLabel: AppConfig.ytmEnabled
                ? (isYtmLoggedIn
                    ? context.l10n.syncYouTubeMusic
                    : context.l10n.connectYtmAccount)
                : context.l10n.navLibrary,
            primaryActionIcon: AppConfig.ytmEnabled
                ? Icons.cloud_sync_rounded
                : Icons.library_music_rounded,
            onPrimaryAction: () {
              if (AppConfig.ytmEnabled) {
                _syncYtmLikes(context);
              } else {
                _tabController.animateTo(0);
              }
            },
          ),
          if (AppConfig.ytmEnabled) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: TextButton.icon(
                onPressed: () => _showImportYtmFavoritesDialog(context),
                icon: const Icon(Icons.link_rounded, size: 18),
                label: Text(context.l10n.importByPlaylistLink),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: TextButton.icon(
                onPressed: () => context.push('/ytm-search'),
                icon: const Icon(Icons.travel_explore_rounded, size: 18),
                label: Text(context.l10n.searchYtm),
              ),
            ),
          ],
        ],
      );
    }
  }

  void _downloadFavorites(BuildContext context, List<SongsTableData> songs) {
    if (songs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.noFavToDownload)),
      );
      return;
    }

    final downloadCubit = context.read<YtmDownloadCubit?>() ??
        (getIt.isRegistered<YtmDownloadCubit>() ? getIt<YtmDownloadCubit>() : null);
    if (downloadCubit == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Download service unavailable')),
      );
      return;
    }
    final queuedCount = downloadCubit.downloadAll(songs);

    if (queuedCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              context.l10n.queuedForDownload(queuedCount)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      final hasOnlineTracks =
          songs.any((s) => s.remoteId != null && s.remoteId!.isNotEmpty);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            hasOnlineTracks
                ? context.l10n.browseAllOnlineLikedDownloaded
                : context.l10n.browseAllSongsOffline,
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _syncYtmLikes(BuildContext context) async {
    final accountService = getIt<YtmAccountService>();
    if (!accountService.isLoggedIn) {
      final success = await YtmWebLoginSheet.show(context);
      if (success != true) return;
    }

    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final authCubit = context.read<AuthCubit>();
    final libraryCubit = context.read<LibraryCubit>();

    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: AppSpacing.md,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.onInverseSurface,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(context.l10n.syncingYtm),
          ],
        ),
        duration: const Duration(seconds: 4),
      ),
    );

    try {
      final count = await libraryCubit.syncYtmAccountLikes();
      if (context.mounted) {
        if (_favTabFilter != 1) {
          setState(() => _favTabFilter = 1);
        }
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text(context.l10n.syncedOnline(count)),
            behavior: SnackBarBehavior.floating,
          ),
        );
        try {
          authCubit.syncNow();
        } catch (_) {}
      }
    } catch (e) {
      if (context.mounted) {
        messenger.hideCurrentSnackBar();
        final isAuth = (e is YtmException && e.isAuth) ||
            e.toString().toLowerCase().contains('unauthenticated') ||
            e.toString().toLowerCase().contains('session expired') ||
            e.toString().toLowerCase().contains('not signed in');
        if (isAuth) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(context.l10n.sessionExpired),
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: context.l10n.signIn,
                onPressed: () => YtmWebLoginSheet.show(context),
              ),
            ),
          );
        } else {
          messenger.showSnackBar(
            SnackBar(
              content: Text(context.l10n.syncFailed(e.toString())),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  void _showImportYtmFavoritesDialog(BuildContext context) {
    final p = context.palette;
    final controller = _importYtmController..clear();
    bool isLoading = false;
    String? errorText;

    PulsrSheetHelper.showPulsrSheet(
      context: context,
      wrapWithContainer: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
          return Container(
            padding: EdgeInsetsDirectional.fromSTEB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, bottomInset + 24),
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(AppRadii.r28)),
              border: Border.all(color: p.hairline),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: p.textTertiary.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(AppRadii.r2),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.s18),
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: p.accent.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.cloud_download_rounded,
                          color: p.accent, size: 22),
                    ),
                    const SizedBox(width: AppSpacing.s14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(context.l10n.importYtmFav,
                            style: TextStyle(
                              color: p.textPrimary,
                              fontSize: AppFontSize.bodyLarge,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(context.l10n.pastePlaylistLink,
                            style: TextStyle(
                              color: p.textSecondary,
                              fontSize: AppFontSize.label,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s20),
                TextField(
                  controller: controller,
                  style: TextStyle(color: p.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'https://music.youtube.com/playlist?list=...',
                    hintStyle: TextStyle(color: p.textTertiary, fontSize: AppFontSize.bodySmall),
                    prefixIcon: Icon(Icons.link_rounded,
                        color: p.textTertiary, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(Icons.content_paste_rounded,
                          color: p.accent, size: 18),
                      tooltip: context.l10n.browsePasteFromClipboard,
                      onPressed: () async {
                        final data = await Clipboard.getData('text/plain');
                        if (data?.text != null) {
                          setSheetState(
                              () => controller.text = data!.text!.trim());
                        }
                      },
                    ),
                    filled: true,
                    fillColor: p.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadii.r14),
                      borderSide: BorderSide(color: p.hairline),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadii.r14),
                      borderSide: BorderSide(color: p.hairline),
                    ),
                  ),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    errorText!,
                    style: TextStyle(color: p.error, fontSize: AppFontSize.label),
                  ),
                ],
                const SizedBox(height: AppSpacing.s20),
                FilledButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                          final text = controller.text.trim();
                          if (text.isEmpty) {
                            setSheetState(() => errorText =
                                context.l10n.browseEnterPlaylistUrl);
                            return;
                          }
                          setSheetState(() {
                            isLoading = true;
                            errorText = null;
                          });

                          final libraryCubit = context.read<LibraryCubit>();
                          final authCubit = context.read<AuthCubit>();

                          try {
                            final ytmService = getIt<YtmService>();
                            var tracks =
                                await ytmService.getPlaylistTracks(text);
                            if (tracks.isEmpty &&
                                (text.contains('list=LM') ||
                                    text.contains('list=LL') ||
                                    text == 'LM' ||
                                    text == 'LL')) {
                              final ytmAccount = getIt<YtmAccountService>();
                              if (ytmAccount.isLoggedIn) {
                                tracks = await ytmAccount.fetchLikedSongs();
                              }
                            }

                            if (tracks.isEmpty) {
                              setSheetState(() {
                                isLoading = false;
                                errorText =
                                    context.l10n.browseNoTracksPrivateLiked;
                              });
                              return;
                            }

                            final count = await libraryCubit
                                .importYtmTracksAsFavorites(tracks);
                            if (ctx.mounted && Navigator.of(ctx).canPop()) {
                              Navigator.of(ctx).pop();
                            }
                            if (context.mounted) {
                              if (_favTabFilter != 1) {
                                setState(() => _favTabFilter = 1);
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(context.l10n
                                      .importedOnline(count)),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                              // Trigger cloud sync if authenticated
                              try {
                                authCubit.syncNow();
                              } catch (_) {}
                            }
                          } catch (e) {
                            setSheetState(() {
                              isLoading = false;
                              errorText =
                                  '${context.l10n.playlistLoadFailed} $e';
                            });
                          }
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: p.accent,
                    foregroundColor: p.onAccent,
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.s14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadii.r14)),
                  ),
                  child: isLoading
                      ? SizedBox(width: AppSpacing.s20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: p.onAccent),
                        )
                      : Text(context.l10n.importTracks,
                          style: TextStyle(
                              fontSize: AppFontSize.callout, fontWeight: FontWeight.w600),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFavoriteGridCard(
    BuildContext context,
    SongsTableData song,
    List<SongsTableData> currentFavorites,
    PulsrPalette p,
    PlayerCubit playerCubit,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.r18),
      onTap: () => playerCubit.playSong(song, queue: currentFavorites),
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
                if (AppConfig.ytmEnabled &&
                    song.remoteId != null &&
                    song.remoteId!.isNotEmpty)
                  PositionedDirectional(
                    start: 6,
                    top: 6,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: YtmDownloadButton(
                        song: song,
                        activeColor: Colors.white,
                        iconColor: Colors.white,
                        iconSize: 18,
                      ),
                    ),
                  ),
                PositionedDirectional(
                  end: 6,
                  top: 6,
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () =>
                          context.read<LibraryCubit>().toggleFavorite(song.id),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.s6),
                        child: Icon(Icons.favorite_rounded,
                            color: p.favorite, size: 18),
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
              fontSize: AppFontSize.bodySmall,
            ),
          ),
          const SizedBox(height: AppSpacing.s2),
          Text(
            song.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: p.textSecondary, fontSize: AppFontSize.label),
          ),
        ],
      ),
    );
  }





















  // Requires: provided by the composing class (same library).
  int get _favTabFilter;
  set _favTabFilter(int value);

  // Requires: provided by the composing class (same library).
  Future<void> _handleRefresh(BuildContext context);

  // Requires: provided by the composing class (same library).
  TabController get _tabController;

  // Requires: provided by the composing class (same library).
  TextEditingController get _importYtmController;
}
