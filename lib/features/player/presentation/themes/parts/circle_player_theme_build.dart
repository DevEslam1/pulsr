part of '../circle_player_theme.dart';

extension _CirclePlayerThemeBuild on _CirclePlayerThemeState {
  Widget _buildBody(BuildContext context) {
    final p = context.palette;
    final state = widget.props.state;
    final cubit = widget.props.cubit;
    final activeColor = widget.props.activeColor;
    final bgColor = widget.props.bgColor;
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

    return AnimatedContainer(
      duration: context.motionMs(400),
      curve: context.motionCurve(Curves.easeInOut),
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.3),
          radius: 1.2,
          colors: [
            bgColor,
            p.bg,
          ],
        ),
      ),
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
              props: widget.props,
              isTablet: isTablet,
              barWidth: metrics.pillBarWidth,
              barHeight: metrics.pillBarHeight,
            );

            final circleStage = GestureDetector(
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
                key: const ValueKey('circle_artwork_view'),
                child: Hero(
                  tag: 'now_playing_art_full',
                  child: _CircleArtwork(
                    song: song,
                    activeColor: activeColor,
                    rotationController: _rotationController,
                    isTablet: isTablet,
                    isLandscape: isLandscape,
                  ),
                ),
              ),
            );

            final centerDisplay = isInSplitView
                ? circleStage
                : AnimatedSwitcher(
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
                                key: ValueKey('queue_view'),
                              )
                            : circleStage,
                  );

            final controlsColumn = PlayerControlsColumn(
              props: widget.props,
              isTablet: isTablet,
              isLandscape: isLandscape,
              isInSplitView: isInSplitView,
              heightRatio: metrics.heightRatio,
              trackHeader:
                  PlayerTrackHeader(props: widget.props, isTablet: isTablet),
              scaleMainButtonByHeight: true,
              dock: bottomDock,
            );

            if (isInSplitView) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Column(
                  children: [
                    Expanded(child: circleStage),
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
                          Expanded(
                            child: centerDisplay,
                          ),
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
                PlayerTopBar(props: widget.props, isTablet: isTablet),

                // Top View Switcher (lyrics bar: Track | Lyrics | Queue)
                Padding(
                  padding: EdgeInsets.only(
                    top: metrics.switcherTopPad,
                    bottom: metrics.switcherBottomPad,
                  ),
                  child: viewSwitcher,
                ),

                // Center: Spinning Circle / Lyrics / Queue
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, artConstraints) {
                      final double availableWidth =
                          artConstraints.maxWidth - (isTablet ? 64.0 : 36.0);
                      final double availableHeight =
                          artConstraints.maxHeight - (isTablet ? 36.0 : 20.0);
                      final double maxAllowed = isTablet ? 560.0 : 420.0;
                      final double rawSize =
                          math.min(availableWidth, availableHeight);
                      final double circleArtSize =
                          rawSize <= 0 ? 0.0 : math.min(rawSize, maxAllowed);

                      return Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth:
                                (state.isLyricsVisible || state.isQueueVisible)
                                    ? (isTablet ? 560.0 : double.infinity)
                                    : circleArtSize,
                            maxHeight:
                                (state.isLyricsVisible || state.isQueueVisible)
                                    ? double.infinity
                                    : circleArtSize,
                          ),
                          child: centerDisplay,
                        ),
                      );
                    },
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
    );
  }
}
