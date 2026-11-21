// lib/features/library/presentation/tabs/library_favorites_tab.dart
part of '../library_screen.dart';

mixin LibraryFavoritesTab on State<LibraryScreen> {
  // ================= FAVORITES =================
  Widget _buildFavoritesTab(
    BuildContext context,
    LibraryState state,
    PlayerCubit playerCubit,
  ) {
    final p = context.palette;
    final cubit = context.read<LibraryCubit>();
    final allFavorites = state.favorites;
    final localFavorites =
        allFavorites.where((s) => !_isOnlineFavorite(s)).toList();
    final onlineFavorites =
        allFavorites.where((s) => _isOnlineFavorite(s)).toList();

    final scope = _favTabFilter == 0 ? SourceScope.local : SourceScope.online;
    final filteredFavorites =
        scope == SourceScope.local ? localFavorites : onlineFavorites;
    final currentFavorites = LibraryTabSort.sortSongs(
      filteredFavorites,
      _tabSortFor('favorites'),
    );
    final isGrid = state.viewMode == LibraryViewMode.grid;

    return RefreshIndicator(
      color: p.accent,
      backgroundColor: p.surfaceContainer,
      onRefresh: () => scope == SourceScope.online && AppConfig.ytmEnabled
          ? _syncYtmLikes(context)
          : _handleRefresh(context),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: buildFavoritesSlivers(
          context: context,
          songs: currentFavorites,
          localCount: localFavorites.length,
          onlineCount: onlineFavorites.length,
          scope: scope,
          onScopeChanged: (next) => setState(
            () => _favTabFilter = next == SourceScope.online ? 1 : 0,
          ),
          isLoading: state.isLoading,
          isGrid: isGrid,
          isMultiSelectMode: state.isMultiSelectMode,
          selectedSongIds: state.selectedSongIds,
          playerCubit: playerCubit,
          libraryCubit: cubit,
          dismissKeyPrefix: 'fav',
          hasAnyInScope: currentFavorites.isNotEmpty,
          onViewAll: () => context.push('/favorites'),
          onDownloadAll: () => _downloadFavorites(context, currentFavorites),
          onSyncOnline: () => _syncYtmLikes(context),
          onImportOnlineLink: () => _showImportYtmFavoritesDialog(context),
        ),
      ),
    );
  }

  bool _isOnlineFavorite(SongsTableData s) => isOnlineFavorite(s);

  Future<void> _downloadFavorites(
    BuildContext context,
    List<SongsTableData> songs,
  ) async {
    if (songs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.noFavToDownload)),
      );
      return;
    }

    final downloadCubit = context.read<YtmDownloadCubit?>() ??
        (getIt.isRegistered<YtmDownloadCubit>()
            ? getIt<YtmDownloadCubit>()
            : null);
    if (downloadCubit == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.downloadErrorDisabled)),
      );
      return;
    }
    final report = await downloadCubit.downloadAllDetailed(songs);
    if (!context.mounted) return;
    final queuedCount = report.queued;
    final extras = describeBatchOutcomeExtras(
      context.l10n,
      capped: report.capped,
      failed: report.failed,
      firstError: report.firstError,
      skippedLocal: report.skippedLocal,
    );

    if (queuedCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('${context.l10n.queuedForDownload(queuedCount)}$extras'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      final hasOnlineTracks =
          songs.any((s) => s.remoteId != null && s.remoteId!.isNotEmpty);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${hasOnlineTracks ? context.l10n.browseAllOnlineLikedDownloaded : context.l10n.browseAllSongsOffline}$extras',
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
            const SkeletonShimmer(
              child: SkeletonBox(
                width: AppSpacing.md,
                height: 16,
                radius: 8,
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
            padding: EdgeInsetsDirectional.fromSTEB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              bottomInset + 24,
            ),
            decoration: BoxDecoration(
              color: p.surfaceContainer,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadii.r28),
              ),
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
                      borderRadius: AppRadii.r2All,
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
                      child: Icon(
                        Icons.cloud_download_rounded,
                        color: p.accent,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.importYtmFav,
                            style: TextStyle(
                              color: p.textPrimary,
                              fontSize: AppFontSize.bodyLarge,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            context.l10n.pastePlaylistLink,
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
                    hintStyle: TextStyle(
                      color: p.textTertiary,
                      fontSize: AppFontSize.bodySmall,
                    ),
                    prefixIcon: Icon(
                      Icons.link_rounded,
                      color: p.textTertiary,
                      size: 20,
                    ),
                    suffixIcon: IconButton(
                      constraints: const BoxConstraints(
                        minWidth: AppSpacing.minTouchTarget,
                        minHeight: AppSpacing.minTouchTarget,
                      ),
                      icon: Icon(
                        Icons.content_paste_rounded,
                        color: p.accent,
                        size: 18,
                      ),
                      tooltip: context.l10n.browsePasteFromClipboard,
                      onPressed: () async {
                        final data = await Clipboard.getData('text/plain');
                        if (!ctx.mounted) return;
                        if (data?.text != null) {
                          setSheetState(
                            () => controller.text = data!.text!.trim(),
                          );
                        }
                      },
                    ),
                    filled: true,
                    fillColor: p.surface,
                    border: OutlineInputBorder(
                      borderRadius: AppRadii.r14All,
                      borderSide: BorderSide(color: p.hairline),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: AppRadii.r14All,
                      borderSide: BorderSide(color: p.hairline),
                    ),
                  ),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    errorText!,
                    style: TextStyle(
                      color: p.error,
                      fontSize: AppFontSize.label,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.s20),
                FilledButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                          final text = controller.text.trim();
                          if (text.isEmpty) {
                            setSheetState(
                              () => errorText =
                                  context.l10n.browseEnterPlaylistUrl,
                            );
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
                            if (!ctx.mounted) return;
                            if (tracks.isEmpty &&
                                (text.contains('list=LM') ||
                                    text.contains('list=LL') ||
                                    text == 'LM' ||
                                    text == 'LL')) {
                              final ytmAccount = getIt<YtmAccountService>();
                              if (ytmAccount.isLoggedIn) {
                                tracks = await ytmAccount.fetchLikedSongs();
                                if (!ctx.mounted) return;
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
                            if (!ctx.mounted) return;
                            // A repository failure is reported as -1; keep the
                            // sheet open with an inline error instead of
                            // popping and claiming "Imported -1".
                            if (count < 0) {
                              setSheetState(() {
                                isLoading = false;
                                errorText = context.l10n.importFailed;
                              });
                              return;
                            }
                            if (Navigator.of(ctx).canPop()) {
                              Navigator.of(ctx).pop();
                            }
                            if (context.mounted) {
                              if (_favTabFilter != 1) {
                                setState(() => _favTabFilter = 1);
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content:
                                      Text(context.l10n.importedOnline(count)),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                              // Trigger cloud sync if authenticated
                              try {
                                authCubit.syncNow();
                              } catch (_) {}
                            }
                          } catch (e) {
                            if (!ctx.mounted) return;
                            setSheetState(() {
                              isLoading = false;
                              errorText =
                                  '${context.l10n.playlistLoadFailed}$e';
                            });
                          }
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: p.accent,
                    foregroundColor: p.onAccent,
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.s14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadii.r14All,
                    ),
                  ),
                  child: isLoading
                      ? const SkeletonShimmer(
                          child: SkeletonLine(
                            width: 96,
                            height: 14,
                            radius: 7,
                          ),
                        )
                      : Text(
                          context.l10n.importTracks,
                          style: const TextStyle(
                            fontSize: AppFontSize.callout,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Requires: provided by the composing class (same library).
  int get _favTabFilter;
  set _favTabFilter(int value);

  // Requires: provided by the composing class (same library).
  Future<void> _handleRefresh(BuildContext context);

  // Requires: provided by the composing class (same library).
  TextEditingController get _importYtmController;

  // Requires: provided by the composing class (same library).
  LibraryTabSortSpec _tabSortFor(String tabName);
}