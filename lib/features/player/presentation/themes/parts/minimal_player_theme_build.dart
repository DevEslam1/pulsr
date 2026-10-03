part of '../minimal_player_theme.dart';

extension _MinimalPlayerThemeBuild on MinimalPlayerTheme {
  Widget _buildBody(BuildContext context) {
    final state = props.state;
    final cubit = props.cubit;
    final activeColor = props.activeColor;
    final song = state.currentSong;
    final (:nowPlayingDoubleTap, :nowPlayingArtworkSwipe, :visualizerStyle) =
        context.select<
            SettingsCubit,
            ({
              NowPlayingDoubleTapAction nowPlayingDoubleTap,
              NowPlayingArtworkSwipeAction nowPlayingArtworkSwipe,
              VisualizerStyle visualizerStyle,
            })>((c) => (
              nowPlayingDoubleTap: c.state.nowPlayingDoubleTap,
              nowPlayingArtworkSwipe: c.state.nowPlayingArtworkSwipe,
              visualizerStyle: c.state.visualizerStyle,
            ));
    final isTablet = context.isTablet;

    return AnimatedContainer(
      duration: context.motionMs(400),
      curve: context.motionCurve(Curves.easeInOut),
      color: props.bgColor,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isInSplitView = PlayerSplitViewScope.of(context);
            final metrics = PlayerThemeMetrics.calculate(context, constraints);
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
              barHeight: metrics.pillBarHeight,
            );

            final centerDisplay = GestureDetector(
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
              child: AnimatedSwitcher(
                duration: context.motionMs(300),
                child: state.isLyricsVisible
                    ? LyricsView(
                        key: ValueKey('lyrics_${song?.id}_${song?.remoteId}'),
                        lyrics: state.lyrics,
                        isLoading: state.isLoadingLyrics,
                        activeColor: activeColor,
                        source: state.lyricsSource,
                      )
                    : state.isQueueVisible
                        ? const NowPlayingQueueView(
                            key: ValueKey('queue_view_minimal'),
                          )
                        : Column(
                            key: const ValueKey('minimal_art_display'),
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Center(
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxHeight:
                                        isLandscape ? 280 : double.infinity,
                                    maxWidth:
                                        isLandscape ? 280 : double.infinity,
                                  ),
                                  child: AspectRatio(
                                    aspectRatio: 1.0,
                                    child: Hero(
                                      tag: 'now_playing_art_minimal',
                                      child: Container(
                                        decoration: BoxDecoration(
                                          borderRadius: AppRadii.circular(
                                              resolveCustomRadius(context, 20)),
                                          boxShadow: [
                                            BoxShadow(
                                              color: activeColor.withValues(
                                                  alpha: 0.25),
                                              blurRadius: 28,
                                              spreadRadius: 1,
                                              offset: const Offset(0, 10),
                                            ),
                                          ],
                                        ),
                                        child: song != null
                                            ? CachedArtwork(
                                                id: song.id,
                                                albumId: song.albumId,
                                                remoteUrl:
                                                    song.remoteArtworkUrl ??
                                                        song.artworkUri,
                                                type: ArtworkType.AUDIO,
                                                size: double.infinity,
                                                borderRadius:
                                                    resolveCustomRadius(
                                                        context, 20),
                                                highQuality: true,
                                              )
                                            : const SizedBox.shrink(),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (visualizerStyle != VisualizerStyle.off) ...[
                                const SizedBox(height: AppSpacing.s10),
                                AudioVisualizer(
                                  style: visualizerStyle,
                                  color: activeColor,
                                  height: visualizerStyle ==
                                          VisualizerStyle.circular
                                      ? 60
                                      : 36,
                                  isPlaying: state.isPlaying,
                                  audioSessionId: state.audioSessionId,
                                  trackSeed: song?.id,
                                ),
                              ],
                            ],
                          ),
              ),
            );

            final controlsColumn = PlayerControlsColumn(
              props: props,
              isTablet: isTablet,
              isLandscape: isLandscape,
              isInSplitView: isInSplitView,
              heightRatio: metrics.heightRatio,
              trackHeader: PlayerTrackHeader(props: props, isTablet: isTablet),
              scaleMainButtonByHeight: true,
              dock: bottomDock,
            );

            if (isInSplitView) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Column(
                  children: [
                    Expanded(child: centerDisplay),
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
                      child: Column(
                        children: [
                          Padding(
                            padding: EdgeInsets.only(
                              top: metrics.switcherTopPad,
                              bottom: metrics.switcherBottomPad,
                            ),
                            child: viewSwitcher,
                          ),
                          Expanded(child: centerDisplay),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      flex: 6,
                      child: SingleChildScrollView(
                        child: controlsColumn,
                      ),
                    ),
                  ],
                ),
              );
            }

            return Column(
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
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, artConstraints) {
                      final double availableWidth =
                          artConstraints.maxWidth - (isTablet ? 64.0 : 36.0);
                      final double availableHeight =
                          artConstraints.maxHeight - (isTablet ? 24.0 : 12.0);
                      final double maxAllowed = isTablet ? 560.0 : 420.0;
                      final double rawSize =
                          math.min(availableWidth, availableHeight);
                      final double minArtSize =
                          rawSize <= 0 ? 0.0 : math.min(rawSize, maxAllowed);

                      return Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth:
                                (state.isLyricsVisible || state.isQueueVisible)
                                    ? (isTablet ? 560.0 : double.infinity)
                                    : minArtSize,
                            maxHeight:
                                (state.isLyricsVisible || state.isQueueVisible)
                                    ? double.infinity
                                    : minArtSize,
                          ),
                          child: centerDisplay,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                  child: controlsColumn,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
