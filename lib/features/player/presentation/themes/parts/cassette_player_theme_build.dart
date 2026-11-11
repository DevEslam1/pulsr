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

    return PlayerThemeScaffold(
      props: widget.props,
      trackIcon: Icons.radio_rounded,
      dockIconStyle: PlayerDockIconStyle.cassette,
      stage: (context, metrics) => GestureDetector(
        behavior: HitTestBehavior.opaque,
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
          if (nowPlayingArtworkSwipe == NowPlayingArtworkSwipeAction.nextPrev &&
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
          child: Hero(
            tag: widget.props.heroTag,
            child: _CassetteBody(
              props: widget.props,
              activeColor: activeColor,
              spoolController: _spoolController,
              isLandscape: metrics.isLandscape,
              isTablet: metrics.isTablet,
            ),
          ),
        ),
      ),
      chrome: (context, metrics) => PlayerControlsColumn(
        props: widget.props,
        isTablet: metrics.isTablet,
        isLandscape: metrics.isLandscape,
        isInSplitView: PlayerSplitViewScope.of(context),
        heightRatio: metrics.heightRatio,
        metrics: metrics,
        trackHeader: PlayerTrackHeader(
          props: widget.props,
          isTablet: metrics.isTablet,
          metrics: metrics,
        ),
        scaleMainButtonByHeight: true,
        dock: PlayerBottomActionDock(
          props: widget.props,
          isTablet: metrics.isTablet,
          barWidth: metrics.pillBarWidth,
          barHeight: metrics.dockBarHeight,
          dockIconStyle: PlayerDockIconStyle.cassette,
        ),
      ),
    );
  }
}
