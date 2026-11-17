part of '../classic_player_theme.dart';

extension _ClassicPlayerThemeBuild on ClassicPlayerTheme {
  Widget _buildBody(BuildContext context) {
    final state = props.state;
    final activeColor = props.activeColor;
    final song = state.currentSong;
    final p = context.palette;

    // Select only what this theme paints. `waveformSeekBarEnabled` and
    // `playerSliderStyle` used to be destructured here but never read — the
    // shared seek bar subscribes to them itself — so they rebuilt the whole
    // theme for settings Classic cannot show.
    final (:visualizerStyle, :canvasAsBackdrop) = context.select<
        SettingsCubit,
        ({VisualizerStyle visualizerStyle, bool canvasAsBackdrop})>((c) => (
              visualizerStyle: c.state.visualizerStyle,
              canvasAsBackdrop: c.state.canvasAsBackdrop,
            ));

    // Frame, artwork clip and canvas backdrop must share one corner value.
    // The cover used a hardcoded 26.8 while the frame read
    // resolveCustomRadius(), so a Theme Studio radius left visible corner
    // steps where the artwork met its bezel.
    final double artRadius = resolveCustomRadius(context, AppRadii.r28);
    final BorderRadius artCorners = AppRadii.circular(artRadius);

    final bool isPlaying = state.isPlaying;
    final bool showVisualizer = visualizerStyle != VisualizerStyle.off &&
        !state.isLyricsVisible &&
        !state.isQueueVisible &&
        !PlayerSplitViewScope.of(context);

    final double vizHeight =
        visualizerStyle == VisualizerStyle.circular ? 60.0 : 34.0;

    // The deck's light level. The shelf below the cover is tinted from this
    // same value, so the visualizer is lit by the cover glow instead of being
    // a separate widget that happens to share the accent colour.
    final double deckGlowAlpha = isPlaying ? 0.42 : 0.18;

    // The visualizer sits on a lit shelf that belongs to the cover deck, so
    // its height is reserved before the plate is sized. Reserving it after
    // would let the shelf push the deck out of the stage.
    final double shelfHeight =
        showVisualizer ? vizHeight + AppSpacing.xs : 0.0;

    return PlayerThemeScaffold(
      props: props,
      trackIcon: Icons.music_note_rounded,
      dockIconStyle: PlayerDockIconStyle.classic,
      // No onTap override: the shared gesture scope owns single-tap-to-lyrics,
      // which keeps Classic on the same convention as every other theme.
      stage: (context, metrics) => PlayerGestureScope(
        child: LayoutBuilder(
          builder: (context, artConstraints) {
            final double artSize = PlayerThemeMetrics.safeArtworkSize(
              availableWidth: artConstraints.maxWidth,
              availableHeight:
                  math.max(0.0, artConstraints.maxHeight - shelfHeight),
              isTablet: metrics.isTablet,
              maxAllowedOverride: metrics.isLandscape ? 280.0 : null,
            );
            if (artSize <= 0) return const SizedBox.shrink();

            return Center(
              key: const ValueKey('artwork_view'),
              child: SizedBox(
                width: artSize,
                height: artSize + shelfHeight,
                child: AnimatedScale(
                  scale: isPlaying ? 1.0 : 0.975,
                  duration: context.motionMs(320),
                  curve: context.motionCurve(Curves.easeOutCubic),
                  child: AnimatedContainer(
                    duration: context.motionMs(320),
                    curve: context.motionCurve(Curves.easeOutCubic),
                    decoration: BoxDecoration(
                      borderRadius: artCorners,
                      boxShadow: [
                        // Ambient: the cover's own light, in the exact colour
                        // the shelf waveform traces and gated by the same
                        // play state, so the strip below reads as part of this
                        // deck rather than a second, unrelated widget.
                        BoxShadow(
                          color: activeColor.withValues(alpha: deckGlowAlpha),
                          blurRadius: isPlaying ? 44 : 26,
                          spreadRadius: isPlaying ? 2 : 0,
                          offset: const Offset(0, 14),
                        ),
                        // Contact: one tight shadow seats the plate on the
                        // background. The old second ambient layer plus a
                        // 1.4 px white border were decoration competing with
                        // the glow for the same job.
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: p.isDark ? 0.34 : 0.14,
                          ),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: artSize,
                          height: artSize,
                          child: ClipRRect(
                            borderRadius: artCorners,
                            child: Hero(
                              tag: props.heroTag,
                              child: PlayerArtworkSemantics(
                                song: song,
                                child: song == null
                                    ? const SizedBox.shrink()
                                    : (!canvasAsBackdrop
                                        ? CanvasBackdrop(
                                            song: song,
                                            isPlaying: isPlaying,
                                            isBackdropMode: false,
                                            borderRadius: artCorners,
                                            fallbackArtwork: CachedArtwork(
                                              id: song.id,
                                              albumId: song.albumId,
                                              remoteUrl:
                                                  song.remoteArtworkUrl ??
                                                      song.artworkUri,
                                              type: ArtworkType.AUDIO,
                                              size: double.infinity,
                                              borderRadius: artRadius,
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
                                            borderRadius: artRadius,
                                            highQuality: true,
                                          )),
                              ),
                            ),
                          ),
                        ),
                        if (showVisualizer)
                          Container(
                            height: shelfHeight,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                            ),
                            decoration: BoxDecoration(
                              color: activeColor.withValues(
                                alpha: deckGlowAlpha * 0.38,
                              ),
                              borderRadius: BorderRadius.vertical(
                                bottom: Radius.circular(artRadius),
                              ),
                            ),
                            child: AudioVisualizer(
                              style: visualizerStyle,
                              color: activeColor,
                              height: vizHeight,
                              isPlaying: isPlaying,
                              audioSessionId: state.audioSessionId,
                              trackSeed: song?.id,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
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
