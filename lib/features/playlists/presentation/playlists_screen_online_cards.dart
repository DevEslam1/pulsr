part of 'playlists_screen.dart';

class _AccountPlaylistCard extends StatelessWidget {
  final YtmAccountPlaylist playlist;
  final VoidCallback onTap;
  final VoidCallback? onDownload;

  const _AccountPlaylistCard({
    required this.playlist,
    required this.onTap,
    this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    const gradientColors = [AppColors.netflixRed, AppColors.ytRedDeep];
    final onScrim = AppColors.textOnAccent(AppColors.scrim);

    return Semantics(
      button: true,
      label: '${playlist.title}, ${playlist.subtitle}',
      customSemanticsActions: {
        if (onDownload != null)
          CustomSemanticsAction(label: context.l10n.downloadAction):
              onDownload!,
      },
      child: InkWell(
        onTap: () {
          PulsrHaptics.selectionClick();
          onTap();
        },
        borderRadius: AppRadii.r20All,
        child: Container(
          decoration: BoxDecoration(
            color: p.surfaceContainer,
            borderRadius: AppRadii.r20All,
            border: Border.all(color: p.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ExcludeSemantics(
                      child: Hero(
                        tag: 'online_playlist_${playlist.playlistId}',
                        child: playlist.artworkUrl != null
                            ? Image.network(
                                playlist.artworkUrl!,
                                fit: BoxFit.cover,
                                cacheWidth: 360,
                                cacheHeight: 360,
                                loadingBuilder: (context, child, progress) =>
                                    progress == null
                                        ? child
                                        : _buildFallbackCover(gradientColors),
                                errorBuilder: (_, __, ___) =>
                                    _buildFallbackCover(gradientColors),
                              )
                            : _buildFallbackCover(gradientColors),
                      ),
                    ),
                    if (onDownload != null)
                      PositionedDirectional(
                        top: 0,
                        end: 0,
                        child: Semantics(
                          button: true,
                          label: context.l10n.downloadAction,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: onDownload,
                            child: SizedBox(
                              width: AppSpacing.minTouchTarget,
                              height: AppSpacing.minTouchTarget,
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.all(AppSpacing.s6),
                                  decoration: BoxDecoration(
                                    color: AppColors.scrimAt(0.60),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.download_rounded,
                                    color: onScrim,
                                    size: 16,
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
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.s14,
                  AppSpacing.s10,
                  AppSpacing.s14,
                  AppSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playlist.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: AppFontSize.bodySmall,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    Text(
                      playlist.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
        ),
      ),
    );
  }

  Widget _buildFallbackCover(List<Color> colors) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.queue_music_rounded,
          color: AppColors.textOnAccent(AppColors.ytRedDeep),
          size: 36,
        ),
      ),
    );
  }
}

class _LikedMusicOnlineCard extends StatelessWidget {
  final YtmFetchStatus status;
  final int trackCount;
  final String? error;
  final VoidCallback onFetch;
  final VoidCallback onPlay;
  final VoidCallback? onDownload;

  const _LikedMusicOnlineCard({
    required this.status,
    required this.trackCount,
    required this.error,
    required this.onFetch,
    required this.onPlay,
    this.onDownload,
  });

  Widget _circleAction({
    required String label,
    required IconData icon,
    required Color onBrand,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: AppSpacing.minTouchTarget,
            minHeight: AppSpacing.minTouchTarget,
          ),
          child: Center(
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.specularAt(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: onBrand, size: 22),
            ),
          ),
        ),
      ),
    );
  }

