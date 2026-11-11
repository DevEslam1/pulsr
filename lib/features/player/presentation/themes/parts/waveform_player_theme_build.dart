part of '../waveform_player_theme.dart';

extension _WaveformPlayerThemeBuild on _WaveformPlayerThemeState {
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

    final extraBadge = Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s6, vertical: AppSpacing.s2),
      decoration: BoxDecoration(
        color: activeColor.withValues(alpha: 0.16),
        borderRadius: AppRadii.r6All,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.graphic_eq_rounded, size: 11, color: activeColor),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            context.l10n.waveformLabel,
            style: TextStyle(
              fontSize: AppFontSize.micro,
              fontWeight: FontWeight.w900,
              letterSpacing: AppTracking.overline,
              color: activeColor,
            ),
          ),
        ],
      ),
    );

    return PlayerThemeScaffold(
      props: widget.props,
      trackIcon: Icons.graphic_eq_rounded,
      dockIconStyle: PlayerDockIconStyle.waveform,
      background: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.22),
            radius: 1.32,
            colors: [
              Color.lerp(bgColor, activeColor, 0.14) ?? bgColor,
              bgColor,
              p.bg,
            ],
            stops: const [0.0, 0.48, 1.0],
          ),
        ),
      ),
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
        child: _WaveformHeroStage(
          key: const ValueKey('waveform_hero_stage'),
          song: song,
          activeColor: activeColor,
          isPlaying: state.isPlaying,
          isLandscape: metrics.isLandscape,
          isTablet: metrics.isTablet,
          waveController: _waveController,
          audioSessionId: state.audioSessionId,
          heroTag: widget.props.heroTag,
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
          extraBadge: extraBadge,
        ),
        scaleMainButtonByHeight: true,
        dock: PlayerBottomActionDock(
          props: widget.props,
          isTablet: metrics.isTablet,
          barWidth: metrics.pillBarWidth,
          barHeight: metrics.dockBarHeight,
          dockIconStyle: PlayerDockIconStyle.waveform,
        ),
      ),
    );
  }
}
