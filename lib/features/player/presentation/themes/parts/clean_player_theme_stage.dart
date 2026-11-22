part of '../clean_player_theme.dart';

/// Full-bleed smooth mesh & blurred album-art ambient backdrop for Clean Modern Flow.
///
/// Renders a luminous, non-void ambient gradient wash derived from the current
/// album art and accent palette. Any [ImageFilter.blur] is strictly gated by
/// [AppBlur.canBlur] and [AppBlur.clampSigma], falling back to a layered
/// radial mesh wash when GPU Saver or High Contrast is active.
class _CleanAmbientBackdrop extends StatelessWidget {
  final SongsTableData? song;
  final Color activeColor;
  final Color bgColor;
  final bool isAmoled;

  const _CleanAmbientBackdrop({
    required this.song,
    required this.activeColor,
    required this.bgColor,
    required this.isAmoled,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isDark = p.isDark;
    final canBlur = AppBlur.canBlur(context);
    final double sigma = AppBlur.clampSigma(AppBlur.maxSigma);

    final hsl = HSLColor.fromColor(activeColor);
    final secondaryGlow = hsl
        .withHue((hsl.hue + 38.0) % 360.0)
        .withSaturation((hsl.saturation * 0.85).clamp(0.25, 0.90))
        .toColor();
    final deepMist = isDark
        ? Color.alphaBlend(
            activeColor.withValues(alpha: isAmoled ? 0.14 : 0.22),
            isAmoled ? Color.lerp(p.bg, bgColor, 0.35)! : bgColor,
          )
        : Color.alphaBlend(
            activeColor.withValues(alpha: 0.14),
            p.bg,
          );
    final lowerBase = isDark
        ? Color.alphaBlend(
            AppColors.scrimAt(isAmoled ? 0.72 : 0.44),
            bgColor,
          )
        : Color.alphaBlend(
            activeColor.withValues(alpha: 0.06),
            p.bg,
          );

    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Rich ambient base gradient (no harsh pure-black void).
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  deepMist,
                  Color.lerp(deepMist, lowerBase, 0.55) ?? lowerBase,
                  lowerBase,
                ],
                stops: const [0.0, 0.52, 1.0],
              ),
            ),
          ),

          // 2. Blurred album art atmospheric layer (gated by AppBlur).
          if (song != null && canBlur && sigma > 0.0)
            ClipRect(
              child: Opacity(
                opacity: isDark ? (isAmoled ? 0.32 : 0.52) : 0.28,
                child: Transform.scale(
                  scale: 1.35,
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(
                      sigmaX: sigma,
                      sigmaY: sigma,
                      tileMode: TileMode.mirror,
                    ),
                    child: CachedArtwork(
                      id: song!.id,
                      albumId: song!.albumId,
                      remoteUrl: song!.remoteArtworkUrl ?? song!.artworkUri,
                      type: ArtworkType.AUDIO,
                      size: 320,
                      highQuality: false,
                      borderRadius: 0,
                    ),
                  ),
                ),
              ),
            ),

          // 3. Smooth multi-point mesh wash (enhances depth with blur and acts
          //    as a rich blurred-feel fallback when blur is disabled).
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.7, -0.65),
                radius: 1.05,
                colors: [
                  activeColor.withValues(
                    alpha: canBlur
                        ? (isDark ? 0.24 : 0.14)
                        : (isDark ? 0.32 : 0.18),
                  ),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.8, 0.25),
                radius: 1.0,
                colors: [
                  secondaryGlow.withValues(
                    alpha: canBlur
                        ? (isDark ? 0.18 : 0.10)
                        : (isDark ? 0.24 : 0.14),
                  ),
                  Colors.transparent,
                ],
              ),
            ),
          ),

          // 4. Subtle top & bottom legibility scrims.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isDark
                    ? [
                        AppColors.scrimAt(0.28),
                        Colors.transparent,
                        AppColors.scrimAt(isAmoled ? 0.62 : 0.42),
                        AppColors.scrimAt(isAmoled ? 0.84 : 0.66),
                      ]
                    : [
                        p.bg.withValues(alpha: 0.32),
                        p.bg.withValues(alpha: 0.18),
                        p.bg.withValues(alpha: 0.62),
                        p.bg.withValues(alpha: 0.88),
                      ],
                stops: const [0.0, 0.24, 0.68, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Large rounded artwork stage with Apple Music-style play/pause scale & shadow
/// depth animation.
class _CleanArtworkStage extends StatelessWidget {
  final PlayerThemeProps props;
  final PlayerThemeMetrics metrics;
  final bool isInSplitView;
  final bool isPreview;
  final bool canvasEnabled;
  final bool canvasAsBackdrop;
  final double horizontalPadding;

  const _CleanArtworkStage({
    required this.props,
    required this.metrics,
    required this.isInSplitView,
    required this.isPreview,
    required this.canvasEnabled,
    required this.canvasAsBackdrop,
    required this.horizontalPadding,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = props.state;
    final song = state.currentSong;
    final activeColor = props.activeColor;
    final isPlaying = state.isPlaying;
    final isDark = p.isDark;

    final double artRadius = resolveCustomRadius(context, AppRadii.r16);
    final BorderRadius artCorners = AppRadii.circular(artRadius);
    final bool customGlow = resolveCustomGlow(context);

    final bool animateScale = !isPreview && context.motionEnabled;
    final Duration motionDuration =
        animateScale ? context.motionMs(320) : Duration.zero;
    final Curve motionCurve = context.motionCurve(Curves.easeOutCubic);
    final double targetScale = (isPreview || isPlaying) ? 1.0 : 0.90;

    return KeyedSubtree(
      key: const ValueKey('art_stage'),
      child: PlayerGestureScope(
        child: LayoutBuilder(
          builder: (context, stageConstraints) {
            final double availW = math.max(
              0.0,
              stageConstraints.maxWidth - horizontalPadding * 2,
            );
            final double availH = math.max(
              0.0,
              stageConstraints.maxHeight - AppSpacing.xs * 2,
            );
            final double artSize = PlayerThemeMetrics.safeArtworkSize(
              availableWidth: availW,
              availableHeight: availH,
              isTablet: metrics.isTablet,
              maxAllowedOverride: metrics.isTablet ? 460.0 : 420.0,
            );

            if (artSize <= 0) {
              return const SizedBox.shrink();
            }

            final fallbackArt = CachedArtwork(
              id: song?.id ?? 0,
              albumId: song?.albumId,
              remoteUrl: song?.remoteArtworkUrl ?? song?.artworkUri,
              type: ArtworkType.AUDIO,
              size: artSize,
              highQuality: true,
              borderRadius: artRadius,
            );

            final Widget mediaChild =
                (!isPreview && canvasEnabled && !canvasAsBackdrop && song != null)
                    ? CanvasBackdrop(
                        song: song,
                        isPlaying: isPlaying,
                        isBackdropMode: false,
                        borderRadius: artCorners,
                        fallbackArtwork: fallbackArt,
                      )
                    : fallbackArt;

            final List<BoxShadow> shadows = [
              BoxShadow(
                color: AppColors.scrimAt(
                  isDark
                      ? (isPlaying ? 0.56 : 0.34)
                      : (isPlaying ? 0.24 : 0.14),
                ),
                blurRadius: isPlaying ? 38 : 16,
                spreadRadius: isPlaying ? -4 : -6,
                offset: Offset(0, isPlaying ? 18 : 8),
              ),
              if (customGlow || isPlaying)
                BoxShadow(
                  color: activeColor.withValues(
                    alpha: customGlow
                        ? (isPlaying ? 0.38 : 0.24)
                        : (isDark ? 0.22 : 0.12),
                  ),
                  blurRadius: customGlow ? 42 : 28,
                  spreadRadius: customGlow ? -2 : -8,
                  offset: Offset(0, isPlaying ? 10 : 4),
                ),
            ];

            return Center(
              child: AnimatedScale(
                scale: targetScale,
                duration: motionDuration,
                curve: motionCurve,
                child: AnimatedContainer(
                  duration: motionDuration,
                  curve: motionCurve,
                  width: artSize,
                  height: artSize,
                  decoration: BoxDecoration(
                    borderRadius: artCorners,
                    border: Border.all(
                      color: isDark
                          ? AppColors.specularAt(0.14)
                          : AppColors.specularAt(0.35),
                      width: 1.0,
                    ),
                    boxShadow: shadows,
                  ),
                  child: ClipRRect(
                    borderRadius: artCorners,
                    child: RepaintBoundary(
                      child: Hero(
                        tag: props.heroTag,
                        child: PlayerArtworkSemantics(
                          song: song,
                          child: mediaChild,
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
    );
  }
}
