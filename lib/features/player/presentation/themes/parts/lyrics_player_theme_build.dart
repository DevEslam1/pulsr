part of '../lyrics_player_theme.dart';

extension _LyricsPlayerThemeBuild on LyricsPlayerTheme {
  Widget _buildBody(BuildContext context) {
    final state = props.state;
    final cubit = props.cubit;
    final activeColor = props.activeColor;
    final bgColor = props.bgColor;
    final song = state.currentSong;
    final (:nowPlayingDoubleTap, :nowPlayingArtworkSwipe) = context.select<
        SettingsCubit,
        ({
          NowPlayingDoubleTapAction nowPlayingDoubleTap,
          NowPlayingArtworkSwipeAction nowPlayingArtworkSwipe,
        })>((c) => (
          nowPlayingDoubleTap: c.state.nowPlayingDoubleTap,
          nowPlayingArtworkSwipe: c.state.nowPlayingArtworkSwipe,
        ));
    final isTablet = context.isTablet;

    return Stack(
      children: [
        // 1 & 2. Dynamic Fluid Ambient Backdrop & Dual Glow Auras (Isolated in RepaintBoundary)
        Positioned.fill(
          child: RepaintBoundary(
            child: Stack(
              children: [
                Positioned.fill(
                  child: AnimatedContainer(
                    duration: context.motionMs(500),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color.lerp(bgColor, Colors.black, 0.42) ?? bgColor,
                          bgColor,
                          const Color(0xFF080910),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 0.48, 1.0],
                      ),
                    ),
                  ),
                ),
                PositionedDirectional(
                  top: -70,
                  start: -30,
                  end: -30,
                  height: isTablet ? 520 : 400,
                  child: IgnorePointer(
                    child: AnimatedContainer(
                      duration: context.motionMs(500),
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment.center,
                          radius: 0.85,
                          colors: [
                            activeColor.withValues(
                              alpha: state.isPlaying ? 0.32 : 0.18,
                            ),
                            activeColor.withValues(alpha: 0.07),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.54, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
                PositionedDirectional(
                  bottom: -60,
                  start: 0,
                  end: 0,
                  height: isTablet ? 380 : 280,
                  child: IgnorePointer(
                    child: AnimatedContainer(
                      duration: context.motionMs(500),
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment.center,
                          radius: 0.85,
                          colors: [
                            activeColor.withValues(alpha: 0.16),
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
        ),

        // 3. Foreground Content
        SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isInSplitView = PlayerSplitViewScope.of(context);
              final metrics =
                  PlayerThemeMetrics.calculate(context, constraints);
              final isLandscape = metrics.isLandscape;

              final viewSwitcher = PlayerViewSwitcher(
                state: state,
                cubit: cubit,
                activeColor: activeColor,
                isTablet: isTablet,
                barWidth: metrics.pillBarWidth,
                barHeight: metrics.pillBarHeight,
                trackIcon: Icons.album_rounded,
                surfaceFillAlpha: 0.06,
                borderAlpha: 0.12,
              );

              final bottomDock = PlayerBottomActionDock(
                props: props,
                isTablet: isTablet,
                barWidth: metrics.pillBarWidth,
                barHeight: metrics.dockBarHeight,
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
                  key: const ValueKey('track_art_lyrics_focus'),
                  child: LayoutBuilder(
                    builder: (context, artConstraints) {
                      final double availableWidth =
                          artConstraints.maxWidth - (isTablet ? 64.0 : 36.0);
                      final double availableHeight =
                          artConstraints.maxHeight - (isTablet ? 24.0 : 12.0);
                      final double maxAllowed = isTablet ? 560.0 : 420.0;
                      final double rawArtSize =
                          math.min(availableWidth, availableHeight);
                      final double artSize = isLandscape
                          ? 280.0
                          : (rawArtSize <= 0
                              ? 0.0
                              : math.min(rawArtSize, maxAllowed));

                      return ConstrainedBox(
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
                      );
                    },
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
                            ? Container(
                                key: ValueKey(
                                    'lyrics_${song?.id}_${song?.remoteId}'),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      AppColors.specularAt(0.07),
                                      context.palette.surfaceContainer
                                          .withValues(alpha: 0.24),
                                    ],
                                  ),
                                  borderRadius: AppRadii.r20All,
                                  border: Border.all(
                                    color: activeColor.withValues(alpha: 0.22),
                                    width: 1.1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.scrimAt(0.22),
                                      blurRadius: 20,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: LyricsView(
                                  lyrics: state.lyrics,
                                  isLoading: state.isLoadingLyrics,
                                  activeColor: activeColor,
                                  source: state.lyricsSource,
                                ),
                              )
                          : state.isQueueVisible
                              ? const NowPlayingQueueView(
                                  key: ValueKey('queue_view_lyrics'),
                                )
                              : KeyedSubtree(
                                  key: const ValueKey('stage_lyrics_focus'),
                                  child: artworkDisplay,
                                ),
                    );

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
                        fontSize: AppFontSize.micro,
                        fontWeight: FontWeight.w900,
                        letterSpacing: AppTracking.overline,
                        color: activeColor,
                      ),
                    ),
                  ],
                ),
              );

              final controlsColumn = PlayerControlsColumn(
                props: props,
                isTablet: isTablet,
                isLandscape: isLandscape,
                isInSplitView: isInSplitView,
                heightRatio: metrics.heightRatio,
                metrics: metrics,
                trackHeader: PlayerTrackHeader(
                  props: props,
                  isTablet: isTablet,
                  metrics: metrics,
                  extraBadge: extraBadge,
                ),
                scaleMainButtonByHeight: true,
                dock: bottomDock,
              );

              if (isInSplitView) {
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: Column(
                    children: [
                      Expanded(child: artworkDisplay),
                      controlsColumn,
                    ],
                  ),
                );
              }

              if (isLandscape) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        flex: 5,
                        child: Center(
                          child: centerDisplay,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        flex: 6,
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Padding(
                                padding: EdgeInsets.only(
                                  bottom: metrics.switcherBottomPad,
                                ),
                                child: viewSwitcher,
                              ),
                              controlsColumn,
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }

              // Portrait Mode: Fallback to scrolling on very short screens
              final isVeryShort = constraints.maxHeight < 560;
              final isTrackView =
                  !state.isLyricsVisible && !state.isQueueVisible;

              if (isVeryShort && isTrackView) {
                final double scrollSize =
                    (constraints.maxHeight * 0.40).clamp(180.0, 300.0);

                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    children: [
                      const PlayerPlayHandle(),
                      PlayerTopBar(props: props, isTablet: isTablet),
                      Padding(
                        padding: EdgeInsets.only(
                          top: metrics.switcherTopPad,
                          bottom: metrics.switcherBottomPad,
                        ),
                        child: viewSwitcher,
                      ),
                      Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: scrollSize,
                            maxHeight: scrollSize,
                          ),
                          child: centerDisplay,
                        ),
                      ),
                      SizedBox(
                          height:
                              (isTablet ? 12.0 : 8.0) * metrics.heightRatio),
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                        child: controlsColumn,
                      ),
                    ],
                  ),
                );
              }

              return Column(
                children: [
                  const PlayerPlayHandle(),
                  PlayerTopBar(props: props, isTablet: isTablet),

                  // Top View Switcher (lyrics bar: Track | Lyrics | Queue)
                  Padding(
                    padding: EdgeInsets.only(
                      top: metrics.switcherTopPad,
                      bottom: metrics.switcherBottomPad,
                    ),
                    child: viewSwitcher,
                  ),

                  // Center: Lyrics Immersion / Artwork / Queue
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: isTablet ? 580.0 : double.infinity,
                          maxHeight: double.infinity,
                        ),
                        child: centerDisplay,
                      ),
                    ),
                  ),

                  SizedBox(
                      height: (isTablet ? 12.0 : 8.0) * metrics.heightRatio),

                  // Bottom Controls Section
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                    child: controlsColumn,
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
