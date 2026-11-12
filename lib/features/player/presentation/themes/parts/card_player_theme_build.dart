part of '../card_player_theme.dart';

extension _CardPlayerThemeBuild on CardPlayerTheme {
  Widget _buildBody(BuildContext context) {
    final p = context.palette;
    final state = props.state;
    final cubit = props.cubit;
    final activeColor = props.activeColor;
    final song = state.currentSong;
    final (
      :visualizerStyle,
      :waveformSeekBarEnabled,
      :playerSliderStyle,
    ) = context.select<
        SettingsCubit,
        ({
          VisualizerStyle visualizerStyle,
          bool waveformSeekBarEnabled,
          PlayerSliderStyle playerSliderStyle,
        })>((c) => (
          visualizerStyle: c.state.visualizerStyle,
          waveformSeekBarEnabled: c.state.waveformSeekBarEnabled,
          playerSliderStyle: c.state.playerSliderStyle,
        ));

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textTitleColor = isDark ? Colors.white : p.textPrimary;
    final textSubtitleColor = isDark ? Colors.white70 : p.textSecondary;

    final isWaveformActive = waveformSeekBarEnabled &&
        playerSliderStyle == PlayerSliderStyle.normal;
    final showVisualizer = visualizerStyle != VisualizerStyle.off &&
        !isWaveformActive &&
        !state.isLyricsVisible &&
        !state.isQueueVisible &&
        !PlayerSplitViewScope.of(context);

    final visualizer = showVisualizer
        ? Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg, vertical: AppSpacing.s2),
            child: AudioVisualizer(
              style: visualizerStyle,
              color: activeColor,
              height: visualizerStyle == VisualizerStyle.circular ? 64 : 40,
              isPlaying: state.isPlaying,
              audioSessionId: state.audioSessionId,
              trackSeed: song?.id,
            ),
          )
        : const SizedBox.shrink();

    return PlayerThemeScaffold(
      props: props,
      trackIcon: Icons.layers_rounded,
      background: RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            song != null
                ? CanvasBackdrop(
                    song: song,
                    isPlaying: state.isPlaying,
                    isBackdropMode: true,
                    fallbackArtwork: CachedArtwork(
                      id: song.id,
                      albumId: song.albumId,
                      remoteUrl: song.remoteArtworkUrl ?? song.artworkUri,
                      type: ArtworkType.AUDIO,
                      size: double.infinity,
                      highQuality: true,
                    ),
                  )
                : Container(color: p.bg),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [
                          AppColors.scrimLight,
                          AppColors.scrimAt(0.72),
                          AppColors.scrimAt(0.94),
                        ]
                      : [
                          AppColors.specularAt(0.35),
                          AppColors.specularAt(0.65),
                          AppColors.specularAt(0.92),
                        ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            PositionedDirectional(
              bottom: -40,
              start: -20,
              end: -20,
              height: context.isTablet ? 440 : 340,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.center,
                      radius: 0.85,
                      colors: [
                        activeColor.withValues(alpha: isDark ? 0.24 : 0.14),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      stage: (context, metrics) => PlayerGestureScope(
        onTap: () => cubit.toggleLyricsVisibility(),
        child: LayoutBuilder(
          builder: (context, artConstraints) {
            final double cardArtSize = PlayerThemeMetrics.safeArtworkSize(
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
                  key: const ValueKey('artwork_card'),
                  child: SizedBox(
                    width: cardArtSize,
                    height: cardArtSize,
                    child: AnimatedScale(
                      scale: state.isPlaying ? 1.0 : 0.97,
                      duration: context.motionMs(320),
                      curve: context.motionCurve(Curves.easeOutCubic),
                      child: AspectRatio(
                        aspectRatio: 1.0,
                        child: Hero(
                          tag: props.heroTag,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: AppRadii.circular(
                                  resolveCustomRadius(context, AppRadii.r28)),
                              border: Border.all(
                                color: Colors.white
                                    .withValues(alpha: isDark ? 0.20 : 0.45),
                                width: 1.4,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      AppColors.scrimAt(isDark ? 0.62 : 0.22),
                                  blurRadius: 32,
                                  spreadRadius: 4,
                                  offset: const Offset(0, 14),
                                ),
                                BoxShadow(
                                  color: activeColor.withValues(
                                      alpha: state.isPlaying ? 0.36 : 0.20),
                                  blurRadius: 28,
                                  spreadRadius: -2,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: song != null
                                ? CachedArtwork(
                                    id: song.id,
                                    albumId: song.albumId,
                                    remoteUrl: song.remoteArtworkUrl ??
                                        song.artworkUri,
                                    type: ArtworkType.AUDIO,
                                    size: double.infinity,
                                    borderRadius: 28,
                                    highQuality: true,
                                  )
                                : Container(
                                    decoration: BoxDecoration(
                                      color: p.surfaceContainer,
                                      borderRadius: AppRadii.r28All,
                                    ),
                                    child: Icon(
                                      Icons.music_note_rounded,
                                      size: 96,
                                      color: textSubtitleColor.withValues(
                                          alpha: 0.4),
                                    ),
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
      chrome: (context, metrics) => Container(
        decoration: BoxDecoration(
          borderRadius: AppRadii.circular(
              resolveCustomRadius(context, AppRadii.r28)),
          color: p.playerCard,
          border: Border.all(
            color: p.hairline,
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.s10),
        child: PlayerControlsColumn(
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
            horizontalPadding: 0,
            tabletHorizontalPadding: 0,
            verticalPadding: 0,
            titleColor: textTitleColor,
            subtitleColor: textSubtitleColor,
            titleArtistGap: AppSpacing.s2,
          ),
          scaleMainButtonByHeight: true,
          dense: true,
          dock: PlayerBottomActionDock(
            props: props,
            isTablet: metrics.isTablet,
            barWidth: metrics.pillBarWidth,
            barHeight: metrics.dockBarHeight,
            disableBlur: true,
          ),
        ),
      ),
    );
  }
}
