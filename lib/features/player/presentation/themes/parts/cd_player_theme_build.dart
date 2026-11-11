part of '../cd_player_theme.dart';

extension _CdPlayerThemeBuild on _CdPlayerThemeState {
  Widget _buildBody(BuildContext context) {
    return PlayerThemeScaffold(
      props: widget.props,
      trackIcon: Icons.album_outlined,
      dockIconStyle: PlayerDockIconStyle.cd,
      stage: (context, metrics) => Center(
        key: const ValueKey('cd_stage_view'),
        child: Hero(
          tag: widget.props.heroTag,
          child: _CdTurntableStage(
            props: widget.props,
            isTablet: metrics.isTablet,
            isLandscape: metrics.isLandscape,
            rotationController: _rotationController,
            tonearmAnimation: _tonearmAnimation,
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
          dockIconStyle: PlayerDockIconStyle.cd,
        ),
      ),
    );
  }
}
