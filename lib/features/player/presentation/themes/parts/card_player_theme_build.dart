part of '../card_player_theme.dart';

extension _CardPlayerThemeBuild on CardPlayerTheme {
  Widget _buildBody(BuildContext context) {
    final p = context.palette;
    final state = props.state;
    final cubit = props.cubit;
    final activeColor = props.activeColor;
    final song = state.currentSong;
    final isPlaying = state.isPlaying;
    final isDark = p.isDark;

    final (
      :visualizerStyle,
      :outputDevice,
    ) = context.select<
        SettingsCubit,
        ({
          VisualizerStyle visualizerStyle,
          Object? outputDevice,
        })>((c) => (
          visualizerStyle: c.state.visualizerStyle,
          outputDevice: c.state.currentOutputDevice,
        ));

    final settingsSnapshot = context.read<SettingsCubit>().state;
    final telemetry = formatPlayerAudioTelemetry(song, settingsSnapshot);
    final double cardRadius = resolveCustomRadius(context, AppRadii.r24);
    final bool customGlow = resolveCustomGlow(context);
    final textScale =
        MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 2.0);

    final Color topBarSurface = isDark
        ? AppColors.scrimAt(0.30)
        : p.surface.withValues(alpha: 0.72);
    final Color topBarBorder =
        isDark ? AppColors.specularAt(0.18) : p.hairline;

    return PlayerSurfaceShell(
      props: props,
      background: _SpatialBlurredCanvas(
        song: song,
        isPlaying: isPlaying,
        activeColor: activeColor,
        bgColor: props.bgColor,
      ),
      topBarBuilder: (context, metrics) => PlayerCompactTopBar(
        foregroundColor: p.textPrimary,
        buttonSurfaceColor: topBarSurface,
        buttonBorderColor: topBarBorder,
        blurSigma: AppBlur.chip,
        center: _SpatialTopPill(
          song: song,
          telemetry: telemetry,
          activeColor: activeColor,
          surfaceColor: topBarSurface,
          borderColor: topBarBorder,
        ),
        trailing: [
          PlayerIconActionButton(
            icon: Icons.more_horiz_rounded,
            tooltip: context.l10n.moreOptions,
            iconColor: p.textPrimary,
            surfaceColor: topBarSurface,
            borderColor: topBarBorder,
            blurSigma: AppBlur.chip,
            onTap: song == null
                ? null
                : () {
                    PulsrHaptics.lightImpact();
                    SongOptionsSheet.show(context, song: song);
                  },
          ),
        ],
      ),
      builder: (context, metrics, isInSplitView, isPreview) {
        final constraints = metrics.constraints;
        final isLandscape = metrics.isLandscape && !isInSplitView;
        final isShort = metrics.isShortHeight ||
            isPreview ||
            (isInSplitView && constraints.maxHeight < 560);
        final isVeryShort = metrics.isVeryShortHeight ||
            (isInSplitView && constraints.maxHeight < 470);

        final showVisualizer = !isPreview &&
            visualizerStyle != VisualizerStyle.off &&
            !state.isLyricsVisible &&
            !state.isQueueVisible &&
            !isInSplitView &&
            !isVeryShort;

        final Widget? visualizerWidget = showVisualizer
            ? Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: AppSpacing.lg,
                  end: AppSpacing.lg,
                  top: AppSpacing.xs,
                ),
                child: AudioVisualizer(
                  style: visualizerStyle,
                  color: activeColor,
                  height: visualizerStyle == VisualizerStyle.circular ? 52 : 30,
                  isPlaying: isPlaying,
                  audioSessionId: state.audioSessionId,
                  trackSeed: song?.id,
                ),
              )
            : null;

        final Widget cardDeck = _SpatialCardDeck(
          props: props,
          metrics: metrics,
          cardRadius: cardRadius,
          customGlow: customGlow,
          isPreview: isPreview,
        );

        final Widget controlCard = _SpatialGlassControlCard(
          props: props,
          metrics: metrics,
          cardRadius: cardRadius,
          isCompact: isShort,
          isVeryShort: isVeryShort,
          isInSplitView: isInSplitView,
          isPreview: isPreview,
        );

