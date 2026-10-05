part of '../card_player_theme.dart';

extension _CardPlayerThemeBuild on CardPlayerTheme {
  Widget _buildBody(BuildContext context) {
    final p = context.palette;
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

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBgColor = isDark
        ? const Color(0xFF141828).withValues(alpha: 0.78)
        : AppColors.specularAt(0.92);
    final cardBorderColor = isDark ? AppColors.specularAt(0.15) : p.hairline;
    final textTitleColor = isDark ? Colors.white : p.textPrimary;
    final textSubtitleColor = isDark ? Colors.white70 : p.textSecondary;

    return Stack(
      children: [
        // 1. Full-bleed Artwork Background
        Positioned.fill(
          child: song != null
              ? CachedArtwork(
                  id: song.id,
                  albumId: song.albumId,
                  remoteUrl: song.remoteArtworkUrl ?? song.artworkUri,
                  type: ArtworkType.AUDIO,
                  size: double.infinity,
                  highQuality: true,
                )
              : Container(color: p.bg),
        ),

        // 2. Adaptive Gradient & Blur Overlay
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [
                        AppColors.scrimLight,
                        AppColors.scrimAt(0.75),
                        AppColors.scrimAt(0.95),
                      ]
                    : [
                        AppColors.specularAt(0.35),
                        AppColors.specularAt(0.65),
                        AppColors.specularAt(0.92),
                      ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ),

        // 3. Foreground Content
        SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isInSplitView = PlayerSplitViewScope.of(context);
              final metrics =
                  PlayerThemeMetrics.calculate(context, constraints);
              final isLandscape = metrics.isLandscape;

              final viewSwitcher = PlayerViewSwitcher(
                state: state,
                cubit: cubit,
                activeColor: activeColor,
                isTablet: isTablet,
                barWidth: metrics.pillBarWidth,
                barHeight: metrics.pillBarHeight,
                trackIcon: Icons.layers_rounded,
                surfaceFillAlpha: 0.08,
                borderAlpha: 0.15,
              );

              final bottomDock = PlayerBottomActionDock(
                props: props,
                isTablet: isTablet,
                barWidth: metrics.pillBarWidth,
                barHeight: metrics.pillBarHeight,
                disableBlur: true,
              );

              final artworkCard = GestureDetector(
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
                child: Center(
                  key: const ValueKey('artwork_card'),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: isLandscape ? 320 : double.infinity,
                      maxWidth: isLandscape ? 320 : double.infinity,
                    ),
                    child: AspectRatio(
                      aspectRatio: 1.0,
                      child: Hero(
                        tag: 'now_playing_art_full',
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: AppRadii.circular(
                                resolveCustomRadius(context, AppRadii.r28)),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.scrimAt(isDark ? 0.6 : 0.2),
                                blurRadius: 30,
                                spreadRadius: 4,
                                offset: const Offset(0, 12),
                              ),
                              BoxShadow(
                                color: activeColor.withValues(alpha: 0.3),
                                blurRadius: 24,
                                spreadRadius: -2,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: song != null
                              ? CachedArtwork(
                                  id: song.id,
                                  albumId: song.albumId,
                                  remoteUrl:
                                      song.remoteArtworkUrl ?? song.artworkUri,
                                  type: ArtworkType.AUDIO,
                                  size: double.infinity,
                                  borderRadius: 28,
                                  highQuality: true,
                                )
                              : Container(
                                  decoration: BoxDecoration(
                                    color: p.surfaceContainer,
                                    borderRadius: AppRadii.r28All,
                                  ),
                                  child: Icon(
                                    Icons.music_note_rounded,
                                    size: 96,
                                    color: textSubtitleColor.withValues(
                                        alpha: 0.4),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              );

              final centerDisplay = isInSplitView
                  ? artworkCard
                  : AnimatedSwitcher(
                      duration: context.motionMs(300),
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
                                  key: ValueKey('queue_view'))
                              : artworkCard,
                    );

              final showVisualizer = visualizerStyle != VisualizerStyle.off &&
                  !waveformSeekBarEnabled &&
                  !state.isLyricsVisible &&
                  !state.isQueueVisible &&
                  !isInSplitView;

              final visualizer = showVisualizer
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg, vertical: AppSpacing.s2),
                      child: AudioVisualizer(
                        style: visualizerStyle,
                        color: activeColor,
                        height: visualizerStyle == VisualizerStyle.circular
                            ? 64
                            : 40,
                        isPlaying: state.isPlaying,
                        audioSessionId: state.audioSessionId,
                        trackSeed: song?.id,
                      ),
                    )
                  : const SizedBox.shrink();

              final controlsColumn = PlayerControlsColumn(
                props: props,
                isTablet: isTablet,
                isLandscape: isLandscape,
                isInSplitView: isInSplitView,
                heightRatio: metrics.heightRatio,
                trackHeader: PlayerTrackHeader(
                  props: props,
                  isTablet: isTablet,
                  horizontalPadding: 0,
                  tabletHorizontalPadding: 0,
                  verticalPadding: 0,
                  titleColor: textTitleColor,
                  subtitleColor: textSubtitleColor,
                  titleArtistGap: AppSpacing.s2,
                ),
                scaleMainButtonByHeight: true,
                dense: true,
                dock: bottomDock,
              );

              final bottomGlassCard = GlassContainer(
                borderRadius: AppRadii.circular(
                    resolveCustomRadius(context, AppRadii.r28)),
                blur: 24,
                color: cardBgColor,
                border: Border.all(
                  color: cardBorderColor,
                  width: 1,
                ),
                padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md,
                    AppSpacing.sm, AppSpacing.md, AppSpacing.s10),
                child: controlsColumn,
              );

              if (isInSplitView) {
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: Column(
                    children: [
                      Expanded(child: centerDisplay),
                      bottomGlassCard,
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
                          child: bottomGlassCard,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return Column(
                children: [
                  const PlayerPlayHandle(),
                  PlayerTopBar(
                    props: props,
                    isTablet: isTablet,
                    titleColor: textTitleColor,
                    subtitleColor: textSubtitleColor,
                  ),

                  // Top View Switcher (lyrics bar: Track | Lyrics | Queue)
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
                        final double cardArtSize =
                            rawSize <= 0 ? 0.0 : math.min(rawSize, maxAllowed);

                        return Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: (state.isLyricsVisible ||
                                      state.isQueueVisible)
                                  ? (isTablet ? 560.0 : double.infinity)
                                  : cardArtSize,
                              maxHeight: (state.isLyricsVisible ||
                                      state.isQueueVisible)
                                  ? double.infinity
                                  : cardArtSize,
                            ),
                            child: centerDisplay,
                          ),
                        );
                      },
                    ),
                  ),

                  if (showVisualizer) visualizer,

                  SizedBox(
                      height:
                          (isTablet ? 12.0 : 8.0) * metrics.heightRatio),

                  // Bottom Card with Controls and EQ Action Dock
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md, vertical: AppSpacing.xxs),
                    child: bottomGlassCard,
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
