part of '../cassette_player_theme.dart';

extension _CassettePlayerThemeBuild on _CassettePlayerThemeState {
  Widget _buildBody(BuildContext context) {
    final state = widget.props.state;
    final cubit = widget.props.cubit;
    final activeColor = widget.props.activeColor;
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

    return LayoutBuilder(
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
          trackIcon: Icons.radio_rounded,
          surfaceFillAlpha: 0.06,
          borderAlpha: 0.12,
        );

        final bottomDock = PlayerBottomActionDock(
          props: widget.props,
          isTablet: isTablet,
          barWidth: metrics.pillBarWidth,
          barHeight: metrics.pillBarHeight,
        );

        final centerDisplay = AnimatedSwitcher(
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
                  : GestureDetector(
                      onTap: () => cubit.togglePlayPause(),
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
                        key: const ValueKey('cassette_view'),
                        child: _CassetteBody(
                          song: song,
                          activeColor: activeColor,
                          spoolController: _spoolController,
                          isLandscape: isLandscape,
                          isTablet: isTablet,
                        ),
                      ),
                    ),
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
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Column(
                children: [
                  Expanded(child: centerDisplay),
                  controlsColumn,
                ],
              ),
            ),
          );
        }

        if (isLandscape) {
          return SafeArea(
            child: Padding(
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
            ),
          );
        }

        return SafeArea(
          child: Column(
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

              // Center: Cassette / Lyrics / Queue
              Expanded(
                child: LayoutBuilder(
                  builder: (context, artConstraints) {
                    final double availableWidth =
                        artConstraints.maxWidth - (isTablet ? 64.0 : 28.0);
                    final double availableHeight =
                        artConstraints.maxHeight - (isTablet ? 24.0 : 12.0);
                    final double maxW = isTablet ? 560.0 : 440.0;
                    final double maxH = isTablet ? 360.0 : 300.0;
                    final double rawW = math.min(availableWidth, maxW);
                    final double rawH = math.min(availableHeight, maxH);
                    final double cassetteW = rawW <= 0 ? 0.0 : rawW;
                    final double cassetteH = rawH <= 0 ? 0.0 : rawH;

                    return Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth:
                              (state.isLyricsVisible || state.isQueueVisible)
                                  ? (isTablet ? 560.0 : double.infinity)
                                  : cassetteW,
                          maxHeight:
                              (state.isLyricsVisible || state.isQueueVisible)
                                  ? double.infinity
                                  : cassetteH,
                        ),
                        child: centerDisplay,
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: AppSpacing.xxs),

              // Bottom Controls Section
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                child: controlsColumn,
              ),
            ],
          ),
        );
      },
    );
  }
}
