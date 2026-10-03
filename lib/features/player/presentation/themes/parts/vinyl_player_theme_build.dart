part of '../vinyl_player_theme.dart';

extension _VinylPlayerThemeBuild on _VinylPlayerThemeState {
  Widget _buildBody(BuildContext context) {
    final state = widget.props.state;
    final cubit = widget.props.cubit;
    final activeColor = widget.props.activeColor;
    final song = state.currentSong;
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
                  : Center(
                      key: const ValueKey('turntable_view'),
                      child: _VinylTurntableDeck(
                        props: widget.props,
                        isTablet: isTablet,
                        isLandscape: isLandscape,
                        rotationController: _rotationController,
                        tonearmAnimation: _tonearmAnimation,
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

              // Center: Turntable / Lyrics / Queue
              Expanded(
                child: LayoutBuilder(
                  builder: (context, artConstraints) {
                    final double availableWidth =
                        artConstraints.maxWidth - (isTablet ? 64.0 : 28.0);
                    final double availableHeight =
                        artConstraints.maxHeight - (isTablet ? 24.0 : 12.0);
                    final double maxAllowed = isTablet ? 560.0 : 420.0;
                    final double rawSize =
                        math.min(availableWidth, availableHeight);
                    final double deckSize =
                        rawSize <= 0 ? 0.0 : math.min(rawSize, maxAllowed);

                    return Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth:
                              (state.isLyricsVisible || state.isQueueVisible)
                                  ? (isTablet ? 560.0 : double.infinity)
                                  : deckSize,
                          maxHeight:
                              (state.isLyricsVisible || state.isQueueVisible)
                                  ? double.infinity
                                  : deckSize,
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