        final Widget? volumeBar = (!isPreview &&
                (isInSplitView || context.isTablet) &&
                !isVeryShort)
            ? Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: AppSpacing.md,
                  end: AppSpacing.md,
                  bottom: AppSpacing.xs,
                ),
                child: PlayerVolumeBar(
                  cubit: cubit,
                  activeColor: activeColor,
                ),
              )
            : null;

        final double horizontalInset =
            (constraints.maxWidth * 0.045).clamp(12.0, 24.0);

        // Landscape single-pane layout: stacked card deck on start, floating
        // spatial glass control card on end.
        if (isLandscape) {
          return SafeArea(
            top: !isPreview,
            bottom: !isPreview,
            left: !isPreview,
            right: !isPreview,
            child: Padding(
              padding: EdgeInsetsDirectional.only(
                top: isPreview ? AppSpacing.xs : AppSpacing.xxl + AppSpacing.xs,
                bottom: AppSpacing.sm,
                start: AppSpacing.md,
                end: AppSpacing.md,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 5,
                    child: Center(child: cardDeck),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    flex: 5,
                    child: Center(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (volumeBar != null) volumeBar,
                            controlCard,
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // Scroll fallback for very short portrait screens or 200% text scaling
        // so the glass card and deck never trigger RenderFlex overflow.
        final double portraitScrollThreshold =
            570.0 + (textScale - 1.0) * 125.0;
        if (!isPreview &&
            !isInSplitView &&
            constraints.maxHeight < portraitScrollThreshold) {
          final double boundedDeckH =
              (constraints.maxHeight * 0.36).clamp(155.0, 260.0);
          return SafeArea(
            top: true,
            bottom: true,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: EdgeInsetsDirectional.fromSTEB(
                  horizontalInset,
                  AppSpacing.xxl + AppSpacing.sm,
                  horizontalInset,
                  AppSpacing.md,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: boundedDeckH,
                      width: double.infinity,
                      child: cardDeck,
                    ),
                    if (visualizerWidget != null) visualizerWidget,
                    const SizedBox(height: AppSpacing.sm),
                    if (volumeBar != null) volumeBar,
                    controlCard,
                  ],
                ),
              ),
            ),
          );
        }

        // Standard Portrait / Tablet Split-View / Mini-Preview composition.
        return Column(
          children: [
            if (!isInSplitView && !isPreview)
              const SafeArea(
                top: true,
                bottom: false,
                child: SizedBox(height: AppSpacing.xxl + AppSpacing.xs),
              )
            else
              const SizedBox(height: AppSpacing.xs),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalInset),
                child: cardDeck,
              ),
            ),
            if (visualizerWidget != null) visualizerWidget,
            SizedBox(height: isShort ? AppSpacing.xs : AppSpacing.sm),
            if (volumeBar != null) volumeBar,
            SafeArea(
              top: false,
              bottom: !isPreview && !isInSplitView,
              child: Padding(
                padding: EdgeInsetsDirectional.fromSTEB(
                  horizontalInset,
                  0,
                  horizontalInset,
                  isShort ? AppSpacing.xs : AppSpacing.md,
                ),
                child: RepaintBoundary(child: controlCard),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Full-screen live blurred artwork backdrop for Card Glass Overlay.
///
/// Always fills 100% of the viewport. Strictly gates [ImageFilter.blur] behind
/// [AppBlur.canBlur] and [AppBlur.clampSigma], substituting a lush multi-stop
/// blurred-feel gradient wash when blur is disabled (GPU Saver / High Contrast).
class _SpatialBlurredCanvas extends StatelessWidget {
  final SongsTableData? song;
  final bool isPlaying;
  final Color activeColor;
  final Color bgColor;

  const _SpatialBlurredCanvas({
    required this.song,
    required this.isPlaying,
    required this.activeColor,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isDark = p.isDark;
    final canBlur = AppBlur.canBlur(context);
    final double sigma = AppBlur.clampSigma(AppBlur.maxSigma);

    final hsl = HSLColor.fromColor(activeColor);
    final accentLift = hsl
        .withHue((hsl.hue + 28.0) % 360.0)
        .withSaturation((hsl.saturation * 0.88).clamp(0.28, 0.92))
        .toColor();

    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: bgColor),

          // Live artwork / canvas layer filling 100% viewport.
          if (song != null)
            ClipRect(
              child: Transform.scale(
                scale: canBlur ? 1.24 : 1.08,
                child: canBlur && sigma > 0.0
                    ? ImageFiltered(
                        imageFilter: ImageFilter.blur(
                          sigmaX: sigma,
                          sigmaY: sigma,
                          tileMode: TileMode.mirror,
                        ),
                        child: CanvasBackdrop(
                          song: song!,
                          isPlaying: isPlaying,
                          isBackdropMode: true,
                          fallbackArtwork: CachedArtwork(
                            id: song!.id,
                            albumId: song!.albumId,
                            remoteUrl:
                                song!.remoteArtworkUrl ?? song!.artworkUri,
                            type: ArtworkType.AUDIO,
                            size: double.infinity,
                            highQuality: false,
                          ),
                        ),
                      )
                    : Opacity(
                        opacity: isDark ? 0.28 : 0.20,
                        child: CachedArtwork(
                          id: song!.id,
                          albumId: song!.albumId,
                          remoteUrl: song!.remoteArtworkUrl ?? song!.artworkUri,
                          type: ArtworkType.AUDIO,
                          size: double.infinity,
                          highQuality: false,
                        ),
                      ),
              ),
            ),

          // Blurred-feel tinted atmospheric gradient (essential when blur is
          // disabled, and deepens spatial tone when blur is active).
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.65, -0.55),
                radius: 1.15,
                colors: [
                  activeColor.withValues(
                    alpha: canBlur
                        ? (isDark ? 0.22 : 0.14)
                        : (isDark ? 0.36 : 0.20),
                  ),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.75, 0.45),
                radius: 1.1,
                colors: [
                  accentLift.withValues(
                    alpha: canBlur
                        ? (isDark ? 0.18 : 0.10)
                        : (isDark ? 0.28 : 0.16),
                  ),
                  Colors.transparent,
                ],
              ),
            ),
          ),

          // Vertical legibility gradient protecting both top chrome and glass card.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isDark
                    ? [
                        AppColors.scrimAt(canBlur ? 0.38 : 0.56),
                        AppColors.scrimAt(canBlur ? 0.48 : 0.68),
                        AppColors.scrimAt(canBlur ? 0.80 : 0.90),
                      ]
                    : [
                        p.bg.withValues(alpha: canBlur ? 0.44 : 0.72),
                        p.bg.withValues(alpha: canBlur ? 0.58 : 0.82),
                        p.bg.withValues(alpha: canBlur ? 0.86 : 0.94),
                      ],
                stops: const [0.0, 0.48, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Frosted glass top pill showing compact audio telemetry or album name.
class _SpatialTopPill extends StatelessWidget {
  final SongsTableData? song;
  final PlayerAudioTelemetry telemetry;
  final Color activeColor;
  final Color surfaceColor;
  final Color borderColor;

  const _SpatialTopPill({
    required this.song,
    required this.telemetry,
    required this.activeColor,
    required this.surfaceColor,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final String label = telemetry.compactBadge.isNotEmpty
        ? telemetry.compactBadge
        : (song?.album.trim().isNotEmpty == true
            ? song!.album
            : context.l10n.nowPlaying);

    final bool canOpenQuality = song != null;
    final canBlur = AppBlur.canBlur(context);
    final double sigma = AppBlur.clampSigma(AppBlur.chip);

    Widget pill = Material(
      color: surfaceColor,
      shape: StadiumBorder(side: BorderSide(color: borderColor, width: 1.0)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: canOpenQuality
            ? () {
                PulsrHaptics.selectionClick();
                AudioQualitySheet.show(context, song!, activeColor);
              }
            : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppSpacing.minTouchTarget,
            maxWidth: 220,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s12,
              vertical: AppSpacing.s6,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (telemetry.isHiRes || telemetry.isLossless) ...[
                  Icon(
                    Icons.graphic_eq_rounded,
                    size: 14,
                    color: telemetry.isHiRes ? AppColors.dacGold : activeColor,
                  ),
                  const SizedBox(width: AppSpacing.s4),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppFontSize.caption,
                      fontWeight: FontWeight.w700,
                      letterSpacing: AppTracking.label,
                      color: p.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (canBlur && sigma > 0.0) {
      pill = ClipRRect(
        borderRadius: AppRadii.full,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: pill,
        ),
      );
    }

    return Semantics(
      button: canOpenQuality,
      label: canOpenQuality ? '${context.l10n.audioQuality}: $label' : label,
      excludeSemantics: true,
      child: pill,
    );
  }
}

/// Interactive swipeable stacked album card deck powered by
/// [resolveQueueNeighbors].
///
/// Renders peeking previous (left) and next (right) track cards behind the
/// active center card. Horizontal drag translates and tilts the active card
/// while smoothly revealing the target neighbor, snapping back with a spring
/// curve or committing `cubit.next()` / `cubit.previous()` past threshold.
class _SpatialCardDeck extends StatefulWidget {
  final PlayerThemeProps props;
  final PlayerThemeMetrics metrics;
  final double cardRadius;
  final bool customGlow;
  final bool isPreview;

  const _SpatialCardDeck({
    required this.props,
    required this.metrics,
    required this.cardRadius,
    required this.customGlow,
    required this.isPreview,
  });

  @override
  State<_SpatialCardDeck> createState() => _SpatialCardDeckState();
}

class _SpatialCardDeckState extends State<_SpatialCardDeck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _snapController;
  Animation<double>? _snapAnimation;
  double _dragDx = 0.0;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    )..addListener(() {
        final anim = _snapAnimation;
        if (anim != null && mounted) {
          setState(() => _dragDx = anim.value);
        }
      });
  }

  @override
  void didUpdateWidget(covariant _SpatialCardDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.props.state.currentSong?.id !=
        oldWidget.props.state.currentSong?.id) {
      _snapController.stop();
      _dragDx = 0.0;
      _isDragging = false;
    }
  }

  @override
  void dispose() {
    _snapController.dispose();
    super.dispose();
  }

  void _animateBackToCenter() {
    if (!mounted) return;
    if (!context.motionEnabled || widget.isPreview) {
      setState(() {
        _dragDx = 0.0;
        _isDragging = false;
      });
      return;
    }
    _snapController.duration = context.motionMs(320);
    _snapAnimation = Tween<double>(begin: _dragDx, end: 0.0).animate(
      CurvedAnimation(
        parent: _snapController,
        curve: context.motionCurve(PulsrMotion.spring),
      ),
    );
    _isDragging = false;
    _snapController.forward(from: 0.0);
  }

  void _handleDragEnd(DragEndDetails details, double cardSize) {
    final state = widget.props.state;
    final cubit = widget.props.cubit;
    final double velocity = details.primaryVelocity ?? 0.0;
    final double threshold = cardSize * 0.26;

    if ((_dragDx < -threshold || velocity < -360.0) && state.hasNextNeighbour) {
      PulsrHaptics.lightImpact();
      cubit.next();
    } else if ((_dragDx > threshold || velocity > 360.0) &&
        state.hasPreviousNeighbour) {
      PulsrHaptics.lightImpact();
      cubit.previous();
    }
    _animateBackToCenter();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = widget.props.state;
    final song = state.currentSong;
    final isPlaying = state.isPlaying;
    final activeColor = widget.props.activeColor;
    final isDark = p.isDark;
    final neighbors = resolveQueueNeighbors(state);
    final swipePref = context.select<SettingsCubit, NowPlayingArtworkSwipeAction>(
      (c) => c.state.nowPlayingArtworkSwipe,
    );
    final bool allowSwipe = !widget.isPreview &&
        swipePref == NowPlayingArtworkSwipeAction.nextPrev;
    final BorderRadius cardCorners = AppRadii.circular(widget.cardRadius);
    final bool motionEnabled = !widget.isPreview && context.motionEnabled;
    final Duration motionDuration =
        motionEnabled ? context.motionMs(320) : Duration.zero;
    final Curve motionCurve = context.motionCurve(Curves.easeOutCubic);

    return PlayerGestureScope(
      child: LayoutBuilder(
        builder: (context, artConstraints) {
          final double maxW = artConstraints.maxWidth;
          final double maxH = artConstraints.maxHeight;
          // Reserve horizontal peek space so previous/next cards peek cleanly
          // without clipping outside the viewport.
          final double horizontalPeekReserve = (maxW * 0.16).clamp(18.0, 56.0);
          final double verticalBleed = 14.0;

          final double cardSize = PlayerThemeMetrics.safeArtworkSize(
            availableWidth: math.max(0.0, maxW - horizontalPeekReserve * 2),
            availableHeight: math.max(0.0, maxH - verticalBleed * 2),
            isTablet: widget.metrics.isTablet,
            maxAllowedOverride: widget.metrics.isLandscape ? 270.0 : 350.0,
          );

          if (cardSize <= 0) {
            return const SizedBox.shrink();
          }

          final double maxDrag = cardSize * 0.62;
          final double clampedDx = _dragDx.clamp(-maxDrag, maxDrag);
          final double dragRatio = (clampedDx / cardSize).clamp(-1.0, 1.0);
          final double absRatio = dragRatio.abs();

          // Reveal interpolation for neighbor cards during horizontal drag.
          final double nextReveal = (-dragRatio).clamp(0.0, 1.0);
          final double prevReveal = dragRatio.clamp(0.0, 1.0);

          final double peekOffset = (cardSize * 0.15).clamp(16.0, 44.0);

          Widget buildPeekCard({
            required SongsTableData? neighborSong,
            required bool isNext,
            required double reveal,
          }) {
            final double sign = isNext ? 1.0 : -1.0;
            final double scale = 0.85 + reveal * 0.10;
            final double translateX = sign * peekOffset * (1.0 - reveal * 0.45);
            final double translateY = (1.0 - reveal) * 8.0;
            final double angle = sign * 0.068 * (1.0 - reveal * 0.7);
            final double dimAlpha = (isDark ? 0.44 : 0.28) * (1.0 - reveal * 0.55);

            return ExcludeSemantics(
              child: IgnorePointer(
                child: Transform.translate(
                  offset: Offset(translateX, translateY),
                  child: Transform.rotate(
                    angle: angle,
                    child: Transform.scale(
                      scale: scale,
                      child: Container(
                        width: cardSize,
                        height: cardSize,
                        decoration: BoxDecoration(
                          borderRadius: cardCorners,
                          color: Color.lerp(
                            p.surfaceContainer,
                            activeColor,
                            isNext ? 0.16 : 0.24,
                          ),
                          border: Border.all(
                            color: isDark
                                ? AppColors.specularAt(0.16 + reveal * 0.12)
                                : p.hairline,
                            width: 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.scrimAt(isDark ? 0.36 : 0.14),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: cardCorners,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (neighborSong != null)
                                CachedArtwork(
                                  id: neighborSong.id,
                                  albumId: neighborSong.albumId,
                                  remoteUrl: neighborSong.remoteArtworkUrl ??
                                      neighborSong.artworkUri,
                                  type: ArtworkType.AUDIO,
                                  size: cardSize,
                                  borderRadius: widget.cardRadius,
                                  highQuality: false,
                                )
                              else
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Color.lerp(
                                              p.surfaceContainerHigh,
                                              activeColor,
                                              isNext ? 0.14 : 0.22,
                                            ) ??
                                            p.surfaceContainerHigh,
                                        p.surfaceContainer,
                                      ],
                                    ),
                                  ),
                                ),
                              ColoredBox(
                                color: isDark
                                    ? AppColors.scrimAt(dimAlpha)
                                    : p.bg.withValues(alpha: dimAlpha),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }

          // Order peeking cards so whichever neighbor is being dragged into
          // view rises above the opposite neighbor.
          final Widget prevCard = buildPeekCard(
            neighborSong: neighbors.prev,
            isNext: false,
            reveal: prevReveal,
          );
          final Widget nextCard = buildPeekCard(
            neighborSong: neighbors.next,
            isNext: true,
            reveal: nextReveal,
          );

          final double activeScale =
              ((widget.isPreview || isPlaying) ? 1.0 : 0.95) -
                  absRatio * 0.04;
          final double activeTilt = dragRatio * 0.11;

          final Widget activeCard = GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: allowSwipe
                ? (_) {
                    _snapController.stop();
                    setState(() => _isDragging = true);
                  }
                : null,
            onHorizontalDragUpdate: allowSwipe
                ? (details) {
                    setState(() {
                      _dragDx = (_dragDx + details.delta.dx)
                          .clamp(-maxDrag, maxDrag);
                    });
                  }
                : null,
            onHorizontalDragEnd: allowSwipe
                ? (details) => _handleDragEnd(details, cardSize)
                : null,
            onHorizontalDragCancel: allowSwipe ? _animateBackToCenter : null,
            child: Transform.translate(
              offset: Offset(clampedDx, absRatio * 10.0),
              child: Transform.rotate(
                angle: activeTilt,
                child: AnimatedScale(
                  scale: activeScale,
                  duration: _isDragging ? Duration.zero : motionDuration,
                  curve: motionCurve,
                  child: AnimatedContainer(
                    key: const ValueKey('artwork_card'),
                    duration: _isDragging ? Duration.zero : motionDuration,
                    curve: motionCurve,
                    width: cardSize,
                    height: cardSize,
                    decoration: BoxDecoration(
                      borderRadius: cardCorners,
                      border: Border.all(
                        color: isDark
                            ? AppColors.specularAt(0.24)
                            : AppColors.specularAt(0.50),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.scrimAt(
                            isDark
                                ? (isPlaying ? 0.60 : 0.44)
                                : (isPlaying ? 0.24 : 0.15),
                          ),
                          blurRadius: isPlaying ? 38 : 22,
                          spreadRadius: isPlaying ? -2 : -4,
                          offset: Offset(0, isPlaying ? 18 : 10),
                        ),
                        BoxShadow(
                          color: activeColor.withValues(
                            alpha: widget.customGlow
                                ? (isPlaying ? 0.44 : 0.28)
                                : (isPlaying ? 0.26 : 0.14),
                          ),
                          blurRadius: widget.customGlow ? 42 : 24,
                          spreadRadius: widget.customGlow ? 0 : -4,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: cardCorners,
                      child: Hero(
                        tag: widget.props.heroTag,
                        child: PlayerArtworkSemantics(
                          song: song,
                          child: song != null
                              ? CachedArtwork(
                                  id: song.id,
                                  albumId: song.albumId,
                                  remoteUrl: song.remoteArtworkUrl ??
                                      song.artworkUri,
                                  type: ArtworkType.AUDIO,
                                  size: cardSize,
                                  borderRadius: widget.cardRadius,
                                  highQuality: true,
                                )
                              : DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: p.surfaceContainer,
                                    borderRadius: cardCorners,
                                  ),
                                  child: Icon(
                                    Icons.music_note_rounded,
                                    size: 72,
                                    color: p.textSecondary
                                        .withValues(alpha: 0.45),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );

          return Center(
            child: SizedBox(
              width: cardSize + peekOffset * 2,
              height: cardSize + verticalBleed * 2,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  if (dragRatio >= 0) ...[
                    nextCard,
                    prevCard,
                  ] else ...[
                    prevCard,
                    nextCard,
                  ],
                  activeCard,
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Unified frosted-glass floating control card with crisp specular top border,
/// track metadata + favorite heart, `BlocSelector`-driven glass scrubber,
/// spatial transport controls, and compact Lyrics / Queue / Tools footer row.
class _SpatialGlassControlCard extends StatelessWidget {
  final PlayerThemeProps props;
  final PlayerThemeMetrics metrics;
  final double cardRadius;
  final bool isCompact;
  final bool isVeryShort;
  final bool isInSplitView;
  final bool isPreview;

  const _SpatialGlassControlCard({
    required this.props,
    required this.metrics,
    required this.cardRadius,
    required this.isCompact,
    required this.isVeryShort,
    required this.isInSplitView,
    required this.isPreview,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = props.state;
    final cubit = props.cubit;
    final song = state.currentSong;
    final activeColor = props.activeColor;
    final isDark = p.isDark;
    final canBlur = AppBlur.canBlur(context);
    final double sigma = AppBlur.clampSigma(AppBlur.sheet);
    final BorderRadius corners = AppRadii.circular(cardRadius);

    final Color glassFill = canBlur
        ? Color.alphaBlend(
            activeColor.withValues(alpha: isDark ? 0.07 : 0.04),
            isDark
                ? p.surfaceContainer.withValues(alpha: 0.54)
                : p.surface.withValues(alpha: 0.76),
          )
        : p.surfaceContainer.withValues(alpha: AppBlur.solidFallbackMinAlpha);

    final Color outerBorder = isDark ? AppColors.specularAt(0.18) : p.hairline;
    final double gap = isVeryShort
        ? AppSpacing.s4
        : (isCompact ? AppSpacing.s6 : AppSpacing.s10);

    final double titleFontSize = metrics.isTablet
        ? AppFontSize.titleLarge
        : (isVeryShort ? AppFontSize.bodyLarge : AppFontSize.title);
    final double artistFontSize =
        isVeryShort ? AppFontSize.label : AppFontSize.bodySmall;

    final Widget cardBody = Container(
      decoration: BoxDecoration(
        borderRadius: corners,
        color: glassFill,
        border: Border.all(color: outerBorder, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: AppColors.scrimAt(isDark ? 0.40 : 0.10),
            blurRadius: 28,
            spreadRadius: -4,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Crisp specular top highlight rim catching light on the frosted sheet.
          PositionedDirectional(
            top: 0,
            start: cardRadius * 0.7,
            end: cardRadius * 0.7,
            height: 1.2,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      AppColors.specularAt(isDark ? 0.42 : 0.75),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              AppSpacing.md,
              isVeryShort ? AppSpacing.s8 : AppSpacing.s12,
              AppSpacing.md,
              isVeryShort ? AppSpacing.s4 : AppSpacing.s8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Track title & artist + favorite heart.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          MarqueeText(
                            text: song?.title ?? context.l10n.noTrackSelected,
                            textAlign: TextAlign.start,
                            style: TextStyle(
                              color: p.textPrimary,
                              fontSize: titleFontSize,
                              fontWeight: FontWeight.w700,
                              letterSpacing: AppTracking.title,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.s2),
                          Text(
                            song?.artist ?? context.l10n.unknownArtist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: p.textSecondary,
                              fontSize: artistFontSize,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    PlayerAnimatedFavoriteButton(
                      isFavorite: song?.isFavorite == true,
                      favoriteColor: AppColors.favorite,
                      inactiveColor: p.textSecondary,
                      iconSize: 23,
                      semanticLabel: song?.isFavorite == true
                          ? context.l10n.unlike
                          : context.l10n.like,
                      onTap: () {
                        if (song != null) {
                          cubit.toggleFavorite(song.id);
                        }
                      },
                    ),
                  ],
                ),

                SizedBox(height: gap),

                // 2. Sleek glass progress scrubber (BlocSelector-scoped).
                _SpatialGlassScrubber(
                  props: props,
                  duration: state.duration,
                  activeColor: activeColor,
                  isCompact: isCompact,
                ),

                // Optional transient banners (suppressed in preview).
                if (!isPreview && song?.source == SongSource.radio) ...[
                  const SizedBox(height: AppSpacing.xs),
                  RadioNowPlayingRecommendations(
                    props: props,
                    cubit: cubit,
                    metrics: metrics,
                  ),
                ] else if (!isPreview && state.bookmarkPosition != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  PlayerBookmarkPromptBanner(
                    cubit: cubit,
                    position: state.bookmarkPosition!,
                  ),
                ],

                SizedBox(height: gap),

                // 3. Spatial glass transport controls (Shuffle, Prev, Play/Pause, Next, Repeat).
                _SpatialTransportRow(
                  props: props,
                  activeColor: activeColor,
                  isCompact: isCompact,
                  isPreview: isPreview,
                ),

                SizedBox(height: isVeryShort ? AppSpacing.s2 : AppSpacing.s6),

                // Subtle hairline glass divider above footer.
                Divider(
                  height: 1,
                  thickness: 0.8,
                  color: isDark ? AppColors.specularAt(0.10) : p.hairline,
                ),

                // 4. Compact footer row: Lyrics, Queue, PlayerToolsTriggerButton.
                _SpatialFooterRow(
                  props: props,
                  activeColor: activeColor,
                  isInSplitView: isInSplitView,
                  isPreview: isPreview,
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (canBlur && sigma > 0.0) {
      return ClipRRect(
        borderRadius: corners,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: cardBody,
        ),
      );
    }

    return ClipRRect(
      borderRadius: corners,
      child: cardBody,
    );
  }
}

/// Sleek glass progress scrubber strictly isolated inside a
/// `BlocSelector<PlayerCubit, PlayerState, Duration>` so playback ticks never
/// rebuild the surrounding glass card or artwork deck.
class _SpatialGlassScrubber extends StatefulWidget {
  final PlayerThemeProps props;
  final Duration duration;
  final Color activeColor;
  final bool isCompact;

  const _SpatialGlassScrubber({
    required this.props,
    required this.duration,
    required this.activeColor,
    required this.isCompact,
  });

  @override
  State<_SpatialGlassScrubber> createState() => _SpatialGlassScrubberState();
}

class _SpatialGlassScrubberState extends State<_SpatialGlassScrubber> {
  double? _dragMs;

  @override
  void didUpdateWidget(covariant _SpatialGlassScrubber oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.props.state.currentSong?.id !=
        oldWidget.props.state.currentSong?.id) {
      _dragMs = null;
    }
  }

  double _fractionFor(double dx, double width, TextDirection direction) {
    if (width <= 0) return 0.0;
    final adjusted = direction == TextDirection.rtl ? width - dx : dx;
    return (adjusted / width).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isDark = p.isDark;
    final direction = Directionality.of(context);

    return BlocSelector<PlayerCubit, PlayerState, Duration>(
      selector: (s) => s.position,
      builder: (context, position) {
        final double maxMs = widget.duration.inMilliseconds.toDouble();
        final double safeMax = maxMs > 0 ? maxMs : 1.0;
        final bool isDragging = _dragMs != null;
        final double effectiveMs =
            (_dragMs ?? position.inMilliseconds.toDouble()).clamp(0.0, safeMax);
        final double progress = (effectiveMs / safeMax).clamp(0.0, 1.0);
        final Duration effectiveDuration = Duration(milliseconds: effectiveMs.round());

        Duration clampSeek(Duration delta) {
          final target = effectiveDuration + delta;
          if (target < Duration.zero) return Duration.zero;
          if (target > widget.duration) return widget.duration;
          return target;
        }

        String seekLabel(Duration v) =>
            '${Formatters.formatDuration(v)} / '
            '${Formatters.formatDuration(widget.duration)}';

        final double trackHeight =
            isDragging ? (widget.isCompact ? 9.0 : 10.0) : (widget.isCompact ? 5.0 : 6.0);
        final Color trackBg = isDark
            ? AppColors.specularAt(0.16)
            : p.textPrimary.withValues(alpha: 0.14);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              slider: true,
              label: context.l10n.seekLabel,
              value: seekLabel(effectiveDuration),
              increasedValue:
                  seekLabel(clampSeek(const Duration(seconds: 10))),
              decreasedValue:
                  seekLabel(clampSeek(const Duration(seconds: -10))),
              onIncrease: () => widget.props.cubit
                  .seek(clampSeek(const Duration(seconds: 10))),
              onDecrease: () => widget.props.cubit
                  .seek(clampSeek(const Duration(seconds: -10))),
              excludeSemantics: true,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final double width = constraints.maxWidth;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (details) {
                      final frac =
                          _fractionFor(details.localPosition.dx, width, direction);
                      PulsrHaptics.selectionClick();
                      widget.props.cubit
                          .seek(Duration(milliseconds: (frac * safeMax).round()));
                    },
                    onHorizontalDragStart: (details) {
                      PulsrHaptics.selectionClick();
                      final frac =
                          _fractionFor(details.localPosition.dx, width, direction);
                      setState(() => _dragMs = frac * safeMax);
                    },
                    onHorizontalDragUpdate: (details) {
                      final frac =
                          _fractionFor(details.localPosition.dx, width, direction);
                      setState(() => _dragMs = frac * safeMax);
                    },
                    onHorizontalDragEnd: (_) {
                      final target = _dragMs;
                      if (target != null) {
                        widget.props.cubit
                            .seek(Duration(milliseconds: target.round()));
                      }
                      setState(() => _dragMs = null);
                    },
                    onHorizontalDragCancel: () => setState(() => _dragMs = null),
                    child: SizedBox(
                      height: widget.isCompact ? 30.0 : 36.0,
                      width: double.infinity,
                      child: Center(
                        child: AnimatedContainer(
                          duration: context.motionMs(120),
                          curve: context.motionCurve(Curves.easeOutCubic),
                          height: trackHeight,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: trackBg,
                            borderRadius: AppRadii.full,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: FractionallySizedBox(
                            alignment: AlignmentDirectional.centerStart,
                            widthFactor: progress,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    widget.activeColor.withValues(alpha: 0.86),
                                    widget.activeColor,
                                  ],
                                ),
                                borderRadius: AppRadii.full,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  Formatters.formatDuration(effectiveDuration),
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w600,
                    color: isDragging ? p.textPrimary : p.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  Formatters.formatDuration(widget.duration),
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w600,
                    color: p.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Spatial glass transport controls: Shuffle, Previous, luminous Play/Pause
/// pill, Next, and Repeat (zero A/B loop clutter).
class _SpatialTransportRow extends StatelessWidget {
  final PlayerThemeProps props;
  final Color activeColor;
  final bool isCompact;
  final bool isPreview;

  const _SpatialTransportRow({
    required this.props,
    required this.activeColor,
    required this.isCompact,
    required this.isPreview,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = props.state;
    final cubit = props.cubit;
    final l10n = context.l10n;
    final isDark = p.isDark;
    final isPlaying = state.isPlaying;
    final isShuffle = state.isShuffle;
    final repeatMode = state.repeatMode;
    final hasPrev = state.hasPreviousNeighbour;
    final hasNext = state.hasNextNeighbour;

    final double playSize = isCompact ? 50.0 : 58.0;
    final Color skipGlassSurface = isDark
        ? AppColors.specularAt(0.10)
        : p.textPrimary.withValues(alpha: 0.06);
    final Color skipGlassBorder =
        isDark ? AppColors.specularAt(0.14) : p.hairline;

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 1. Shuffle
          PlayerIconActionButton(
            icon: Icons.shuffle_rounded,
            tooltip: l10n.shuffle,
            isActive: isShuffle,
            iconColor: p.textSecondary,
            activeColor: activeColor,
            iconSize: 20,
            showActiveDot: true,
            onTap: () => cubit.toggleShuffle(),
          ),
          const SizedBox(width: AppSpacing.s6),

          // 2. Previous
          PlayerIconActionButton(
            icon: Icons.skip_previous_rounded,
            tooltip: l10n.previous,
            iconColor: hasPrev ? p.textPrimary : p.textTertiary,
            surfaceColor: skipGlassSurface,
            borderColor: skipGlassBorder,
            iconSize: 26,
            onTap: hasPrev ? () => cubit.previous() : null,
          ),
          const SizedBox(width: AppSpacing.s12),

          // 3. Play / Pause luminous spatial circle
          Semantics(
            button: true,
            label: isPlaying ? l10n.pause : l10n.play,
            excludeSemantics: true,
            child: Material(
              color: activeColor,
              shape: CircleBorder(
                side: BorderSide(
                  color: AppColors.specularAt(isDark ? 0.32 : 0.48),
                  width: 1.0,
                ),
              ),
              elevation: isPlaying ? 6 : 2,
              shadowColor: activeColor.withValues(alpha: 0.45),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {
                  PulsrHaptics.lightImpact();
                  cubit.togglePlayPause();
                },
                child: SizedBox(
                  width: math.max(playSize, AppSpacing.minTouchTarget),
                  height: math.max(playSize, AppSpacing.minTouchTarget),
                  child: Center(
                    child: AnimatedSwitcher(
                      duration:
                          isPreview ? Duration.zero : context.motionMs(200),
                      child: Icon(
                        isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        key: ValueKey(isPlaying),
                        size: isCompact ? 28 : 32,
                        color: AppColors.textOnAccent(activeColor),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s12),

          // 4. Next
          PlayerIconActionButton(
            icon: Icons.skip_next_rounded,
            tooltip: l10n.next,
            iconColor: hasNext ? p.textPrimary : p.textTertiary,
            surfaceColor: skipGlassSurface,
            borderColor: skipGlassBorder,
            iconSize: 26,
            onTap: hasNext ? () => cubit.next() : null,
          ),
          const SizedBox(width: AppSpacing.s6),

          // 5. Repeat
          PlayerIconActionButton(
            icon: repeatMode == PlayerRepeatMode.one
                ? Icons.repeat_one_rounded
                : Icons.repeat_rounded,
            tooltip: l10n.repeat,
            isActive: repeatMode != PlayerRepeatMode.off,
            iconColor: p.textSecondary,
            activeColor: activeColor,
            iconSize: 20,
            showActiveDot: true,
            onTap: () {
              cubit.toggleRepeat();
              final nextMode = switch (repeatMode) {
                PlayerRepeatMode.off => PlayerRepeatMode.all,
                PlayerRepeatMode.all => PlayerRepeatMode.one,
                PlayerRepeatMode.one => PlayerRepeatMode.off,
              };
              final nextLabel = switch (nextMode) {
                PlayerRepeatMode.one => l10n.repeatOne,
                PlayerRepeatMode.all => l10n.repeatAll,
                PlayerRepeatMode.off => l10n.repeatOff,
              };
              PulsrToast.show(
                context,
                message: nextLabel,
                icon: nextMode == PlayerRepeatMode.one
                    ? Icons.repeat_one_rounded
                    : Icons.repeat_rounded,
                duration: const Duration(milliseconds: 1200),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Compact frosted footer row inside the floating control card:
/// **Lyrics**, **Queue**, and [PlayerToolsTriggerButton].
class _SpatialFooterRow extends StatelessWidget {
  final PlayerThemeProps props;
  final Color activeColor;
  final bool isInSplitView;
  final bool isPreview;

  const _SpatialFooterRow({
    required this.props,
    required this.activeColor,
    required this.isInSplitView,
    required this.isPreview,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = props.state;
    final cubit = props.cubit;
    final splitTabCtrl = PlayerSplitViewScope.tabControllerOf(context);

    Widget buildFooter(BuildContext context) {
      final bool isLyricsActive = !isPreview &&
          (isInSplitView ? (splitTabCtrl?.index == 0) : state.isLyricsVisible);
      final bool isQueueActive = !isPreview &&
          (isInSplitView ? (splitTabCtrl?.index == 1) : state.isQueueVisible);

      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          PlayerIconActionButton(
            icon: Icons.lyrics_rounded,
            tooltip: context.l10n.lyrics,
            isActive: isLyricsActive,
            iconColor: p.textSecondary,
            activeColor: activeColor,
            iconSize: 21,
            showActiveDot: true,
            onTap: () {
              if (isInSplitView && splitTabCtrl != null) {
                splitTabCtrl.animateTo(0);
              } else {
                cubit.toggleLyricsVisibility();
              }
            },
          ),
          PlayerIconActionButton(
            icon: Icons.queue_music_rounded,
            tooltip: context.l10n.queue,
            isActive: isQueueActive,
            iconColor: p.textSecondary,
            activeColor: activeColor,
            iconSize: 21,
            showActiveDot: true,
            onTap: () {
              if (isInSplitView && splitTabCtrl != null) {
                splitTabCtrl.animateTo(1);
              } else {
                cubit.toggleQueueVisibility();
              }
            },
          ),
          PlayerToolsTriggerButton(
            props: props,
            icon: Icons.tune_rounded,
            iconColor: p.textSecondary,
            iconSize: 21,
          ),
        ],
      );
    }

    if (isInSplitView && splitTabCtrl != null) {
      return AnimatedBuilder(
        animation: splitTabCtrl.animation ?? splitTabCtrl,
        builder: (context, _) => buildFooter(context),
      );
    }
    return buildFooter(context);
  }
}
