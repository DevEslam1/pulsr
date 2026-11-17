part of '../lyrics_player_theme.dart';

extension _LyricsPlayerThemeBuild on LyricsPlayerTheme {
  Widget _buildBody(BuildContext context) {
    final state = props.state;
    final activeColor = props.activeColor;
    final song = state.currentSong;
    final isPlaying = state.isPlaying;
    final visualizerStyle = context
        .select<SettingsCubit, VisualizerStyle>((c) => c.state.visualizerStyle);

    // Only timed lyrics can drive a live window: an untimed sheet has no
    // "current line", and highlighting the first one as if it were singing
    // would be a lie. Without timing the stage degrades to the artwork alone.
    final bool hasTimedLyrics =
        state.lyrics.any((line) => line.timestamp > Duration.zero);

    // One corner value for the plate, its clip and the artwork.
    final double artRadius = resolveCustomRadius(context, 20);
    final BorderRadius artCorners = AppRadii.circular(artRadius);

    final extraBadge = Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s6, vertical: AppSpacing.s2),
      decoration: BoxDecoration(
        color: activeColor.withValues(alpha: 0.18),
        borderRadius: AppRadii.r6All,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mic_rounded, size: 11, color: activeColor),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            context.l10n.lyrics,
            style: TextStyle(
              fontSize: AppFontSize.caption,
              fontWeight: FontWeight.w900,
              letterSpacing: AppTracking.overline,
              color: activeColor,
            ),
          ),
        ],
      ),
    );

    return PlayerThemeScaffold(
      props: props,
      trackIcon: Icons.lyrics_rounded,
      dockIconStyle: PlayerDockIconStyle.lyricsFocus,
      // No onTap override: single tap stays bound to lyrics through the shared
      // gesture scope, exactly like the other themes.
      stage: (context, metrics) => PlayerGestureScope(
        child: Center(
          key: const ValueKey('track_art_lyrics_focus'),
          child: LayoutBuilder(
            builder: (context, artConstraints) {
              final bool isSplit = PlayerSplitViewScope.of(context);
              final bool visualizerAllowed =
                  visualizerStyle != VisualizerStyle.off &&
                      !isSplit &&
                      !state.isQueueVisible;
              final double visualizerH =
                  visualizerStyle == VisualizerStyle.circular ? 60.0 : 34.0;
              final double visualizerReserve =
                  visualizerAllowed ? visualizerH + AppSpacing.xs : 0.0;

              final int previewLineCount = metrics.isVeryShortHeight
                  ? 1
                  : (metrics.isShortHeight ? 2 : 3);
              final double naturalPreview =
                  _lyricPreviewHeight(context, previewLineCount);
              // The window may never eat more than a third of the stage: the
              // cover still has to read as the cover on a small phone.
              final double previewHeight =
                  math.min(naturalPreview, artConstraints.maxHeight * 0.34);
              final double previewReserve = previewHeight + AppSpacing.md;

              double measure(double reserved) {
                final double availableWidth = artConstraints.maxWidth -
                    (metrics.isTablet ? 64.0 : 36.0);
                final double availableHeight = math.max(
                  0.0,
                  artConstraints.maxHeight -
                      (metrics.isTablet ? 24.0 : 12.0) -
                      reserved,
                );
                final double maxAllowed = metrics.isLandscape
                    ? 280.0
                    : (metrics.isTablet ? 560.0 : 420.0);
                final double raw =
                    math.min(availableWidth, availableHeight);
                return raw <= 0 ? 0.0 : math.min(raw, maxAllowed);
              }

              final bool previewWanted = hasTimedLyrics && !isSplit;
              double artSize =
                  measure(previewWanted ? previewReserve : visualizerReserve);
              // A lyric window over a postage-stamp cover is worse than the
              // plain stage, so the preview is the thing that yields when the
              // screen cannot hold both.
              final bool showPreview = previewWanted && artSize >= 120.0;
              if (previewWanted && !showPreview) {
                artSize = measure(visualizerReserve);
              }
              // The preview and the visualizer share the single slot under the
              // cover: the words are the theme's signature, the visualizer is
              // decoration and steps aside for them.
              final bool showVisualizer = visualizerAllowed && !showPreview;
              if (artSize <= 0) return const SizedBox.shrink();

              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: artSize,
                      maxWidth: artSize,
                    ),
                    child: AspectRatio(
                      aspectRatio: 1.0,
                      child: Hero(
                        tag: props.heroTag,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: artCorners,
                            boxShadow: [
                              BoxShadow(
                                color: activeColor.withValues(
                                  alpha: isPlaying ? 0.34 : 0.18,
                                ),
                                blurRadius: 34,
                                spreadRadius: 1,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: artCorners,
                            child: PlayerArtworkSemantics(
                              song: song,
                              child: song != null
                                  ? CachedArtwork(
                                      id: song.id,
                                      albumId: song.albumId,
                                      remoteUrl: song.remoteArtworkUrl ??
                                          song.artworkUri,
                                      type: ArtworkType.AUDIO,
                                      size: double.infinity,
                                      borderRadius: artRadius,
                                      highQuality: true,
                                    )
                                  : const SizedBox.shrink(),
                            ),
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
                            horizontal: AppSpacing.lg,
                            vertical: AppSpacing.xxs),
                        child: AudioVisualizer(
                          style: visualizerStyle,
                          color: activeColor,
                          height: visualizerH,
                          isPlaying: isPlaying,
                          audioSessionId: state.audioSessionId,
                          trackSeed: song?.id,
                        ),
                      ),
                    ),
                  if (showPreview) ...[
                    SizedBox(height: AppSpacing.md),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 380),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                        ),
                        child: _LyricsPreviewHost(
                          lines: state.lyrics,
                          activeColor: activeColor,
                          height: previewHeight,
                          lineCount: previewLineCount,
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
      chrome: (context, metrics) => PlayerControlsColumn(
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
          extraBadge: extraBadge,
        ),
        scaleMainButtonByHeight: true,
        dock: PlayerBottomActionDock(
          props: props,
          isTablet: metrics.isTablet,
          barWidth: metrics.pillBarWidth,
          barHeight: metrics.dockBarHeight,
          dockIconStyle: PlayerDockIconStyle.lyricsFocus,
        ),
      ),
    );
  }
}

/// Natural height of the lyric window at the user's text scale, so the rows
/// keep their share of the stage when the system font doubles.
double _lyricPreviewHeight(BuildContext context, int lineCount) {
  final TextScaler scaler = MediaQuery.textScalerOf(context);
  final double active = scaler.scale(AppFontSize.callout) * 1.3;
  final double neighbour = scaler.scale(AppFontSize.bodySmall) * 1.3;
  return active + neighbour * (lineCount - 1) + AppSpacing.xs * (lineCount + 1);
}

/// Index of the lyric line sounding at [position], or -1 while the track is
/// still in its intro (before the first timestamp).
///
/// Binary search rather than a linear scan: this runs inside the preview's
/// selector for every position tick and real sheets carry hundreds of lines.
int _activeLyricLineIndex(List<LyricsLine> lines, Duration position) {
  if (lines.isEmpty) return -1;
  final int positionMs = position.inMilliseconds;
  int low = 0;
  int high = lines.length - 1;
  int active = -1;
  while (low <= high) {
    final int mid = (low + high) >> 1;
    if (lines[mid].timestamp.inMilliseconds <= positionMs) {
      active = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return active;
}

/// Binds the lyric window to the *active line index* only.
///
/// A `BlocSelector` that returns the index means 10 Hz position ticks rebuild
/// this strip exclusively — and only when the singing line actually changes —
/// instead of rebuilding the cover, chrome and transport every second.
class _LyricsPreviewHost extends StatefulWidget {
  final List<LyricsLine> lines;
  final Color activeColor;
  final double height;
  final int lineCount;

  const _LyricsPreviewHost({
    required this.lines,
    required this.activeColor,
    required this.height,
    required this.lineCount,
  });

  @override
  State<_LyricsPreviewHost> createState() => _LyricsPreviewHostState();
}

class _LyricsPreviewHostState extends State<_LyricsPreviewHost> {
  /// Sheet order, made monotonic once per lyrics list.
  ///
  /// LRC files written by hand or exported by converters routinely arrive out
  /// of order, and a binary search over an unsorted sheet does not fail — it
  /// silently highlights the wrong line for the rest of the track. Sorting in
  /// `didUpdateWidget` keeps that repair off the 10 Hz position path: the
  /// selector below only ever searches an already-ordered list.
  late List<LyricsLine> _sorted;

  @override
  void initState() {
    super.initState();
    _sorted = _orderedLines(widget.lines);
  }

  @override
  void didUpdateWidget(covariant _LyricsPreviewHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.lines, widget.lines)) {
      _sorted = _orderedLines(widget.lines);
    }
  }

  /// Returns [lines] untouched when it is already in order, so the common case
  /// costs one linear pass and no allocation.
  static List<LyricsLine> _orderedLines(List<LyricsLine> lines) {
    for (var i = 1; i < lines.length; i++) {
      if (lines[i].timestamp < lines[i - 1].timestamp) {
        return List<LyricsLine>.of(lines)
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      }
    }
    return lines;
  }

  @override
  Widget build(BuildContext context) {
    return BlocSelector<PlayerCubit, PlayerState, int>(
      selector: (s) => _activeLyricLineIndex(_sorted, s.position),
      builder: (context, activeIndex) => _LyricsPreviewLines(
        lines: _sorted,
        activeIndex: activeIndex,
        activeColor: widget.activeColor,
        height: widget.height,
        lineCount: widget.lineCount,
      ),
    );
  }
}

/// Previous / current / next line under the cover, the current one in the
/// accent colour and its neighbours dimmed.
class _LyricsPreviewLines extends StatelessWidget {
  final List<LyricsLine> lines;
  final int activeIndex;
  final Color activeColor;
  final double height;
  final int lineCount;

  const _LyricsPreviewLines({
    required this.lines,
    required this.activeIndex,
    required this.activeColor,
    required this.height,
    required this.lineCount,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (lines.isEmpty) return const SizedBox.shrink();

    final int lastIndex = lines.length - 1;
    final int safeActive = activeIndex < 0
        ? -1
        : (activeIndex > lastIndex ? lastIndex : activeIndex);
    // Before the first timestamp the window opens on the opening lines with
    // nothing highlighted yet, instead of pretending line one is singing.
    final int start =
        safeActive < 0 ? 0 : math.max(0, safeActive - (lineCount >= 3 ? 1 : 0));
    final int end = math.min(lines.length, start + lineCount);

    return SizedBox(
      height: height,
      // Each row gets an equal slice of the reserved height, so a 2.0 text
      // scale with a long line can only ellipsise inside its slice instead of
      // pushing the transport off-screen.
      child: ClipRect(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (int i = start; i < end; i++)
              Expanded(
                child: Align(
                  alignment: Alignment.center,
                  child: Text(
                    lines[i].text.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: i == safeActive
                          ? AppFontSize.callout
                          : AppFontSize.bodySmall,
                      fontWeight:
                          i == safeActive ? FontWeight.w800 : FontWeight.w600,
                      height: 1.3,
                      color: i == safeActive ? activeColor : p.textTertiary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
