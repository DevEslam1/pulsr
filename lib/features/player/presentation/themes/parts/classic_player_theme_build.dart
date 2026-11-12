part of '../classic_player_theme.dart';

extension _ClassicPlayerThemeBuild on ClassicPlayerTheme {
  Widget _buildBody(BuildContext context) {
    final state = props.state;
    final cubit = props.cubit;
    final activeColor = props.activeColor;
    final song = state.currentSong;

    final (
      :visualizerStyle,
      :waveformSeekBarEnabled,
      :playerSliderStyle,
      :canvasEnabled,
      :canvasAsBackdrop
    ) = context.select<
        SettingsCubit,
        ({
          VisualizerStyle visualizerStyle,
          bool waveformSeekBarEnabled,
          PlayerSliderStyle playerSliderStyle,
          bool canvasEnabled,
          bool canvasAsBackdrop,
        })>((c) => (
          visualizerStyle: c.state.visualizerStyle,
          waveformSeekBarEnabled: c.state.waveformSeekBarEnabled,
          playerSliderStyle: c.state.playerSliderStyle,
          canvasEnabled: c.state.canvasEnabled,
          canvasAsBackdrop: c.state.canvasAsBackdrop,
        ));

    final artRadius = resolveCustomRadius(context, AppRadii.r28);

    final isWaveformActive = waveformSeekBarEnabled &&
        playerSliderStyle == PlayerSliderStyle.normal;
    final showVisualizer = visualizerStyle != VisualizerStyle.off &&
        !isWaveformActive &&
        !state.isLyricsVisible &&
        !state.isQueueVisible &&
        !PlayerSplitViewScope.of(context);

    final visualizer = showVisualizer
        ? Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg, vertical: AppSpacing.xxs),
                child: AudioVisualizer(
                  style: visualizerStyle,
                  color: activeColor,
                  height: visualizerStyle == VisualizerStyle.circular
                      ? 65
                      : 36,
                  isPlaying: state.isPlaying,
                  audioSessionId: state.audioSessionId,
                  trackSeed: song?.id,
                ),
              ),
            ),
          )
        : const SizedBox.shrink();

    return PlayerThemeScaffold(
      props: props,
      trackIcon: Icons.music_note_rounded,
      dockIconStyle: PlayerDockIconStyle.classic,
      stage: (context, metrics) => PlayerGestureScope(
        onTap: () => cubit.toggleLyricsVisibility(),
        child: LayoutBuilder(
          builder: (context, artConstraints) {
            final double dynamicArtSize = PlayerThemeMetrics.safeArtworkSize(
              availableWidth: artConstraints.maxWidth,
              availableHeight: artConstraints.maxHeight,
              isTablet: metrics.isTablet,
              maxAllowedOverride: metrics.isLandscape ? 280.0 : null,
            );
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  key: const ValueKey('artwork_view'),
                  child: SizedBox(
                    width: dynamicArtSize,
                    height: dynamicArtSize,
                    child: AnimatedScale(
                      scale: state.isPlaying ? 1.0 : 0.97,
                      duration: context.motionMs(320),
                      curve: context.motionCurve(Curves.easeOutCubic),
                      child: AspectRatio(
                        aspectRatio: 1.0,
                        child: Hero(
                          tag: props.heroTag,
                          child: AnimatedContainer(
                            duration: context.motionMs(320),
                            curve: context.motionCurve(Curves.easeOutCubic),
                            decoration: BoxDecoration(
                              borderRadius: AppRadii.circular(artRadius),
                              border: Border.all(
                                color: Colors.white.withValues(
                                  alpha: state.isPlaying ? 0.22 : 0.14,
                                ),
                                width: 1.4,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: activeColor.withValues(
                                    alpha: state.isPlaying ? 0.44 : 0.20,
                                  ),
                                  blurRadius: state.isPlaying ? 46 : 28,
                                  spreadRadius: state.isPlaying ? 3 : 0,
                                  offset: const Offset(0, 16),
                                ),
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.42),
                                  blurRadius: 22,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: AppRadii.circular(artRadius),
                              child: song != null
                                  ? (!canvasAsBackdrop
                                      ? CanvasBackdrop(
                                          song: song,
                                          isPlaying: state.isPlaying,
                                          isBackdropMode: false,
                                          borderRadius:
                                              AppRadii.circular(artRadius),
                                          fallbackArtwork: CachedArtwork(
                                            id: song.id,
                                            albumId: song.albumId,
                                            remoteUrl: song.remoteArtworkUrl ??
                                                song.artworkUri,
                                            type: ArtworkType.AUDIO,
                                            size: double.infinity,
                                            borderRadius: 26.8,
                                            highQuality: true,
                                          ),
                                        )
                                      : CachedArtwork(
                                          id: song.id,
                                          albumId: song.albumId,
                                          remoteUrl: song.remoteArtworkUrl ??
                                              song.artworkUri,
                                          type: ArtworkType.AUDIO,
                                          size: double.infinity,
                                          borderRadius: 26.8,
                                          highQuality: true,
                                        ))
                                  : const SizedBox.shrink(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (showVisualizer) visualizer,
              ],
            );
          },
        ),
      ),
      chrome: (context, metrics) => PlayerControlsColumn(
        props: props,
        isTablet: metrics.isTablet,
        isLandscape: metrics.isLandscape,
        isInSplitView: PlayerSplitViewScope.of(context),
        heightRatio: metrics.isLandscape ? 0.85 : metrics.heightRatio,
        metrics: metrics,
        trackHeader: PlayerTrackHeader(
          props: props,
          isTablet: metrics.isTablet,
          metrics: metrics,
          badgeGap: metrics.isLandscape ? AppSpacing.xxs : AppSpacing.s8,
          titleArtistGap: metrics.isLandscape ? 2.0 : AppSpacing.xs,
          verticalPadding:
              metrics.isLandscape ? 0.0 : metrics.trackHeaderVerticalPadding,
        ),
        classicSizing: true,
        scaleMainButtonByHeight: true,
        abLoopActive: state.abLoopEnabled,
        dock: PlayerBottomActionDock(
          props: props,
          isTablet: metrics.isTablet,
          barWidth: metrics.pillBarWidth,
          barHeight: metrics.dockBarHeight,
          dockIconStyle: PlayerDockIconStyle.classic,
        ),
      ),
    );
  }
}
