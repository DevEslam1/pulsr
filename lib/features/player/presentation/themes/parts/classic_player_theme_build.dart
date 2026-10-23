part of '../classic_player_theme.dart';

extension _ClassicPlayerThemeBuild on ClassicPlayerTheme {
  Widget _buildBody(BuildContext context) {
    final p = context.palette;
    final state = props.state;
    final cubit = props.cubit;
    final activeColor = props.activeColor;
    final bgColor = props.bgColor;
    final song = state.currentSong;

    final (
      :nowPlayingDoubleTap,
      :nowPlayingArtworkSwipe,
      :visualizerStyle,
      :waveformSeekBarEnabled,
      :canvasEnabled,
      :canvasAsBackdrop
    ) = context.select<
        SettingsCubit,
        ({
          NowPlayingDoubleTapAction nowPlayingDoubleTap,
          NowPlayingArtworkSwipeAction nowPlayingArtworkSwipe,
          VisualizerStyle visualizerStyle,
          bool waveformSeekBarEnabled,
          bool canvasEnabled,
          bool canvasAsBackdrop,
        })>((c) => (
          nowPlayingDoubleTap: c.state.nowPlayingDoubleTap,
          nowPlayingArtworkSwipe: c.state.nowPlayingArtworkSwipe,
          visualizerStyle: c.state.visualizerStyle,
          waveformSeekBarEnabled: c.state.waveformSeekBarEnabled,
          canvasEnabled: c.state.canvasEnabled,
          canvasAsBackdrop: c.state.canvasAsBackdrop,
        ));

    final artRadius = resolveCustomRadius(context, AppRadii.r28);

    final isTablet = context.isTablet;
    final isInSplitView = PlayerSplitViewScope.of(context);

    // Only show standalone audio visualizer if waveform seekbar is NOT already
    // visualizing the audio and the visualizer is explicitly turned on.
    final showVisualizer = visualizerStyle != VisualizerStyle.off &&
        !waveformSeekBarEnabled &&
        !state.isLyricsVisible &&
        !state.isQueueVisible;

    return Stack(
      children: [
        // 1. Dynamic Ambient Backdrop (Isolated in RepaintBoundary for 120fps)
        Positioned.fill(
          child: RepaintBoundary(
            child: Stack(
              children: [
                Positioned.fill(
                  child: AnimatedContainer(
                    duration: context.motionMs(500),
                    curve: context.motionCurve(Curves.easeInOut),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color.lerp(bgColor, Colors.black, 0.40) ?? bgColor,
                          p.bg,
                          Color.lerp(
                                  p.bg, Colors.black, p.isDark ? 0.48 : 0.05) ??
                              p.bg,
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 0.50, 1.0],
                      ),
                    ),
                  ),
                ),

                // Ambient Top Glow Sphere (Behind Artwork)
                PositionedDirectional(
                  top: -40,
                  start: -30,
                  end: -30,
                  height: isTablet ? 540 : 420,
                  child: IgnorePointer(
                    child: AnimatedContainer(
                      duration: context.motionMs(500),
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment.center,
                          radius: 0.85,
                          colors: [
                            activeColor.withValues(
                                alpha: state.isPlaying ? 0.34 : 0.22),
                            activeColor.withValues(alpha: 0.09),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.54, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),

                // Ambient Bottom Glow (Near Controls) - Centered for visual symmetry
                PositionedDirectional(
                  bottom: -70,
                  start: 0,
                  end: 0,
                  height: isTablet ? 420 : 320,
                  child: IgnorePointer(
                    child: AnimatedContainer(
                      duration: context.motionMs(500),
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment.center,
                          radius: 0.85,
                          colors: [
                            activeColor.withValues(alpha: 0.18),
                            activeColor.withValues(alpha: 0.05),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.5, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // 2. Main Foreground Layout
        SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final metrics =
                  PlayerThemeMetrics.calculate(context, constraints);
              final isLandscape = metrics.isLandscape;
              // Classic uses its own taller switcher insets.
              final switcherTopPad =
                  (isTablet ? 8.0 : 4.0) * metrics.heightRatio;
              final switcherBottomPad =
                  (isTablet ? 12.0 : 8.0) * metrics.heightRatio;
              final landscapeArtSize =
                  (constraints.maxHeight - 24).clamp(180.0, 560.0);

              final viewSwitcher = PlayerViewSwitcher(
                state: state,
                cubit: cubit,
                activeColor: activeColor,
                isTablet: isTablet,
                barWidth: isLandscape ? 286.0 : metrics.pillBarWidth,
                barHeight: isLandscape ? 36.0 : metrics.pillBarHeight,
                trackIcon: Icons.music_note_rounded,
                surfaceFillAlpha: 0.06,
                borderAlpha: 0.12,
              );

              final bottomDock = PlayerBottomActionDock(
                props: props,
                isTablet: isTablet,
                barWidth: metrics.pillBarWidth,
                barHeight: metrics.dockBarHeight,
                dockIconStyle: PlayerDockIconStyle.classic,
              );

              final artworkDisplay = GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => cubit.toggleLyricsVisibility(),
                onDoubleTap: () {
                  switch (nowPlayingDoubleTap) {
                    case NowPlayingDoubleTapAction.toggleFavorite:
                      if (song != null) cubit.toggleFavorite(song.id);
                      break;
                    case NowPlayingDoubleTapAction.toggleLyrics:
                      cubit.toggleLyricsVisibility();
                      break;
                    case NowPlayingDoubleTapAction.none:
                      break;
                  }
                },
                onHorizontalDragEnd: (details) {
                  if (nowPlayingArtworkSwipe ==
                          NowPlayingArtworkSwipeAction.nextPrev &&
                      details.primaryVelocity != null) {
                    if (details.primaryVelocity! < -200) {
                      cubit.next();
                    } else if (details.primaryVelocity! > 200) {
                      cubit.previous();
                    }
                  }
                },
                child: Center(
                  key: const ValueKey('artwork_view'),
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
              );

              final centerDisplay = isInSplitView
                  ? artworkDisplay
                  : AnimatedSwitcher(
                      duration: context.motionMs(320),
                      transitionBuilder: (child, anim) =>
                          playerOverlayTransitionBuilder(context, child, anim),
                      child: state.isLyricsVisible
                          ? LyricsView(
                              key: ValueKey(
                                  'lyrics_${song?.id}_${song?.remoteId}'),
                              lyrics: state.lyrics,
                              isLoading: state.isLoadingLyrics,
                              activeColor: activeColor,
                              source: state.lyricsSource,
                            )
                          : state.isQueueVisible
                              ? const NowPlayingQueueView(
                                  key: ValueKey('queue_view'),
                                )
                              : KeyedSubtree(
                                  key: const ValueKey('stage_classic'),
                                  child: artworkDisplay,
                                ),
                    );

              final visualizer = showVisualizer
                  ? Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 360),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg,
                              vertical: AppSpacing.xxs),
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

              final controlsColumn = PlayerControlsColumn(
                props: props,
                isTablet: isTablet,
                isLandscape: isLandscape,
                isInSplitView: isInSplitView,
                heightRatio: isLandscape ? 0.85 : metrics.heightRatio,
                metrics: metrics,
                trackHeader: PlayerTrackHeader(
                  props: props,
                  isTablet: isTablet,
                  metrics: metrics,
                  badgeGap: isLandscape ? AppSpacing.xxs : AppSpacing.s8,
                  titleArtistGap: isLandscape ? 2.0 : AppSpacing.xs,
                  verticalPadding:
                      isLandscape ? 0.0 : metrics.trackHeaderVerticalPadding,
                ),
                classicSizing: true,
                scaleMainButtonByHeight: true,
                abLoopActive: state.abLoopEnabled,
                dock: bottomDock,
              );

              // Responsive Split-View (Tablet Landscape Screen 2 - Left Pane)
              if (isInSplitView) {
                return LayoutBuilder(
                  builder: (context, splitConstraints) {
                    final double availableWidth =
                        splitConstraints.maxWidth - (isTablet ? 48.0 : 32.0);
                    final double availableHeight =
                        splitConstraints.maxHeight - 340.0;
                    final double rawSize =
                        math.min(availableWidth, availableHeight);
                    final double dynamicArtSize =
                        (rawSize <= 0 ? 220.0 : math.min(rawSize, 400.0))
                            .clamp(180.0, 420.0);

                    return Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                      child: Column(
                        children: [
                          Expanded(
                            child: Center(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: dynamicArtSize,
                                  maxHeight: dynamicArtSize,
                                ),
                                child: centerDisplay,
                              ),
                            ),
                          ),
                          controlsColumn,
                        ],
                      ),
                    );
                  },
                );
              }

              // Landscape / Tablet Two-Pane Mode
              if (isLandscape) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg, vertical: AppSpacing.xxs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Left Pane: Artwork
                      Expanded(
                        flex: 5,
                        child: Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: landscapeArtSize,
                              maxWidth: landscapeArtSize,
                            ),
                            child: centerDisplay,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s28),
                      // Right Pane: View Switcher (lyrics bar) + Controls
                      Expanded(
                        flex: 6,
                        child: Center(
                          key: const ValueKey('track_controls_pane'),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 540),
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      bottom: AppSpacing.xs,
                                    ),
                                    child: viewSwitcher,
                                  ),
                                  controlsColumn,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }

              // Portrait Mode: Fallback to scrolling on very short screens to preserve hero artwork
              final isVeryShort = constraints.maxHeight < 560;
              final isTrackView =
                  !state.isLyricsVisible && !state.isQueueVisible;

              if (isVeryShort && isTrackView) {
                final double scrollArtSize =
                    (constraints.maxHeight * 0.42).clamp(180.0, 300.0);

                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    children: [
                      const PlayerPlayHandle(
                        padding: EdgeInsets.only(
                            top: AppSpacing.s8, bottom: AppSpacing.xs),
                      ),
                      PlayerTopBar(
                        props: props,
                        isTablet: isTablet,
                        verticalPadding: AppSpacing.xs,
                      ),
                      const SizedBox(height: AppSpacing.s2),
                      Padding(
                        padding: EdgeInsets.only(
                          top: switcherTopPad,
                          bottom: switcherBottomPad,
                        ),
                        child: viewSwitcher,
                      ),
                      Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: scrollArtSize,
                            maxHeight: scrollArtSize,
                          ),
                          child: centerDisplay,
                        ),
                      ),
                      if (showVisualizer) visualizer,
                      SizedBox(
                          height:
                              (isTablet ? 12.0 : 8.0) * metrics.heightRatio),
                      controlsColumn,
                    ],
                  ),
                );
              }

              return Column(
                children: [
                  const PlayerPlayHandle(
                    padding: EdgeInsets.only(
                        top: AppSpacing.s8, bottom: AppSpacing.xs),
                  ),
                  PlayerTopBar(
                    props: props,
                    isTablet: isTablet,
                    verticalPadding: AppSpacing.xs,
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  // View Switcher Bar (Track | Lyrics | Queue)
                  Padding(
                    padding: EdgeInsets.only(
                      top: switcherTopPad,
                      bottom: switcherBottomPad,
                    ),
                    child: viewSwitcher,
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, artConstraints) {
                        final double availableWidth =
                            artConstraints.maxWidth - (isTablet ? 32.0 : 8.0);
                        final double availableHeight =
                            artConstraints.maxHeight - (isTablet ? 20.0 : 4.0);
                        final double maxAllowed = isTablet ? 600.0 : 480.0;
                        final double rawSize =
                            math.min(availableWidth, availableHeight);
                        final double dynamicArtSize =
                            rawSize <= 0 ? 0.0 : math.min(rawSize, maxAllowed);

                        return Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: (state.isLyricsVisible ||
                                      state.isQueueVisible)
                                  ? (isTablet ? 560.0 : double.infinity)
                                  : dynamicArtSize,
                              maxHeight: (state.isLyricsVisible ||
                                      state.isQueueVisible)
                                  ? double.infinity
                                  : dynamicArtSize,
                            ),
                            child: centerDisplay,
                          ),
                        );
                      },
                    ),
                  ),
                  if (showVisualizer) visualizer,
                  SizedBox(
                      height: (isTablet ? 12.0 : 8.0) * metrics.heightRatio),
                  controlsColumn,
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
