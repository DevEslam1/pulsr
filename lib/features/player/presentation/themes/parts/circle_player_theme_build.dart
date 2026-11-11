part of '../circle_player_theme.dart';

extension _CirclePlayerThemeBuild on _CirclePlayerThemeState {
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
      trackIcon: Icons.album_rounded,
      dockIconStyle: PlayerDockIconStyle.circle,
      stage: (context, metrics) => GestureDetector(
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
          key: const ValueKey('circle_artwork_view'),
          child: Hero(
            tag: widget.props.heroTag,
            child: _CircleArtwork(
              props: widget.props,
              activeColor: activeColor,
              rotationController: _rotationController,
              isTablet: metrics.isTablet,
              isLandscape: metrics.isLandscape,
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
          dockIconStyle: PlayerDockIconStyle.circle,
        ),
      ),
    );
  }
}
