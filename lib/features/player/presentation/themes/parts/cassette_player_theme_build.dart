part of '../cassette_player_theme.dart';

extension _CassettePlayerThemeBuild on _CassettePlayerThemeState {
  Widget _buildBody(BuildContext context) {
    final cubit = widget.props.cubit;
    final activeColor = widget.props.activeColor;

    return PlayerThemeScaffold(
      props: widget.props,
      trackIcon: Icons.radio_rounded,
      dockIconStyle: PlayerDockIconStyle.cassette,
      stage: (context, metrics) => PlayerGestureScope(
        onTap: () => cubit.togglePlayPause(),
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
