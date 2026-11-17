part of '../minimal_player_theme.dart';

extension _MinimalPlayerThemeBuild on MinimalPlayerTheme {
  Widget _buildBody(BuildContext context) {
    final state = props.state;
    final activeColor = props.activeColor;
    final song = state.currentSong;
    // Only the visualizer switch is read here. Selecting the wider settings
    // record also rebuilt this theme whenever the waveform-seek or slider-style
    // preferences changed, neither of which the stage paints.
    final visualizerStyle = context
        .select<SettingsCubit, VisualizerStyle>((c) => c.state.visualizerStyle);

    final showVisualizer = visualizerStyle != VisualizerStyle.off &&
        !state.isLyricsVisible &&
        !state.isQueueVisible &&
        !PlayerSplitViewScope.of(context);

    return PlayerThemeScaffold(
      props: props,
      trackIcon: Icons.album_rounded,
      dockIconStyle: PlayerDockIconStyle.minimal,
      background: DecoratedBox(
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
      ),
      stage: (context, metrics) => PlayerGestureScope(
        child: LayoutBuilder(
          builder: (context, artConstraints) {
            final visualizerSpace = showVisualizer
                ? math.min(artConstraints.maxHeight,
                    visualizerStyle == VisualizerStyle.circular ? 70.0 : 46.0)
                : 0.0;
            // The cover yields to the read-out instead of the two guessing at
            // each other's height: the spec HUD is laid out at its real wrapped
            // height (three lines on a 320 dp stage at 200% text) and the cover
            // takes whatever the stage has left. Reserving a flat `50 * scale`
            // was 17 px short on exactly that case and overflowed the stage.
            final double artworkCap = metrics.isLandscape
                ? 280.0
                : (metrics.isTablet ? 600.0 : 480.0);
            return Column(
              key: const ValueKey('minimal_art_display'),
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  // The cover keeps most of the stage when there is room; the
                  // visualizer only ever gets a fifth of the leftover space.
                  flex: 4,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: artworkCap,
                        maxHeight: artworkCap,
                      ),
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
                                  color: activeColor.withValues(alpha: 0.25),
                                  blurRadius: 28,
                                  spreadRadius: 1,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
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
                  ),
                ),
                _MinimalAudiophileTelemetry(
                  song: song,
                  activeColor: activeColor,
                  // The HUD may use the full stage width so the spec row stays
                  // on one or two lines at 200% text instead of stacking.
                  maxWidth: math.min(artConstraints.maxWidth, 420.0),
                ),
                // Flexible, like the cover: the visualizer is decoration and
                // must yield the same way when a 200% text scale leaves the
                // stage too short for the read-out. Its height comes from the
                // space it is actually given, not from the stage estimate.
                if (showVisualizer)
                  Flexible(
                    child: LayoutBuilder(
                      builder: (context, vizConstraints) {
                        final double gap = math.min(10.0, visualizerSpace);
                        final double height =
                            math.max(0.0, vizConstraints.maxHeight - gap);
                        if (height <= 0) return const SizedBox.shrink();
                        return Padding(
                          padding: EdgeInsets.only(top: gap),
                          child: AudioVisualizer(
                            style: visualizerStyle,
                            color: activeColor,
                            height: height,
                            isPlaying: state.isPlaying,
                            audioSessionId: state.audioSessionId,
                            trackSeed: song?.id,
                          ),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
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
          alignStart: true,
        ),
        scaleMainButtonByHeight: true,
        dock: PlayerBottomActionDock(
          props: props,
          isTablet: metrics.isTablet,
          barWidth: metrics.pillBarWidth,
          barHeight: metrics.dockBarHeight,
          dockIconStyle: PlayerDockIconStyle.minimal,
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
  final double maxWidth;

  const _MinimalAudiophileTelemetry({
    required this.song,
    required this.activeColor,
    required this.maxWidth,
  });

  /// Specs come from decoded file headers only.
  ///
  /// This widget used to fall back to '44.1 kHz' / '16-BIT' / 'PCM' whenever a
  /// track had not been enriched yet, printing an invented spec in an app whose
  /// promise is bit-perfect provenance. Missing fields are omitted now, and the
  /// file extension is deliberately not used as a codec either: a renamed file
  /// can claim any format, so only the header value counts.
  static List<({String label, bool isFormat})> _specsFor(SongsTableData? song) {
    if (song == null) return const [];
    final specs = <({String label, bool isFormat})>[];

    final codec = song.codec?.trim();
    if (codec != null && codec.isNotEmpty) {
      specs.add((label: codec.toUpperCase(), isFormat: true));
    }

    final sampleRate = song.sampleRate;
    if (sampleRate != null && sampleRate > 0) {
      // Non-breaking space keeps the value and its unit on one line when the
      // row wraps at large text scales.
      specs.add((
        label: '${(sampleRate / 1000).toStringAsFixed(1)}\u00A0kHz',
        isFormat: false,
      ));
    }

    final bitDepth = song.bitDepth;
    if (bitDepth != null && bitDepth > 0) {
      specs.add((label: '$bitDepth-BIT', isFormat: false));
    }

    final bitrateKbps = song.bitrateKbps;
    if (bitrateKbps != null && bitrateKbps > 0) {
      specs.add((label: '$bitrateKbps\u00A0kbps', isFormat: false));
    }

    return specs;
  }

  @override
  Widget build(BuildContext context) {
    final specs = _specsFor(song);
    if (specs.isEmpty) return const SizedBox.shrink();

    final p = context.palette;
    final textStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: AppFontSize.caption,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.6,
      height: 1.45,
    );

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
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
        // One wrapping paragraph instead of a fixed Row: the old
        // withNoTextScaling + FittedBox pair kept the type at 100% no matter
        // what the listener asked for, which is exactly the dishonesty this HUD
        // was meant to avoid. A paragraph wraps at any scale, keeps the
        // monospace letter-spaced look, and never clips a spec.
        child: Text.rich(
          TextSpan(
            children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: _buildStatusDot(),
              ),
              for (int i = 0; i < specs.length; i++) ...[
                if (i > 0)
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: _buildDivider(p.hairline),
                  ),
                TextSpan(
                  text: specs[i].label,
                  style: textStyle.copyWith(
                    color: specs[i].isFormat ? activeColor : p.textSecondary,
                  ),
                ),
              ],
            ],
          ),
          textAlign: TextAlign.center,
          style: textStyle,
        ),
      ),
    );
  }

  Widget _buildStatusDot() {
    return Container(
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
