// Hero card widgets for OnlinePlaylistDetailScreen, split into a part file to
// keep online_playlist_detail_screen.dart within the file-size ratchet.
part of 'online_playlist_detail_screen.dart';

extension _OnlinePlaylistDetailHero on _OnlinePlaylistDetailScreenState {
  Widget _buildHeroCard(
    BuildContext context,
    PulsrPalette p,
    int totalDurationMs,
  ) {
    const ytGradient = [AppColors.netflixRed, AppColors.ytRedDeep];

    return Container(
      decoration: BoxDecoration(
        color: p.surfaceContainer,
        borderRadius: AppRadii.r24All,
        border: Border.all(color: p.hairline),
        boxShadow: [
          BoxShadow(
            color: AppColors.scrimAt(p.isDark ? 0.25 : 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 164,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ExcludeSemantics(
                  child: _artworkUrl != null && _artworkUrl!.isNotEmpty
                      ? Image.network(
                          _artworkUrl!,
                          fit: BoxFit.cover,
                          cacheWidth: 600,
                          cacheHeight: 360,
                          loadingBuilder: (context, child, progress) =>
                              progress == null
                                  ? child
                                  : _buildFallbackHeroGradient(ytGradient),
                          errorBuilder: (_, __, ___) =>
                              _buildFallbackHeroGradient(ytGradient),
                        )
                      : _buildFallbackHeroGradient(ytGradient),
                ),
                ExcludeSemantics(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.scrimAt(0.15),
                          p.surfaceContainer.withValues(alpha: 0.92),
                          p.surfaceContainer,
                        ],
                        stops: const [0.0, 0.78, 1.0],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ),
                PositionedDirectional(
                  top: AppSpacing.sm,
                  start: AppSpacing.sm,
                  child: MergeSemantics(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.ytRed,
                        borderRadius: AppRadii.r8All,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.scrimAt(0.38),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ExcludeSemantics(
                            child: Icon(
                              Icons.play_circle_fill_rounded,
                              color: AppColors.textOnAccent(AppColors.ytRed),
                              size: 14,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xxs),
                          Text(
                            context.l10n.ytmHeader,
                            style: TextStyle(
                              color: AppColors.textOnAccent(AppColors.ytRed),
                              fontSize: AppFontSize.caption,
                              fontWeight: FontWeight.w900,
                              letterSpacing: AppTracking.medium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                PositionedDirectional(
                  bottom: 0,
                  start: AppSpacing.s18,
                  end: AppSpacing.s18,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Semantics(
                              header: true,
                              child: Text(
                                _title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: AppFontSize.titleLarge,
                                  fontWeight: FontWeight.w900,
                                  color: p.textPrimary,
                                  letterSpacing: AppTracking.heading,
                                  height: 1.15,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: AppFontSize.bodySmall,
                                color: p.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        constraints: const BoxConstraints(
                          minWidth: AppSpacing.minTouchTarget,
                          minHeight: AppSpacing.minTouchTarget,
                        ),
                        icon: Icon(
                          Icons.edit_rounded,
                          size: 18,
                          color: p.textSecondary,
                        ),
                        tooltip: context.l10n.browseRenamePlaylist,
                        onPressed: _showRenameDialog,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.s18,
              AppSpacing.xs,
              AppSpacing.s18,
              AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MergeSemantics(
                  child: Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xxs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _buildHeroBadge(
                        p,
                        icon: Icons.music_note_rounded,
                        label: context.l10n.previewTrackCount(_tracks.length),
                      ),
                      if (totalDurationMs > 0)
                        _buildHeroBadge(
                          p,
                          icon: Icons.schedule_rounded,
                          label: Formatters.formatDurationMs(totalDurationMs),
                        ),
                      if (_hasCustomOrder)
                        _buildHeroBadge(
                          p,
                          icon: Icons.reorder_rounded,
                          label: context.l10n.customOrder,
                          highlight: true,
                        ),
                      if (_isOfflineCache)
                        _buildHeroBadge(
                          p,
                          icon: Icons.cloud_off_rounded,
                          label: context.l10n.cachedCopy,
                        ),
                    ],
                  ),
                ),
                if (_tracks.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _playAll(shuffle: false),
                          icon: const Icon(Icons.play_arrow_rounded, size: 20),
                          label: Text(
                            context.l10n.playAll,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: p.accent,
                            foregroundColor: p.onAccent,
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.s12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: AppRadii.r14All,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: () => _playAll(shuffle: true),
                          icon: const Icon(Icons.shuffle_rounded, size: 18),
                          label: Text(
                            context.l10n.shuffle,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: p.surfaceContainerHigh,
                            foregroundColor: p.textPrimary,
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.s12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: AppRadii.r14All,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      IconButton.filledTonal(
                        constraints: const BoxConstraints(
                          minWidth: AppSpacing.minTouchTarget,
                          minHeight: AppSpacing.minTouchTarget,
                        ),
                        onPressed: _enterReorderMode,
                        icon: const Icon(Icons.swap_vert_rounded, size: 20),
                        tooltip: context.l10n.reorderSongs,
                        style: IconButton.styleFrom(
                          backgroundColor: p.surfaceContainerHigh,
                          foregroundColor: p.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isDownloading ? null : _downloadAll,
                          icon: _isDownloading
                              ? PulsrProgressBar.circular(
                                  size: 14,
                                  strokeWidth: 2,
                                  color: p.accent,
                                )
                              : const Icon(Icons.download_rounded, size: 16),
                          label: Text(
                            context.l10n.downloadAll,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: AppFontSize.label,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: p.hairline),
                            foregroundColor: p.textPrimary,
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.s10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: AppRadii.r12All,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isSaving ? null : _saveToLocalPlaylists,
                          icon: _isSaving
                              ? PulsrProgressBar.circular(
                                  size: 14,
                                  strokeWidth: 2,
                                  color: p.accent,
                                )
                              : const Icon(
                                  Icons.playlist_add_rounded,
                                  size: 18,
                                ),
                          label: Text(
                            context.l10n.saveToPulsr,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: AppFontSize.label,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: p.hairline),
                            foregroundColor: p.textPrimary,
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.s10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: AppRadii.r12All,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroBadge(
    PulsrPalette p, {
    required IconData icon,
    required String label,
    bool highlight = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: highlight ? p.accentSoft : p.surfaceContainerHigh,
        borderRadius: AppRadii.r8All,
        border: Border.all(
          color: highlight ? p.accent.withValues(alpha: 0.35) : p.hairline,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: Icon(
              icon,
              size: 13,
              color: highlight ? p.accent : p.textSecondary,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: AppFontSize.caption,
              fontWeight: FontWeight.w700,
              color: highlight ? p.accent : p.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFallbackHeroGradient(List<Color> gradient) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.queue_music_rounded,
          color: AppColors.textOnAccent(AppColors.ytRedDeep),
          size: 54,
        ),
      ),
    );
  }
}
