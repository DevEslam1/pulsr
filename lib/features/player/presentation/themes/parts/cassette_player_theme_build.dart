part of '../cassette_player_theme.dart';

extension _CassettePlayerThemeBuild on _CassettePlayerThemeState {
  Widget _buildBody(BuildContext context) {
    final cubit = widget.props.cubit;
    final state = widget.props.state;
    final activeColor = widget.props.activeColor;
    final visualizerStyle = context.select<SettingsCubit, VisualizerStyle>(
        (c) => c.state.visualizerStyle);
    final showVisualizer = visualizerStyle != VisualizerStyle.off &&
        !state.isLyricsVisible &&
        !state.isQueueVisible &&
        !PlayerSplitViewScope.of(context);

    return PlayerThemeScaffold(
      props: widget.props,
      trackIcon: Icons.radio_rounded,
      dockIconStyle: PlayerDockIconStyle.cassette,
      stage: (context, metrics) => PlayerGestureScope(
        onTap: () => cubit.togglePlayPause(),
        child: LayoutBuilder(
          builder: (context, stageConstraints) {
            final double visualizerH = showVisualizer
                ? (visualizerStyle == VisualizerStyle.circular ? 60.0 : 34.0)
                : 0.0;
            final double visualizerSpace =
                showVisualizer ? visualizerH + 8.0 : 0.0;
            final double availableH =
                math.max(0.0, stageConstraints.maxHeight - visualizerSpace);
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  key: const ValueKey('cassette_view'),
                  child: SizedBox(
                    height: availableH,
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
                if (showVisualizer)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg, vertical: AppSpacing.xxs),
                      child: AudioVisualizer(
                        style: visualizerStyle,
                        color: activeColor,
                        height: visualizerH,
                        isPlaying: state.isPlaying,
                        audioSessionId: state.audioSessionId,
                        trackSeed: state.currentSong?.id,
                      ),
                    ),
                  ),
              ],
            );
          },
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
