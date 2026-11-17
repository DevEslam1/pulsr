part of '../lyrics_player_theme.dart';

extension _LyricsPlayerThemeBuild on LyricsPlayerTheme {
  Widget _buildBody(BuildContext context) {
    final state = props.state;
    final cubit = props.cubit;
    final activeColor = props.activeColor;
    final song = state.currentSong;
    final visualizerStyle = context
        .select<SettingsCubit, VisualizerStyle>((c) => c.state.visualizerStyle);
    final showVisualizer = visualizerStyle != VisualizerStyle.off &&
        !state.isLyricsVisible &&
        !state.isQueueVisible &&
        !PlayerSplitViewScope.of(context);

    final extraBadge = Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s6, vertical: AppSpacing.s2),
      decoration: BoxDecoration(
        color: activeColor.withValues(alpha: 0.18),
        borderRadius: AppRadii.r6All,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mic_rounded, size: 11, color: activeColor),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            context.l10n.lyrics,
            style: TextStyle(
              fontSize: AppFontSize.caption,
              fontWeight: FontWeight.w900,
              letterSpacing: AppTracking.overline,
              color: activeColor,
            ),
          ),
        ],
      ),
    );

    return PlayerThemeScaffold(
      props: props,
      trackIcon: Icons.lyrics_rounded,
      dockIconStyle: PlayerDockIconStyle.lyricsFocus,
      stage: (context, metrics) => PlayerGestureScope(
        onTap: () => cubit.toggleLyricsVisibility(),
        child: Center(
          key: const ValueKey('track_art_lyrics_focus'),
          child: LayoutBuilder(
            builder: (context, artConstraints) {
              final double visualizerH = showVisualizer
                  ? (visualizerStyle == VisualizerStyle.circular ? 60.0 : 34.0)
                  : 0.0;
              final double visualizerSpace =
                  showVisualizer ? visualizerH + 8.0 : 0.0;
              final double availableWidth =
                  artConstraints.maxWidth - (metrics.isTablet ? 64.0 : 36.0);
              final double availableHeight = math.max(
                  0.0,
                  artConstraints.maxHeight -
                      (metrics.isTablet ? 24.0 : 12.0) -
                      visualizerSpace);
              final double maxAllowed = metrics.isLandscape
                  ? 280.0
                  : (metrics.isTablet ? 560.0 : 420.0);
              final double rawArtSize =
                  math.min(availableWidth, availableHeight);
              final double artSize =
                  rawArtSize <= 0 ? 0.0 : math.min(rawArtSize, maxAllowed);

              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: artSize,
                      maxWidth: artSize,
                    ),
                    child: AspectRatio(
                      aspectRatio: 1.0,
                      child: Hero(
                        tag: props.heroTag,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: AppRadii.circular(
                                resolveCustomRadius(context, 20)),
                            boxShadow: [
                              BoxShadow(
                                color: activeColor.withValues(alpha: 0.35),
                                blurRadius: 36,
                                spreadRadius: 2,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: PlayerArtworkSemantics(
                            song: song,
                            child: song != null
                                ? CachedArtwork(
                                    id: song.id,
                                    albumId: song.albumId,
                                    remoteUrl: song.remoteArtworkUrl ??
                                        song.artworkUri,
                                    type: ArtworkType.AUDIO,
                                    size: double.infinity,
                                    borderRadius:
                                        resolveCustomRadius(context, 20),
                                    highQuality: true,
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (showVisualizer)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                            vertical: AppSpacing.xxs),
                        child: AudioVisualizer(
                          style: visualizerStyle,
                          color: activeColor,
                          height: visualizerH,
                          isPlaying: state.isPlaying,
                          audioSessionId: state.audioSessionId,
                          trackSeed: song?.id,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
      chrome: (context, metrics) => PlayerControlsColumn(
        props: props,
        isTablet: metrics.isTablet,
        isLandscape: metrics.isLandscape,
        isInSplitView: PlayerSplitViewScope.of(context),
        heightRatio: metrics.heightRatio,
        metrics: metrics,
        trackHeader: PlayerTrackHeader(
          props: props,
          isTablet: metrics.isTablet,
          metrics: metrics,
          extraBadge: extraBadge,
        ),
        scaleMainButtonByHeight: true,
        dock: PlayerBottomActionDock(
          props: props,
          isTablet: metrics.isTablet,
          barWidth: metrics.pillBarWidth,
          barHeight: metrics.dockBarHeight,
          dockIconStyle: PlayerDockIconStyle.lyricsFocus,
        ),
      ),
    );
  }
}
