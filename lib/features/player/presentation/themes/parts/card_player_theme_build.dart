part of '../card_player_theme.dart';

extension _CardPlayerThemeBuild on CardPlayerTheme {
  Widget _buildBody(BuildContext context) {
    final p = context.palette;
    final state = props.state;
    final activeColor = props.activeColor;
    final song = state.currentSong;
    final isPlaying = state.isPlaying;

    // Only the visualizer style is read here. The seek bar resolves its own
    // waveform/slider preferences, so selecting them rebuilt the whole card
    // for values it never painted.
    final visualizerStyle = context
        .select<SettingsCubit, VisualizerStyle>((c) => c.state.visualizerStyle);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textTitleColor = isDark ? Colors.white : p.textPrimary;
    final textSubtitleColor = isDark ? Colors.white70 : p.textSecondary;

    // One corner value for the sleeve, its artwork and the empty-state plate.
    // The frame used resolveCustomRadius() while the cover used a literal 28,
    // which showed a corner step as soon as Theme Studio moved the radius.
    final double sleeveRadius = resolveCustomRadius(context, AppRadii.r28);
    final BorderRadius sleeveCorners = AppRadii.circular(sleeveRadius);

    final showVisualizer = visualizerStyle != VisualizerStyle.off &&
        !state.isLyricsVisible &&
        !state.isQueueVisible &&
        !PlayerSplitViewScope.of(context);

    final visualizer = showVisualizer
        ? Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg, vertical: AppSpacing.s2),
            child: AudioVisualizer(
              style: visualizerStyle,
              color: activeColor,
              height: visualizerStyle == VisualizerStyle.circular ? 64 : 40,
              isPlaying: isPlaying,
              audioSessionId: state.audioSessionId,
              trackSeed: song?.id,
            ),
          )
        : const SizedBox.shrink();

    return PlayerThemeScaffold(
      props: props,
      trackIcon: Icons.layers_rounded,
      background: ExcludeSemantics(
        child: RepaintBoundary(
          child: Stack(
            fit: StackFit.expand,
            children: [
              song != null
                  ? CanvasBackdrop(
                      song: song,
                      isPlaying: isPlaying,
                      isBackdropMode: true,
                      fallbackArtwork: CachedArtwork(
                        id: song.id,
                        albumId: song.albumId,
                        remoteUrl: song.remoteArtworkUrl ?? song.artworkUri,
                        type: ArtworkType.AUDIO,
                        size: double.infinity,
                        highQuality: true,
                      ),
                    )
                  : Container(color: p.bg),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [
                            AppColors.scrimLight,
                            AppColors.scrimAt(0.72),
                            AppColors.scrimAt(0.94),
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
              PositionedDirectional(
                bottom: -40,
                start: -20,
                end: -20,
                height: context.isTablet ? 440 : 340,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.center,
                        radius: 0.85,
                        colors: [
                          activeColor.withValues(alpha: isDark ? 0.24 : 0.14),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      // No onTap override: the shared gesture scope keeps single tap bound to
      // lyrics, same as every other theme.
      stage: (context, metrics) => PlayerGestureScope(
        child: LayoutBuilder(
          builder: (context, artConstraints) {
            // Rotation swings the sleeve corners a few pixels past its own
            // box, so the stage reserves that bleed instead of letting the
            // stack paint over the screen gutter.
            const double stackBleed = 10.0;
            final double visualizerH = visualizerStyle == VisualizerStyle.circular
                ? 64.0
                : 40.0;
            final double visualizerSpace =
                showVisualizer ? visualizerH + AppSpacing.xxs : 0.0;
            final double sleeveSize = PlayerThemeMetrics.safeArtworkSize(
              availableWidth:
                  math.max(0.0, artConstraints.maxWidth - stackBleed * 2),
              availableHeight: math.max(
                0.0,
                artConstraints.maxHeight - visualizerSpace - stackBleed * 2,
              ),
              isTablet: metrics.isTablet,
              maxAllowedOverride: metrics.isLandscape ? 280.0 : null,
            );
            if (sleeveSize <= 0) return const SizedBox.shrink();

            // The cards wedged behind the cover. Painted as real stock: an
            // accent-tinted board, a hairline rim and a soft shadow, each
            // turned a degree or two so the pile never looks printed.
            Widget wedgedSleeve({
              required Color fill,
              required Color rim,
              required double offsetY,
              required double turn,
            }) {
              return AnimatedSlide(
                offset: Offset(0, offsetY),
                duration: context.motionMs(420),
                curve: context.motionCurve(Curves.easeOutCubic),
                child: AnimatedRotation(
                  turns: turn,
                  duration: context.motionMs(420),
                  curve: context.motionCurve(Curves.easeOutCubic),
                  child: Container(
                    width: sleeveSize,
                    height: sleeveSize,
                    decoration: BoxDecoration(
                      borderRadius: sleeveCorners,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          fill,
                          Color.lerp(fill, p.bg, 0.35) ?? fill,
                        ],
                      ),
                      border: Border.all(color: rim, width: 1.0),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black
                              .withValues(alpha: isDark ? 0.30 : 0.10),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  key: const ValueKey('artwork_card'),
                  child: SizedBox(
                    width: sleeveSize + stackBleed * 2,
                    height: sleeveSize + stackBleed * 2,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        wedgedSleeve(
                          fill: Color.lerp(
                                  p.surfaceContainer, activeColor, 0.30) ??
                              p.surfaceContainer,
                          rim: activeColor.withValues(alpha: 0.20),
                          offsetY: isPlaying ? 0.030 : 0.018,
                          // -3.2° out of the pile, -2.6° resting in it.
                          turn: isPlaying ? -0.0089 : -0.0072,
                        ),
                        wedgedSleeve(
                          fill: Color.lerp(
                                  p.surfaceContainerHigh, activeColor, 0.18) ??
                              p.surfaceContainerHigh,
                          rim: p.isDark
                              ? AppColors.specularAt(0.22)
                              : p.hairline,
                          offsetY: isPlaying ? 0.016 : 0.009,
                          // 2.1° against the card below, so the pile fans open.
                          turn: isPlaying ? 0.0058 : 0.0044,
                        ),
                        // The top sleeve. Playing = pulled clear of the pile:
                        // it straightens, scales up and casts a longer shadow.
                        AnimatedScale(
                          scale: isPlaying ? 1.0 : 0.955,
                          duration: context.motionMs(420),
                          curve: context.motionCurve(Curves.easeOutCubic),
                          child: AnimatedRotation(
                            // 1.8° while it rests in the stack, square once
                            // it is out.
                            turns: isPlaying ? 0.0 : 0.005,
                            duration: context.motionMs(420),
                            curve: context.motionCurve(Curves.easeOutCubic),
                            child: AnimatedSlide(
                              offset: Offset(0, isPlaying ? -0.014 : 0.0),
                              duration: context.motionMs(420),
                              curve: context.motionCurve(Curves.easeOutCubic),
                              child: AnimatedContainer(
                                duration: context.motionMs(420),
                                curve: context.motionCurve(Curves.easeOutCubic),
                                width: sleeveSize,
                                height: sleeveSize,
                                decoration: BoxDecoration(
                                  borderRadius: sleeveCorners,
                                  border: Border.all(
                                    color: Colors.white.withValues(
                                      alpha: isDark ? 0.18 : 0.34,
                                    ),
                                    width: 1.2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.scrimAt(
                                        isDark
                                            ? (isPlaying ? 0.62 : 0.46)
                                            : (isPlaying ? 0.24 : 0.16),
                                      ),
                                      blurRadius: isPlaying ? 40 : 24,
                                      spreadRadius: isPlaying ? 4 : 1,
                                      offset: Offset(0, isPlaying ? 20 : 12),
                                    ),
                                    BoxShadow(
                                      color: activeColor.withValues(
                                        alpha: isPlaying ? 0.30 : 0.16,
                                      ),
                                      blurRadius: 24,
                                      spreadRadius: -4,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: sleeveCorners,
                                  child: Hero(
                                    tag: props.heroTag,
                                    child: PlayerArtworkSemantics(
                                      song: song,
                                      child: song != null
                                          ? CachedArtwork(
                                              id: song.id,
                                              albumId: song.albumId,
                                              remoteUrl:
                                                  song.remoteArtworkUrl ??
                                                      song.artworkUri,
                                              type: ArtworkType.AUDIO,
                                              size: double.infinity,
                                              borderRadius: sleeveRadius,
                                              highQuality: true,
                                            )
                                          : Container(
                                              decoration: BoxDecoration(
                                                color: p.surfaceContainer,
                                                borderRadius: sleeveCorners,
                                              ),
                                              child: Icon(
                                                Icons.music_note_rounded,
                                                size: 96,
                                                color: textSubtitleColor
                                                    .withValues(alpha: 0.4),
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (showVisualizer) visualizer,
              ],
            );
          },
        ),
      ),
      chrome: (context, metrics) => Container(
        decoration: BoxDecoration(
          borderRadius: sleeveCorners,
          color: p.playerCard,
          border: Border.all(
            color: p.hairline,
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.s10),
        child: PlayerControlsColumn(
          props: props,
          isTablet: metrics.isTablet,
          isLandscape: metrics.isLandscape,
          isInSplitView: PlayerSplitViewScope.of(context),
          heightRatio: metrics.heightRatio,
          metrics: metrics,
          trackHeader: PlayerTrackHeader(
            props: props,
            isTablet: metrics.isTablet,
            metrics: metrics,
            horizontalPadding: 0,
            tabletHorizontalPadding: 0,
            verticalPadding: 0,
            titleColor: textTitleColor,
            subtitleColor: textSubtitleColor,
            titleArtistGap: AppSpacing.s2,
          ),
          scaleMainButtonByHeight: true,
          dense: true,
          dock: PlayerBottomActionDock(
            props: props,
            isTablet: metrics.isTablet,
            barWidth: metrics.pillBarWidth,
            barHeight: metrics.dockBarHeight,
            disableBlur: true,
          ),
        ),
      ),
    );
  }
}
