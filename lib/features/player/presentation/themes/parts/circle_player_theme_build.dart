part of '../circle_player_theme.dart';

extension _CirclePlayerThemeBuild on _CirclePlayerThemeState {
  Widget _buildBody(BuildContext context) {
    final cubit = widget.props.cubit;
    final activeColor = widget.props.activeColor;

    return PlayerThemeScaffold(
      props: widget.props,
      trackIcon: Icons.album_rounded,
      dockIconStyle: PlayerDockIconStyle.circle,
      stage: (context, metrics) => PlayerGestureScope(
        onTap: () => cubit.toggleLyricsVisibility(),
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
