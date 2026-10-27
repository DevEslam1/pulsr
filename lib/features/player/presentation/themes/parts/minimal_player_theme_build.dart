part of '../minimal_player_theme.dart';

extension _MinimalPlayerThemeBuild on MinimalPlayerTheme {
  Widget _buildBody(BuildContext context) {
    final state = props.state;
    final cubit = props.cubit;
    final activeColor = props.activeColor;
    final song = state.currentSong;
    final (
      :nowPlayingDoubleTap,
      :nowPlayingArtworkSwipe,
      :visualizerStyle,
      :waveformSeekBarEnabled
    ) = context.select<
        SettingsCubit,
        ({
          NowPlayingDoubleTapAction nowPlayingDoubleTap,
          NowPlayingArtworkSwipeAction nowPlayingArtworkSwipe,
          VisualizerStyle visualizerStyle,
          bool waveformSeekBarEnabled,
        })>((c) => (
          nowPlayingDoubleTap: c.state.nowPlayingDoubleTap,
          nowPlayingArtworkSwipe: c.state.nowPlayingArtworkSwipe,
          visualizerStyle: c.state.visualizerStyle,
          waveformSeekBarEnabled: c.state.waveformSeekBarEnabled,
        ));
    final isTablet = context.isTablet;

    return AnimatedContainer(
      duration: context.motionMs(400),
      curve: context.motionCurve(Curves.easeInOut),
      decoration: BoxDecoration(
        color: props.bgColor,
        gradient: RadialGradient(
          center: const Alignment(0, -0.35),
          radius: 1.1,
          colors: [
            Color.lerp(props.bgColor, activeColor, 0.10) ?? props.bgColor,
            props.bgColor,
          ],
        ),
      ),
      child: SafeArea(
        child: LayoutBuilder(
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
              props: props,
              isTablet: isTablet,
              barWidth: metrics.pillBarWidth,
              barHeight: metrics.dockBarHeight,
            );

            final showVisualizer = visualizerStyle != VisualizerStyle.off &&
                !waveformSeekBarEnabled &&
                !state.isLyricsVisible &&
                !state.isQueueVisible &&
                !isInSplitView;

            final artworkDisplay = GestureDetector(
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
              child: LayoutBuilder(
                builder: (context, artConstraints) {
                  final visualizerSpace = showVisualizer
                      ? math.min(
                          artConstraints.maxHeight,
                          visualizerStyle == VisualizerStyle.circular
                              ? 70.0
                              : 46.0)
                      : 0.0;
                  final telemetrySpace = (song != null) ? 50.0 : 0.0;
                  final artworkSize = PlayerThemeMetrics.safeArtworkSize(
                    availableWidth: artConstraints.maxWidth,
                    availableHeight: math.max(
                        0.0,
                        artConstraints.maxHeight -
                            visualizerSpace -
                            telemetrySpace),
                    isTablet: isTablet,
                    maxAllowedOverride: isLandscape ? 280.0 : null,
                  );
                  return Column(
                    key: const ValueKey('minimal_art_display'),
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Center(
                        child: SizedBox(
                          width: artworkSize,
                          height: artworkSize,
                          child: AspectRatio(
                            aspectRatio: 1.0,
                            child: Hero(
                              tag: props.heroTag,
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: AppRadii.circular(
                                      resolveCustomRadius(context, 20)),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.16),
                                    width: 1.2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          activeColor.withValues(alpha: 0.25),
                                      blurRadius: 28,
                                      spreadRadius: 1,
                                      offset: const Offset(0, 10),
                                    ),
                                  ],
                                ),
                                child: song != null
                                    ? CachedArtwork(
                                        id: song.id,
                                        albumId: song.albumId,
                                        remoteUrl: song.remoteArtworkUrl ??
                                            song.artworkUri,
                                        type: ArtworkType.AUDIO,
                                        size: double.infinity,
                                        borderRadius:
                                            resolveCustomRadius(context, 20),
                                        highQuality: true,
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ),
                          ),
                        ),
                      ),
                      _MinimalAudiophileTelemetry(
                        song: song,
                        activeColor: activeColor,
                      ),
                      if (showVisualizer) ...[
                        SizedBox(height: math.min(10.0, visualizerSpace)),
                        AudioVisualizer(
                          style: visualizerStyle,
                          color: activeColor,
                          height: math.max(0.0, visualizerSpace - 10),
                          isPlaying: state.isPlaying,
                          audioSessionId: state.audioSessionId,
                          trackSeed: song?.id,
                        ),
                      ],
                    ],
                  );
                },
              ),
            );

            final centerDisplay = isInSplitView
                ? artworkDisplay
                : AnimatedSwitcher(
                    duration: context.motionMs(320),
                    transitionBuilder: (child, anim) =>
                        playerOverlayTransitionBuilder(context, child, anim),
                    child: state.isLyricsVisible
                        ? LyricsView(
                            key: ValueKey(
                                'lyrics_${song?.id}_${song?.remoteId}'),
                            lyrics: state.lyrics,
                            isLoading: state.isLoadingLyrics,
                            activeColor: activeColor,
                            source: state.lyricsSource,
                          )
                        : state.isQueueVisible
                            ? const NowPlayingQueueView(
                                key: ValueKey('queue_view_minimal'),
                              )
                            : KeyedSubtree(
                                key: const ValueKey('stage_minimal'),
                                child: artworkDisplay,
                              ),
                  );

            final controlsColumn = PlayerControlsColumn(
              props: props,
              isTablet: isTablet,
              isLandscape: isLandscape,
              isInSplitView: isInSplitView,
              heightRatio: metrics.heightRatio,
              metrics: metrics,
              trackHeader: PlayerTrackHeader(
                props: props,
                isTablet: isTablet,
                metrics: metrics,
              ),
              scaleMainButtonByHeight: true,
              dock: bottomDock,
            );

            if (isInSplitView) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Column(
                  children: [
                    Expanded(child: artworkDisplay),
                    Flexible(
                      child: SingleChildScrollView(
                        child: controlsColumn,
                      ),
                    ),
                  ],
                ),
              );
            }

            if (isLandscape) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      flex: 5,
                      child: Center(child: centerDisplay),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      flex: 6,
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: EdgeInsets.only(
                                bottom: metrics.switcherBottomPad,
                              ),
                              child: viewSwitcher,
                            ),
                            controlsColumn,
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            // Portrait Mode: Fallback to scrolling on very short screens
            final isVeryShort = constraints.maxHeight < 560;
            final isTrackView = !state.isLyricsVisible && !state.isQueueVisible;

            if (isVeryShort && isTrackView) {
              final double scrollSize =
                  (constraints.maxHeight * 0.40).clamp(180.0, 300.0);

              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    const PlayerPlayHandle(),
                    PlayerTopBar(props: props, isTablet: isTablet),
                    Padding(
                      padding: EdgeInsets.only(
                        top: metrics.switcherTopPad,
                        bottom: metrics.switcherBottomPad,
                      ),
                      child: viewSwitcher,
                    ),
                    Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: scrollSize,
                          maxHeight: scrollSize,
                        ),
                        child: centerDisplay,
                      ),
                    ),
                    SizedBox(
                        height: (isTablet ? 8.0 : 6.0) * metrics.heightRatio),
                    controlsColumn,
                  ],
                ),
              );
            }

            return Column(
              children: [
                const PlayerPlayHandle(),
                PlayerTopBar(props: props, isTablet: isTablet),
                Padding(
                  padding: EdgeInsets.only(
                    top: metrics.switcherTopPad,
                    bottom: metrics.switcherBottomPad,
                  ),
                  child: viewSwitcher,
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, artConstraints) {
                      final double availableWidth =
                          artConstraints.maxWidth - (isTablet ? 64.0 : 36.0);
                      final double availableHeight =
                          artConstraints.maxHeight - (isTablet ? 36.0 : 20.0);
                      final double maxAllowed = isTablet ? 560.0 : 420.0;
                      final double rawSize =
                          math.min(availableWidth, availableHeight);
                      final double minArtSize =
                          rawSize <= 0 ? 0.0 : math.min(rawSize, maxAllowed);

                      return Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth:
                                (state.isLyricsVisible || state.isQueueVisible)
                                    ? (isTablet ? 560.0 : double.infinity)
                                    : minArtSize,
                            maxHeight:
                                (state.isLyricsVisible || state.isQueueVisible)
                                    ? double.infinity
                                    : minArtSize,
                          ),
                          child: centerDisplay,
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(height: (isTablet ? 8.0 : 6.0) * metrics.heightRatio),
                controlsColumn,
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Swiss / Teenage Engineering Audiophile Telemetry HUD
// ---------------------------------------------------------------------------
class _MinimalAudiophileTelemetry extends StatelessWidget {
  final SongsTableData? song;
  final Color activeColor;

  const _MinimalAudiophileTelemetry({
    required this.song,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    if (song == null) return const SizedBox.shrink();

    final p = context.palette;
    final ext = (song!.codec != null && song!.codec!.isNotEmpty)
        ? song!.codec!.toUpperCase()
        : (song!.path.contains('.')
            ? song!.path.split('.').last.toUpperCase()
            : 'PCM');
    final sampleRateStr = song!.sampleRate != null && song!.sampleRate! > 0
        ? '${(song!.sampleRate! / 1000).toStringAsFixed(1)} kHz'
        : '44.1 kHz';
    final bitDepthStr = song!.bitDepth != null && song!.bitDepth! > 0
        ? '${song!.bitDepth}-BIT'
        : '16-BIT';
    final bitrateStr = song!.bitrateKbps != null && song!.bitrateKbps! > 0
        ? '${song!.bitrateKbps} kbps'
        : null;

    return MediaQuery.withNoTextScaling(
      child: Container(
        margin: const EdgeInsets.only(top: AppSpacing.s10),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              p.surfaceContainerHigh,
              p.surfaceContainer,
            ],
          ),
          borderRadius: AppRadii.r8All,
          border: Border.all(
            color: activeColor.withValues(alpha: 0.28),
            width: 0.9,
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 5,
                height: 5,
                margin: const EdgeInsetsDirectional.only(end: 6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: activeColor,
                  boxShadow: [
                    BoxShadow(
                      color: activeColor.withValues(alpha: 0.6),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
              _buildChip(ext, textColor: activeColor),
              _buildDivider(p.hairline),
              _buildChip(sampleRateStr, textColor: p.textSecondary),
              _buildDivider(p.hairline),
              _buildChip(bitDepthStr, textColor: p.textSecondary),
              if (bitrateStr != null) ...[
                _buildDivider(p.hairline),
                _buildChip(bitrateStr, textColor: p.textSecondary),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChip(String label, {required Color textColor}) {
    return Text(
      label,
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: 9.5,
        fontWeight: FontWeight.w800,
        color: textColor,
        letterSpacing: 0.6,
      ),
    );
  }

  Widget _buildDivider(Color dividerColor) {
    return Container(
      width: 1,
      height: 9,
      margin: const EdgeInsets.symmetric(horizontal: 7),
      color: dividerColor,
    );
  }
}
