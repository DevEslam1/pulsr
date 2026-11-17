part of '../clean_player_theme.dart';

/// The upper stage: full-bleed artwork, lyrics or queue.
///
/// The artwork variant is Clean's signature — edge-to-edge cover art that
/// dissolves into the deck colour — so it lives on its own instead of swelling
/// the layout composition in [CleanPlayerTheme].
class _CleanUpperStage extends StatelessWidget {
  final PlayerThemeProps props;
  final bool isInSplitView;
  final bool isLandscape;
  final bool canvasEnabled;
  final bool canvasAsBackdrop;
  final Color fadeColor;
  final double fallbackWidth;

  const _CleanUpperStage({
    required this.props,
    required this.isInSplitView,
    required this.isLandscape,
    required this.canvasEnabled,
    required this.canvasAsBackdrop,
    required this.fadeColor,
    required this.fallbackWidth,
  });

  @override
  Widget build(BuildContext context) {
    final state = props.state;
    final activeColor = props.activeColor;
    final song = state.currentSong;

    // In tablet split-view the right pane is dedicated to lyrics / queue / DSP,
    // so the left deck must ALWAYS display the showcase artwork and never an
    // inline lyrics or queue overlay.
    if (!isInSplitView && state.isLyricsVisible) {
      return KeyedSubtree(
        key: const ValueKey('lyrics_stage'),
        child: SafeArea(
          top: true,
          bottom: false,
          child: SizedBox.expand(
            child: LyricsView(
              key: ValueKey('lyrics_${song?.id}_${song?.remoteId}'),
              lyrics: state.lyrics,
              isLoading: state.isLoadingLyrics,
              activeColor: activeColor,
              source: state.lyricsSource,
              transparentBackground: true,
            ),
          ),
        ),
      );
    }

    if (!isInSplitView && state.isQueueVisible) {
      return KeyedSubtree(
        key: const ValueKey('queue_stage'),
        child: SafeArea(
          top: true,
          bottom: false,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(
              top: AppSpacing.sm,
              start: AppSpacing.md,
              end: AppSpacing.md,
              bottom: AppSpacing.xs,
            ),
            child: const SizedBox.expand(
              child: NowPlayingQueueView(key: ValueKey('queue_view')),
            ),
          ),
        ),
      );
    }

    return KeyedSubtree(
      key: const ValueKey('art_stage'),
      child: PlayerGestureScope(
        child: LayoutBuilder(
          builder: (context, stageConstraints) {
            // Sizes come directly from the rendered stage bounds so landscape
            // split panes fill edge-to-edge into the camera cutout & corners
            // without shrinking or letterboxing.
            final stageW =
                stageConstraints.maxWidth.isFinite && stageConstraints.maxWidth > 0
                    ? stageConstraints.maxWidth
                    : fallbackWidth;
            final stageH = stageConstraints.maxHeight.isFinite &&
                    stageConstraints.maxHeight > 0
                ? stageConstraints.maxHeight
                : stageW;
            final artworkSize = math.max(stageW, stageH).clamp(360.0, 1080.0);
            final useLandscapeFade = isLandscape && !isInSplitView;
            final artAlignment =
                useLandscapeFade ? Alignment.center : Alignment.topCenter;

            final fallbackArt = CachedArtwork(
              id: song?.id ?? 0,
              albumId: song?.albumId,
              remoteUrl: song?.remoteArtworkUrl ?? song?.artworkUri,
              type: ArtworkType.AUDIO,
              size: artworkSize,
              highQuality: true,
              borderRadius: 0,
              alignment: artAlignment,
            );

            final Widget artworkChild = PlayerArtworkSemantics(
              song: song,
              child: (canvasEnabled && !canvasAsBackdrop && song != null)
                  ? CanvasBackdrop(
                      song: song,
                      isPlaying: state.isPlaying,
                      isBackdropMode: false,
                      borderRadius: BorderRadius.zero,
                      fallbackArtwork: fallbackArt,
                    )
                  : fallbackArt,
            );

            final Widget heroArt = RepaintBoundary(
              child: Hero(
                tag: props.heroTag,
                child: SizedBox(
                  width: stageW,
                  height: stageH,
                  child: artworkChild,
                ),
              ),
            );

            if (useLandscapeFade) {
              final textDirection = Directionality.of(context);
              return ShaderMask(
                blendMode: BlendMode.dstIn,
                // White here is a mask channel (BlendMode.dstIn keeps pixels in
                // proportion to its alpha), never a painted foreground colour.
                shaderCallback: (bounds) => LinearGradient(
                  begin: AlignmentDirectional.centerStart,
                  end: AlignmentDirectional.centerEnd,
                  colors: const [
                    Colors.white,
                    Colors.white,
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.68, 1.0],
                ).createShader(bounds, textDirection: textDirection),
                child: heroArt,
              );
            }

            return Stack(
              fit: StackFit.expand,
              children: [
                heroArt,
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.transparent,
                            fadeColor.withValues(alpha: 0.18),
                            fadeColor.withValues(alpha: 0.65),
                            fadeColor,
                          ],
                          stops: const [0.0, 0.52, 0.70, 0.88, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
