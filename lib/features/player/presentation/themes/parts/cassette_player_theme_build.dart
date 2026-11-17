part of '../cassette_player_theme.dart';

extension _CassettePlayerThemeBuild on _CassettePlayerThemeState {
  Widget _buildBody(BuildContext context) {
    final state = widget.props.state;
    final activeColor = widget.props.activeColor;
    final visualizerStyle = context
        .select<SettingsCubit, VisualizerStyle>((c) => c.state.visualizerStyle);
    // The deck is one painted object, so it publishes one semantics node
    // instead of the label print TalkBack used to read out ("SIDE A",
    // "TYPE II", "NR • OFF", the painted counter). Title, artist and
    // transport state come from the chrome header, which stays the accessible
    // source of truth; the shell only adds what the painting cannot say.
    final song = state.currentSong;
    final deckStatus = state.isPlaying
        ? context.l10n.ambientStatusPlaying
        : context.l10n.ambientStatusPaused;
    final deckLabel = song == null
        ? '${context.l10n.nowPlaying}, $deckStatus'
        : '${context.l10n.nowPlayingSemantics(song.title, song.artist)}, '
            '$deckStatus';
    final showVisualizer = visualizerStyle != VisualizerStyle.off &&
        !state.isLyricsVisible &&
        !state.isQueueVisible &&
        !PlayerSplitViewScope.of(context);

    return PlayerThemeScaffold(
      props: widget.props,
      trackIcon: Icons.radio_rounded,
      dockIconStyle: PlayerDockIconStyle.cassette,
      stage: (context, metrics) => PlayerGestureScope(
        // No onTap override: the stage convention is tap = toggle lyrics, and
        // transport already lives on the play/pause button.
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
                    child: Semantics(
                      container: true,
                      label: deckLabel,
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