  Widget _solidBadge(IconData icon, Color bg, Color fg, {double size = 26}) {
    return ExcludeSemantics(
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Icon(icon, color: fg, size: size),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const gradientColors = [AppColors.spotifyGreen, AppColors.spotifyGreenDeep];
    final onBrand = AppColors.textOnAccent(AppColors.spotifyGreenDeep);
    final hasCachedTracks = trackCount > 0;
    final isAuthError = error != null &&
        (error!.toLowerCase().contains('sign in') ||
            error!.toLowerCase().contains('expired'));
    final retryAction =
        isAuthError ? () => YtmWebLoginSheet.show(context) : onFetch;

    String subtitle;
    switch (status) {
      case YtmFetchStatus.idle:
        subtitle = context.l10n.browseTapToSyncYtm;
        break;
      case YtmFetchStatus.loading:
        subtitle = context.l10n.browseSyncingLikedSongs;
        break;
      case YtmFetchStatus.done:
        subtitle =
            '${context.l10n.songsCount(trackCount)} ${context.l10n.browseSynced} • ${context.l10n.browseTapToPlayOrDownload}';
        break;
      case YtmFetchStatus.error:
        final errCopy = error ?? context.l10n.browseFailedToFetch;
        subtitle = hasCachedTracks
            ? '${context.l10n.songsCount(trackCount)} • $errCopy'
            : errCopy;
        break;
    }

    final canOpenCached = status == YtmFetchStatus.done ||
        (status == YtmFetchStatus.error && hasCachedTracks);

    return Semantics(
      button: true,
      label: '${context.l10n.likedMusic}, $subtitle',
      customSemanticsActions: {
        if (status == YtmFetchStatus.done && onDownload != null)
          CustomSemanticsAction(label: context.l10n.downloadAction):
              onDownload!,
        if (status == YtmFetchStatus.error && hasCachedTracks)
          CustomSemanticsAction(label: context.l10n.retry): retryAction,
      },
      child: InkWell(
        onTap: status == YtmFetchStatus.loading
            ? null
            : (canOpenCached ? onPlay : retryAction),
        borderRadius: AppRadii.r22All,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.s20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: gradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: AppRadii.r22All,
            boxShadow: [
              BoxShadow(
                color: gradientColors.first.withValues(alpha: 0.35),
                blurRadius: 28,
                spreadRadius: -6,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Row(
            children: [
              ExcludeSemantics(
                child: Hero(
                  tag: 'online_playlist_VLLM',
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.specularAt(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.thumb_up_alt_rounded,
                      color: onBrand,
                      size: 26,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.likedMusic,
                      style: TextStyle(
                        color: onBrand,
                        fontWeight: FontWeight.w900,
                        fontSize: AppFontSize.title,
                        letterSpacing: AppTracking.title,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: AppColors.specularAt(
                          status == YtmFetchStatus.error ? 0.7 : 0.85,
                        ),
                        fontSize: AppFontSize.label,
                      ),
                    ),
                  ],
                ),
              ),
              if (status == YtmFetchStatus.loading)
                const SkeletonBox(
                  width: AppSpacing.s40,
                  height: AppSpacing.s40,
                  radius: AppRadii.r20,
                )
              else if (status == YtmFetchStatus.done)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onDownload != null) ...[
                      _circleAction(
                        label: context.l10n.downloadAction,
                        icon: Icons.download_rounded,
                        onBrand: onBrand,
                        onTap: onDownload!,
                      ),
                      const SizedBox(width: AppSpacing.s10),
                    ],
                    _solidBadge(
                      Icons.play_arrow_rounded,
                      onBrand,
                      gradientColors.first,
                    ),
                  ],
                )
              else if (status == YtmFetchStatus.error && hasCachedTracks)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _circleAction(
                      label: context.l10n.retry,
                      icon: Icons.refresh_rounded,
                      onBrand: onBrand,
                      onTap: retryAction,
                    ),
                    const SizedBox(width: AppSpacing.s10),
                    _solidBadge(
                      Icons.play_arrow_rounded,
                      onBrand,
                      gradientColors.first,
                    ),
                  ],
                )
              else
                _solidBadge(
                  status == YtmFetchStatus.error
                      ? Icons.refresh_rounded
                      : Icons.download_rounded,
                  onBrand,
                  gradientColors.first,
                  size: 22,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnlinePlaylistCard extends StatelessWidget {
  final OnlinePlaylistEntry entry;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final VoidCallback? onDownload;

  const _OnlinePlaylistCard({
    required this.entry,
    required this.onTap,
    required this.onRemove,
    this.onDownload,
  });

  Widget _overlayButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final onScrim = AppColors.textOnAccent(AppColors.scrim);
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: AppSpacing.minTouchTarget,
          height: AppSpacing.minTouchTarget,
          child: Center(
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.scrimAt(0.55),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: onScrim, size: 16),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final previewArt =
        entry.tracks.isNotEmpty ? entry.tracks.first.artworkUrl : null;

    return Semantics(
      button: true,
      label: entry.title,
      customSemanticsActions: {
        if (onDownload != null)
          CustomSemanticsAction(label: context.l10n.downloadAction):
              onDownload!,
        CustomSemanticsAction(label: context.l10n.remove): onRemove,
      },
      child: InkWell(
        onTap: () {
          PulsrHaptics.selectionClick();
          onTap();
        },
        onLongPress: onRemove,
        borderRadius: AppRadii.r20All,
        child: Container(
          decoration: BoxDecoration(
            color: p.surfaceContainer,
            borderRadius: AppRadii.r20All,
            border: Border.all(color: p.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ExcludeSemantics(
                      child: Hero(
                        tag: 'online_playlist_${entry.id}',
                        child: previewArt != null && previewArt.isNotEmpty
                            ? Image.network(
                                previewArt,
                                fit: BoxFit.cover,
                                cacheWidth: 360,
                                cacheHeight: 360,
                                errorBuilder: (_, __, ___) =>
                                    _buildGradientCover(),
                              )
                            : _buildGradientCover(),
                      ),
                    ),
                    if (onDownload != null)
                      PositionedDirectional(
                        top: 0,
                        start: 0,
                        child: _overlayButton(
                          label: context.l10n.downloadAction,
                          icon: Icons.download_rounded,
                          onTap: onDownload!,
                        ),
                      ),
                    PositionedDirectional(
                      top: 0,
                      end: 0,
                      child: _overlayButton(
                        label: context.l10n.remove,
                        icon: Icons.close_rounded,
                        onTap: onRemove,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.s14,
                  AppSpacing.s10,
                  AppSpacing.s14,
                  AppSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: AppFontSize.bodySmall,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    Text(
                      context.l10n.entryAdded(entry.tracks.length),
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
        ),
      ),
    );
  }

  Widget _buildGradientCover() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.ytRed.withValues(alpha: 0.85),
            AppColors.ytRedDeep,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.queue_music_rounded,
          color: AppColors.textOnAccent(AppColors.ytRedDeep),
          size: 40,
        ),
      ),
    );
  }
}
