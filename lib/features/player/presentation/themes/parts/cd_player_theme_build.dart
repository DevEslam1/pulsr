part of '../cd_player_theme.dart';

/// Brightness-aware cool-silver / brushed-titanium palette for the Y2K Discman
/// faceplate and its machined keys. Built exclusively from semantic palette and
/// material tokens so Light, Dark, and High-Contrast modes remain crisp.
class _CdChassisPalette {
  final bool isDark;
  final Color chassisTop;
  final Color chassisMid;
  final Color chassisBottom;
  final Color metalKeyTop;
  final Color metalKeyMid;
  final Color metalKeyBottom;
  final Color metalKeyBorder;
  final Color metalKeyTopSpecular;
  final Color heroKeyTop;
  final Color heroKeyBottom;
  final Color heroKeyInk;
  final Color inkPrimary;
  final Color inkSecondary;
  final Color hairline;
  final Color lcdSurfaceTop;
  final Color lcdSurfaceBottom;
  final Color lcdBorder;
  final Color lcdInk;
  final Color lcdInkDim;
  final Color lcdGridDot;
  final Color sliderActive;
  final Color sliderInactive;
  final Color sliderThumb;
  final Color actionDeckSurface;

  const _CdChassisPalette({
    required this.isDark,
    required this.chassisTop,
    required this.chassisMid,
    required this.chassisBottom,
    required this.metalKeyTop,
    required this.metalKeyMid,
    required this.metalKeyBottom,
    required this.metalKeyBorder,
    required this.metalKeyTopSpecular,
    required this.heroKeyTop,
    required this.heroKeyBottom,
    required this.heroKeyInk,
    required this.inkPrimary,
    required this.inkSecondary,
    required this.hairline,
    required this.lcdSurfaceTop,
    required this.lcdSurfaceBottom,
    required this.lcdBorder,
    required this.lcdInk,
    required this.lcdInkDim,
    required this.lcdGridDot,
    required this.sliderActive,
    required this.sliderInactive,
    required this.sliderThumb,
    required this.actionDeckSurface,
  });

  factory _CdChassisPalette.of(BuildContext context, Color activeColor) {
    final p = context.palette;
    final surface = context.playerSurfacePalette;
    final isDark = p.isDark;
    final isHighContrast =
        p.isHighContrast || MediaQuery.highContrastOf(context);

    if (isDark) {
      final titaniumTop = Color.lerp(
        PlayerMaterialColors.cdSurfaceMid,
        AppColors.discSilver,
        0.16,
      )!;
      final titaniumMid = Color.lerp(
        PlayerMaterialColors.cdSurfaceTop,
        AppColors.slate,
        0.14,
      )!;
      final titaniumBottom = Color.lerp(
        PlayerMaterialColors.cdTrayGradEnd,
        p.bg,
        0.38,
      )!;

      final heroTop = Color.lerp(
        AppColors.discSilver,
        AppColors.surfaceGreyLight,
        0.48,
      )!;
      final heroBottom = Color.lerp(
        AppColors.discAluminum,
        PlayerMaterialColors.cdWeightHigh,
        0.35,
      )!;

      return _CdChassisPalette(
        isDark: true,
        chassisTop: titaniumTop,
        chassisMid: titaniumMid,
        chassisBottom: titaniumBottom,
        metalKeyTop: Color.lerp(
          PlayerMaterialColors.cdWeightHigh,
          AppColors.discSilver,
          0.18,
        )!,
        metalKeyMid: PlayerMaterialColors.cdHeadMid,
        metalKeyBottom: PlayerMaterialColors.cdSurfaceBottom,
        metalKeyBorder:
            isHighContrast ? p.borderStrong : AppColors.specularAt(0.22),
        metalKeyTopSpecular: AppColors.specularAt(0.40),
        heroKeyTop: heroTop,
        heroKeyBottom: heroBottom,
        heroKeyInk: AppColors.onBright,
        inkPrimary: isHighContrast ? p.textPrimary : AppColors.textPrimary,
        inkSecondary: isHighContrast
            ? p.textSecondary
            : AppColors.discSilver.withValues(alpha: 0.78),
        hairline: isHighContrast ? p.hairline : AppColors.specularAt(0.14),
        lcdSurfaceTop: Color.lerp(
          surface.tapeWindow,
          AppColors.accentCyan,
          0.07,
        )!,
        lcdSurfaceBottom: PlayerMaterialColors.cdTrayGradEnd,
        lcdBorder: isHighContrast ? p.borderStrong : AppColors.specularAt(0.20),
        lcdInk: Color.lerp(surface.ledGlow, AppColors.accentCyan, 0.35)!,
        lcdInkDim: AppColors.discSilver.withValues(alpha: 0.72),
        lcdGridDot: AppColors.specularAt(0.06),
        sliderActive:
            Color.lerp(AppColors.surfaceGreyLight, activeColor, 0.40)!,
        sliderInactive: AppColors.specularAt(0.18),
        sliderThumb: AppColors.surfaceGreyLight,
        actionDeckSurface: PlayerMaterialColors.cdClampWell.withValues(
          alpha: 0.72,
        ),
      );
    }

    // Light mode: crisp cool-silver Discman anodized aluminum faceplate.
    final silverTop = Color.lerp(
      AppColors.lightSurface,
      AppColors.discSilver,
      0.24,
    )!;
    final silverMid = Color.lerp(
      AppColors.lightCard,
      AppColors.discSilver,
      0.32,
    )!;
    final silverBottom = Color.lerp(
      AppColors.lightOutline,
      AppColors.discAluminum,
      0.28,
    )!;

    final heroTop = Color.lerp(
      PlayerMaterialColors.cdHeadHigh,
      AppColors.slate,
      0.20,
    )!;
    final heroBottom = PlayerMaterialColors.cdSurfaceBottom;

    return _CdChassisPalette(
      isDark: false,
      chassisTop: silverTop,
      chassisMid: silverMid,
      chassisBottom: silverBottom,
      metalKeyTop: AppColors.lightSurface,
      metalKeyMid: Color.lerp(AppColors.lightCard, AppColors.discSilver, 0.25)!,
      metalKeyBottom: Color.lerp(
        AppColors.lightOutline,
        AppColors.discSilver,
        0.35,
      )!,
      metalKeyBorder: isHighContrast
          ? p.borderStrong
          : AppColors.slate.withValues(alpha: 0.36),
      metalKeyTopSpecular: AppColors.specularAt(0.90),
      heroKeyTop: heroTop,
      heroKeyBottom: heroBottom,
      heroKeyInk: AppColors.onPrimary,
      inkPrimary: isHighContrast ? p.textPrimary : AppColors.lightTextPrimary,
      inkSecondary:
          isHighContrast ? p.textSecondary : AppColors.lightTextSecondary,
      hairline:
          isHighContrast ? p.hairline : AppColors.slate.withValues(alpha: 0.24),
      lcdSurfaceTop: Color.lerp(
        PlayerMaterialColors.cdSurfaceTop,
        AppColors.slate,
        0.18,
      )!,
      lcdSurfaceBottom: PlayerMaterialColors.cdTrayGradEnd,
      lcdBorder: isHighContrast
          ? p.borderStrong
          : AppColors.slate.withValues(alpha: 0.45),
      lcdInk: Color.lerp(surface.ledGlow, AppColors.accentCyan, 0.28)!,
      lcdInkDim: AppColors.discSilver.withValues(alpha: 0.80),
      lcdGridDot: AppColors.specularAt(0.07),
      sliderActive: Color.lerp(AppColors.onBright, activeColor, 0.45)!,
      sliderInactive: AppColors.slate.withValues(alpha: 0.26),
      sliderThumb: AppColors.onBright,
      actionDeckSurface: AppColors.lightSurface.withValues(alpha: 0.68),
    );
  }
}

extension _CdPlayerThemeBuild on _CdPlayerThemeState {
  Widget _buildBody(BuildContext context) {
    final state = widget.props.state;
    final activeColor = widget.props.activeColor;
    final song = state.currentSong;
    final chassis = _CdChassisPalette.of(context, activeColor);
    final visualizerStyle = context
        .select<SettingsCubit, VisualizerStyle>((c) => c.state.visualizerStyle);
    final customGlow = resolveCustomGlow(context);

    return PlayerSurfaceShell(
      props: widget.props,
      background: _CdBrushedChassisBackground(
        chassis: chassis,
        activeColor: activeColor,
        customGlow: customGlow,
      ),
      topBarBuilder: (context, metrics) => _CdDiscmanTopBar(
        props: widget.props,
        chassis: chassis,
      ),
      builder: (context, metrics, isInSplitView, isPreview) {
        final showVisualizer = visualizerStyle != VisualizerStyle.off &&
            !isPreview &&
            !isInSplitView;
        final textScale =
            MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 2.0);
        final horizontalPad = metrics.isTablet ? AppSpacing.xl : AppSpacing.lg;

        // Drop the "TRK" prefix only when a tablet viewport is artificially
        // squeezed below 600 dp height (matches squeezed-tray accessibility guard).
        final bool squeezeDropTrackPrefix = metrics.isTablet &&
            metrics.constraints.maxHeight <= 600.0 &&
            !isInSplitView;

        Widget buildStage({required double? maxHeight}) {
          final stage = Hero(
            tag: widget.props.heroTag,
            child: _CdJewelStage(
              props: widget.props,
              isTablet: metrics.isTablet,
              isLandscape: metrics.isLandscape,
              rotationController: _rotationController,
              pickupAnimation: _pickupAnimation,
              glossAnimation: _glossController,
              customGlow: customGlow,
            ),
          );
          if (maxHeight != null) {
            return SizedBox(
              key: const ValueKey('cd_stage_view'),
              height: maxHeight,
              child: Center(child: stage),
            );
          }
          return Center(
            key: const ValueKey('cd_stage_view'),
            child: stage,
          );
        }

        Widget buildLowerConsole({
          required bool isCompact,
          required double pad,
        }) {
          final gapSm = isCompact ? AppSpacing.xs : AppSpacing.sm;
          final gapMd = isCompact ? AppSpacing.sm : AppSpacing.md;
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showVisualizer) ...[
                  SizedBox(
                    height: visualizerStyle == VisualizerStyle.circular
                        ? 48.0
                        : 26.0,
                    child: AudioVisualizer(
                      style: visualizerStyle,
                      color: activeColor,
                      height: visualizerStyle == VisualizerStyle.circular
                          ? 48.0
                          : 26.0,
                      isPlaying: state.isPlaying,
                      audioSessionId: state.audioSessionId,
                      trackSeed: song?.id,
                    ),
                  ),
                  SizedBox(height: gapSm),
                ],

                // 1. Backlit Y2K Monospace Dot-Matrix Discman LCD Strip
                _CdDiscmanLcdStrip(
                  props: widget.props,
                  chassis: chassis,
                  isCompact: isCompact,
                  isPreview: isPreview,
                  showTrackNumberPrefix: !squeezeDropTrackPrefix,
                ),
                SizedBox(height: gapSm),

                // 2. Clean Left-Aligned Track Title/Artist + Favorite
                _CdTrackHeaderRow(
                  props: widget.props,
                  chassis: chassis,
                  isCompact: isCompact,
                ),
                SizedBox(height: gapSm),

                // 3. Slim Metallic Discman Seek Bar (BlocSelector-scoped)
                _CdMetallicSeekBar(
                  props: widget.props,
                  chassis: chassis,
                  isCompact: isCompact,
                ),

                if (!isPreview && state.bookmarkPosition != null) ...[
                  SizedBox(height: gapSm),
                  PlayerBookmarkPromptBanner(
                    cubit: widget.props.cubit,
                    position: state.bookmarkPosition!,
                  ),
                ],

                SizedBox(height: gapMd),

                // 4. Precision Brushed-Metal Rectangular Discman Transport Keys
                _CdMetalTransportBar(
                  props: widget.props,
                  chassis: chassis,
                  isCompact: isCompact,
                ),

                if (!isPreview &&
                    isInSplitView &&
                    !metrics.isVeryShortHeight) ...[
                  SizedBox(height: gapSm),
                  PlayerVolumeBar(
                    cubit: widget.props.cubit,
                    activeColor: activeColor,
                  ),
                ],

                if (!isPreview) ...[
                  SizedBox(height: gapMd),
                  // 5. Compact Secondary Discman Action Strip
                  _CdSecondaryActionStrip(
                    props: widget.props,
                    chassis: chassis,
                    isInSplitView: isInSplitView,
                  ),
                ],
              ],
            ),
          );
        }

        // Top inset below PlayerSurfaceShell's floating PlayerCompactTopBar.
        final double topBarReserve = (!isInSplitView && !isPreview)
            ? AppSpacing.minTouchTarget + AppSpacing.xs
            : AppSpacing.xs;

        // 1. Short Landscape Layout (e.g. 844x390 phone landscape)
        if (metrics.isLandscape && !isInSplitView && !isPreview) {
          return SafeArea(
            child: Padding(
              padding:
                  EdgeInsets.only(top: topBarReserve, bottom: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 5,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.xs,
                      ),
                      child: buildStage(maxHeight: null),
                    ),
                  ),
                  Expanded(
                    flex: 6,
                    child: Center(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.xs,
                        ),
                        child: buildLowerConsole(
                          isCompact: true,
                          pad: AppSpacing.md,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // 2. Preview Layout (Theme Picker / Theme Studio thumbnail)
        if (isPreview) {
          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xs,
                    ),
                    child: buildStage(maxHeight: null),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                buildLowerConsole(isCompact: true, pad: AppSpacing.xs),
              ],
            ),
          );
        }

        // 3. Portrait / Tablet / Split-View Layout with automatic scroll guard
        //    for short viewports or 200% accessibility text scaling.
        final double scrollThreshold =
            (isInSplitView ? 520.0 : 640.0) + (textScale - 1.0) * 140.0;
        final bool needsScroll =
            metrics.constraints.maxHeight < scrollThreshold;
        final bool isCompact = metrics.isShortHeight ||
            metrics.isVeryShortHeight ||
            textScale > 1.35;

        if (needsScroll) {
          final double boundedStageH =
              (metrics.constraints.maxHeight * 0.36).clamp(132.0, 260.0);
          return SafeArea(
            top: !isInSplitView,
            bottom: !isInSplitView,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.only(
                top: topBarReserve,
                bottom: AppSpacing.md,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: horizontalPad),
                    child: buildStage(maxHeight: boundedStageH),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  buildLowerConsole(isCompact: true, pad: horizontalPad),
                ],
              ),
            ),
          );
        }

        return SafeArea(
          top: !isInSplitView,
          bottom: !isInSplitView,
          child: Padding(
            padding: EdgeInsets.only(
              top: topBarReserve,
              bottom: AppSpacing.sm,
            ),
            child: Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPad,
                      vertical: AppSpacing.xs,
                    ),
                    child: buildStage(maxHeight: null),
                  ),
                ),
                SizedBox(height: isCompact ? AppSpacing.xs : AppSpacing.sm),
                buildLowerConsole(
                  isCompact: isCompact,
                  pad: horizontalPad,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Brushed cool-silver / titanium Discman faceplate backdrop with subtle
/// hairline metallic sheen reflections.
class _CdBrushedChassisBackground extends StatelessWidget {
  final _CdChassisPalette chassis;
  final Color activeColor;
  final bool customGlow;

  const _CdBrushedChassisBackground({
    required this.chassis,
    required this.activeColor,
    required this.customGlow,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  chassis.chassisTop,
                  chassis.chassisMid,
                  chassis.chassisBottom,
                ],
                stops: const [0.0, 0.48, 1.0],
              ),
            ),
          ),
          CustomPaint(
            painter: _CdChassisSheenPainter(
              chassis: chassis,
              activeColor: activeColor,
              customGlow: customGlow,
            ),
          ),
        ],
      ),
    );
  }
}

class _CdChassisSheenPainter extends CustomPainter {
  final _CdChassisPalette chassis;
  final Color activeColor;
  final bool customGlow;

  _CdChassisSheenPainter({
    required this.chassis,
    required this.activeColor,
    required this.customGlow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Subtle diagonal machined titanium highlight band.
    final sheenPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AppColors.specularAt(0.0),
          AppColors.specularAt(chassis.isDark ? 0.06 : 0.34),
          AppColors.specularAt(0.0),
          AppColors.specularAt(chassis.isDark ? 0.04 : 0.20),
          AppColors.specularAt(0.0),
        ],
        stops: const [0.0, 0.24, 0.46, 0.72, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, sheenPaint);

    // Subtle optical accent glow radiating softly behind the jewel case.
    final glowAlpha = customGlow
        ? (chassis.isDark ? 0.22 : 0.14)
        : (chassis.isDark ? 0.10 : 0.06);
    final glowCenter = Offset(size.width * 0.5, size.height * 0.32);
    final glowRadius = math.max(size.width, size.height) * 0.58;
    canvas.drawCircle(
      glowCenter,
      glowRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            activeColor.withValues(alpha: glowAlpha),
            activeColor.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: glowCenter, radius: glowRadius)),
    );

    // Fine brushed-metal horizontal hairline accents along the top & bottom
    // edges of the chassis.
    if (!GpuBudget.isGpuSaverActive) {
      final linePaint = Paint()
        ..color = chassis.isDark
            ? AppColors.specularAt(0.03)
            : AppColors.slate.withValues(alpha: 0.05)
        ..strokeWidth = 0.6;
      const double step = 18.0;
      for (double y = 12.0; y < size.height; y += step) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CdChassisSheenPainter oldDelegate) =>
      oldDelegate.chassis.isDark != chassis.isDark ||
      oldDelegate.activeColor != activeColor ||
      oldDelegate.customGlow != customGlow;
}

/// Minimal Discman top bar with etched theme identity pill and song menu.
class _CdDiscmanTopBar extends StatelessWidget {
  final PlayerThemeProps props;
  final _CdChassisPalette chassis;

  const _CdDiscmanTopBar({
    required this.props,
    required this.chassis,
  });

  @override
  Widget build(BuildContext context) {
    final song = props.state.currentSong;
    return PlayerCompactTopBar(
      foregroundColor: chassis.inkPrimary,
      buttonSurfaceColor: chassis.actionDeckSurface,
      buttonBorderColor: chassis.hairline,
      center: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [chassis.metalKeyTop, chassis.metalKeyBottom],
          ),
          borderRadius: AppRadii.r8All,
          border: Border.all(color: chassis.metalKeyBorder, width: 1.0),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.album_outlined,
              size: 13,
              color: props.activeColor,
            ),
            const SizedBox(width: AppSpacing.s6),
            Flexible(
              child: Text(
                ((song?.album ?? '').trim().isNotEmpty
                        ? song!.album
                        : context.l10n.browseDisc)
                    .toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: AppFontSize.caption,
                  fontWeight: FontWeight.w800,
                  letterSpacing: AppTracking.wide,
                  color: chassis.inkPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
      trailing: [
        PlayerIconActionButton(
          icon: Icons.more_horiz_rounded,
          tooltip: context.l10n.moreOptions,
          iconColor: chassis.inkPrimary,
          surfaceColor: chassis.actionDeckSurface,
          borderColor: chassis.hairline,
          onTap: song == null
              ? null
              : () => SongOptionsSheet.show(context, song: song),
        ),
      ],
    );
  }
}

/// Authentic Y2K backlit Discman dot-matrix LCD readout strip showing
/// `TRK 12 · 01:48 / 03:56` plus live decoded audio spec when available.
///
/// Subscribes narrowly via [BlocSelector] to whole-second position ticks so
/// parent widgets never rebuild on playback progress.
class _CdDiscmanLcdStrip extends StatelessWidget {
  final PlayerThemeProps props;
  final _CdChassisPalette chassis;
  final bool isCompact;
  final bool isPreview;
  final bool showTrackNumberPrefix;

  const _CdDiscmanLcdStrip({
    required this.props,
    required this.chassis,
    required this.isCompact,
    required this.isPreview,
    required this.showTrackNumberPrefix,
  });

  @override
  Widget build(BuildContext context) {
    final state = props.state;
    final song = state.currentSong;
    final trackNum = (state.currentIndex >= 0 ? state.currentIndex + 1 : 1)
        .toString()
        .padLeft(2, '0');
    final settingsState =
        context.select<SettingsCubit, SettingsState>((c) => c.state);
    final telemetry = formatPlayerAudioTelemetry(song, settingsState);
    final lcdRadius = resolveCustomRadius(context, AppRadii.r10).clamp(
      AppRadii.r4,
      AppRadii.r16,
    );

    return BlocSelector<PlayerCubit, PlayerState,
        ({int posSec, int durSec, bool isPlaying})>(
      selector: (s) => (
        posSec: s.position.inSeconds,
        durSec: s.duration.inSeconds,
        isPlaying: s.isPlaying,
      ),
      builder: (context, tick) {
        final elapsedStr =
            Formatters.formatDuration(Duration(seconds: tick.posSec));
        final totalStr =
            Formatters.formatDuration(Duration(seconds: tick.durSec));
        final trackLabel = showTrackNumberPrefix
            ? '${context.l10n.cdTrackNumber(trackNum)} · $elapsedStr / $totalStr'
            : '$elapsedStr / $totalStr';

        final Widget lcdContent = Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [chassis.lcdSurfaceTop, chassis.lcdSurfaceBottom],
            ),
            borderRadius: AppRadii.circular(lcdRadius),
            border: Border.all(
              color: tick.isPlaying
                  ? props.activeColor.withValues(alpha: 0.45)
                  : chassis.lcdBorder,
              width: 1.1,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.scrimAt(chassis.isDark ? 0.42 : 0.20),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned.fill(
                child: ExcludeSemantics(
                  child: CustomPaint(
                    painter: _CdLcdDotMatrixPainter(
                      dotColor: chassis.lcdGridDot,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: isCompact ? AppSpacing.s6 : AppSpacing.s10,
                ),
                child: Row(
                  children: [
                    // Backlit optical laser LED dot.
                    ExcludeSemantics(
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: tick.isPlaying
                              ? chassis.lcdInk
                              : chassis.lcdInkDim.withValues(alpha: 0.35),
                          boxShadow: tick.isPlaying
                              ? [
                                  BoxShadow(
                                    color: chassis.lcdInk.withValues(
                                      alpha: 0.65,
                                    ),
                                    blurRadius: 6,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s10),
                    Expanded(
                      child: Text(
                        trackLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: isCompact
                              ? AppFontSize.label
                              : AppFontSize.bodySmall,
                          fontWeight: FontWeight.w800,
                          letterSpacing: AppTracking.overline,
                          color: chassis.lcdInk,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    if (telemetry.compactBadge.isNotEmpty) ...[
                      const SizedBox(width: AppSpacing.xs),
                      Flexible(
                        flex: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.s6,
                            vertical: AppSpacing.s2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.specularAt(0.08),
                            borderRadius: AppRadii.r4All,
                            border: Border.all(
                              color: chassis.lcdInk.withValues(alpha: 0.28),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            telemetry.codec ?? telemetry.compactBadge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: AppFontSize.caption,
                              fontWeight: FontWeight.w700,
                              letterSpacing: AppTracking.label,
                              color: chassis.lcdInkDim,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );

        if (song == null || isPreview) return lcdContent;
        return Semantics(
          button: true,
          label: context.l10n.audioQuality,
          child: Material(
            color: AppColors.specularAt(0.0),
            child: InkWell(
              borderRadius: AppRadii.circular(lcdRadius),
              onTap: () => AudioQualitySheet.show(
                context,
                song,
                props.activeColor,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: AppSpacing.minTouchTarget,
                ),
                child: Align(
                  alignment: Alignment.center,
                  child: lcdContent,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CdLcdDotMatrixPainter extends CustomPainter {
  final Color dotColor;

  const _CdLcdDotMatrixPainter({required this.dotColor});

  @override
  void paint(Canvas canvas, Size size) {
    if (GpuBudget.isGpuSaverActive) return;
    final paint = Paint()..color = dotColor;
    const double pitch = 5.0;
    for (double y = 3.0; y < size.height; y += pitch) {
      for (double x = 3.0; x < size.width; x += pitch) {
        canvas.drawRect(Rect.fromLTWH(x, y, 1.2, 1.2), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CdLcdDotMatrixPainter oldDelegate) =>
      oldDelegate.dotColor != dotColor;
}

/// Clean left-aligned track title/artist header paired with a metallic recessed
/// favorite button.
class _CdTrackHeaderRow extends StatelessWidget {
  final PlayerThemeProps props;
  final _CdChassisPalette chassis;
  final bool isCompact;

  const _CdTrackHeaderRow({
    required this.props,
    required this.chassis,
    required this.isCompact,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final song = props.state.currentSong;
    final isFav = song?.isFavorite == true;

    return Row(
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
                  fontSize:
                      isCompact ? AppFontSize.bodyLarge : AppFontSize.title,
                  fontWeight: FontWeight.w800,
                  color: chassis.inkPrimary,
                  letterSpacing: AppTracking.title,
                ),
              ),
              const SizedBox(height: AppSpacing.s2),
              Text(
                song?.artist ?? context.l10n.unknownArtist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize:
                      isCompact ? AppFontSize.label : AppFontSize.bodySmall,
                  fontWeight: FontWeight.w600,
                  color: chassis.inkSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [chassis.metalKeyTop, chassis.metalKeyBottom],
            ),
            borderRadius: AppRadii.r10All,
            border: Border.all(
              color: isFav
                  ? p.favorite.withValues(alpha: 0.55)
                  : chassis.metalKeyBorder,
              width: 1.0,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            color: AppColors.specularAt(0.0),
            child: PlayerAnimatedFavoriteButton(
              isFavorite: isFav,
              semanticLabel: isFav ? context.l10n.unlike : context.l10n.like,
              favoriteColor: p.favorite,
              inactiveColor: chassis.inkSecondary,
              iconSize: 21,
              onTap: () {
                if (song != null) {
                  props.cubit.toggleFavorite(song.id);
                }
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Slim metallic Discman seek bar driven strictly by [BlocSelector].
/// Honours the user's [PlayerSliderStyle] and [waveformSeekBarEnabled] settings.
class _CdMetallicSeekBar extends StatefulWidget {
  final PlayerThemeProps props;
  final _CdChassisPalette chassis;
  final bool isCompact;

  const _CdMetallicSeekBar({
    required this.props,
    required this.chassis,
    required this.isCompact,
  });

  @override
  State<_CdMetallicSeekBar> createState() => _CdMetallicSeekBarState();
}

class _CdMetallicSeekBarState extends State<_CdMetallicSeekBar> {
  double? _dragValue;
  int? _lastSongId;
  String? _lastFilePath;
  Future<List<double>>? _cachedWaveformFuture;

  @override
  void didUpdateWidget(covariant _CdMetallicSeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.props.state.currentSong?.id !=
        oldWidget.props.state.currentSong?.id) {
      _dragValue = null;
      _cachedWaveformFuture = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final song = widget.props.state.currentSong;
    final duration = widget.props.state.duration;
    final (:sliderStyle, :waveformEnabled) = context.select<SettingsCubit,
        ({PlayerSliderStyle sliderStyle, bool waveformEnabled})>(
      (c) => (
        sliderStyle: c.state.playerSliderStyle,
        waveformEnabled: c.state.waveformSeekBarEnabled,
      ),
    );

    return BlocSelector<PlayerCubit, PlayerState,
        ({Duration position, bool isPlaying, bool isBuffering})>(
      selector: (s) => (
        position: s.position,
        isPlaying: s.isPlaying,
        isBuffering: s.isBuffering,
      ),
      builder: (context, playback) {
        final maxMs = duration.inMilliseconds.toDouble();
        final currentMs = playback.position.inMilliseconds.toDouble();
        final effectiveMs =
            (_dragValue ?? currentMs).clamp(0.0, maxMs > 0 ? maxMs : 1.0);
        final effectiveDur = _dragValue != null
            ? Duration(milliseconds: _dragValue!.round())
            : playback.position;

        Duration clampSeek(Duration delta) {
          final target = effectiveDur + delta;
          if (target < Duration.zero) return Duration.zero;
          if (target > duration) return duration;
          return target;
        }

        String labelFor(Duration d) => '${Formatters.formatDuration(d)} / '
            '${Formatters.formatDuration(duration)}';

        final showWaveform = waveformEnabled &&
            sliderStyle == PlayerSliderStyle.normal &&
            song != null;

        if (showWaveform) {
          if (_lastSongId != song.id || _lastFilePath != song.path) {
            _lastSongId = song.id;
            _lastFilePath = song.path;
            _cachedWaveformFuture = null;
          }
          final instant = WaveformService.instance.getInstantWaveform(
            songId: song.id,
            filePath: song.path,
          );
          _cachedWaveformFuture ??= WaveformService.instance
              .getWaveform(songId: song.id, filePath: song.path);

          return FutureBuilder<List<double>>(
            key: ValueKey('cd_wf_${song.id}'),
            initialData: instant,
            future: _cachedWaveformFuture,
            builder: (context, snap) {
              final samples = (snap.hasData && snap.data!.isNotEmpty)
                  ? snap.data!
                  : instant;
              return WaveformSeekBar(
                position: playback.position,
                duration: duration,
                onSeek: widget.props.cubit.seek,
                samples: samples,
                enabled: !playback.isBuffering,
                activeColor: widget.chassis.sliderActive,
                inactiveColor: widget.chassis.sliderInactive,
                height: widget.isCompact ? 26.0 : 32.0,
              );
            },
          );
        }

        return Semantics(
          container: true,
          slider: true,
          label: context.l10n.seekLabel,
          value: labelFor(effectiveDur),
          increasedValue: labelFor(clampSeek(const Duration(seconds: 10))),
          decreasedValue: labelFor(clampSeek(const Duration(seconds: -10))),
          onIncrease: playback.isBuffering
              ? null
              : () => widget.props.cubit
                  .seek(clampSeek(const Duration(seconds: 10))),
          onDecrease: playback.isBuffering
              ? null
              : () => widget.props.cubit
                  .seek(clampSeek(const Duration(seconds: -10))),
          excludeSemantics: true,
          child: SizedBox(
            height: widget.isCompact ? 30.0 : 34.0,
            child: PulsrSlider(
              value: effectiveMs,
              min: 0.0,
              max: maxMs > 0 ? maxMs : 1.0,
              height: widget.isCompact ? 30.0 : 34.0,
              activeColor: widget.chassis.sliderActive,
              inactiveColor: widget.chassis.sliderInactive,
              thumbColor: widget.chassis.sliderThumb,
              sliderStyle: sliderStyle,
              isWavy: sliderStyle == PlayerSliderStyle.wavy,
              animateWave: playback.isPlaying && !playback.isBuffering,
              onChangeStart: (val) {
                PulsrHaptics.selectionClick();
                setState(() => _dragValue = val);
              },
              onChanged: (val) => setState(() => _dragValue = val),
              onChangeEnd: (val) {
                widget.props.cubit.seek(Duration(milliseconds: val.round()));
                setState(() => _dragValue = null);
              },
              onChangeCancel: () => setState(() => _dragValue = null),
            ),
          ),
        );
      },
    );
  }
}

/// Precision-machined rectangular brushed-metal Discman transport keys:
/// `[Shuffle]  [|<<]  [  ▶ / ❚❚  ]  [>>|]  [Repeat]`
class _CdMetalTransportBar extends StatelessWidget {
  final PlayerThemeProps props;
  final _CdChassisPalette chassis;
  final bool isCompact;

  const _CdMetalTransportBar({
    required this.props,
    required this.chassis,
    required this.isCompact,
  });

  @override
  Widget build(BuildContext context) {
    final state = props.state;
    final cubit = props.cubit;
    final activeColor = props.activeColor;
    final isPlaying = state.isPlaying;
    final isBuffering = state.isBuffering;
    final isShuffle = state.isShuffle;
    final repeatMode = state.repeatMode;
    final keyRadius = resolveCustomRadius(context, AppRadii.r8).clamp(
      AppRadii.r4,
      AppRadii.r14,
    );
    final keyHeight = isCompact ? AppSpacing.minTouchTarget : 52.0;
    final sideKeyWidth = isCompact ? 50.0 : 56.0;
    final playKeyWidth = isCompact ? 80.0 : 94.0;
    final auxKeyWidth = AppSpacing.minTouchTarget;

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 1. Shuffle rectangular metal key
          _BrushedMetalKey(
            width: auxKeyWidth,
            height: keyHeight,
            radius: keyRadius,
            chassis: chassis,
            activeColor: activeColor,
            isActive: isShuffle,
            tooltip: context.l10n.shuffle,
            onTap: () {
              PulsrHaptics.selection();
              cubit.toggleShuffle();
            },
            child: Icon(
              Icons.shuffle_rounded,
              size: 19,
              color: isShuffle ? activeColor : chassis.inkSecondary,
            ),
          ),
          const SizedBox(width: AppSpacing.s8),

          // 2. Previous |<< rectangular metal key
          _BrushedMetalKey(
            width: sideKeyWidth,
            height: keyHeight,
            radius: keyRadius,
            chassis: chassis,
            activeColor: activeColor,
            tooltip: context.l10n.previous,
            onTap: state.hasPreviousNeighbour
                ? () {
                    PulsrHaptics.light();
                    cubit.previous();
                  }
                : null,
            child: Icon(
              Icons.skip_previous_rounded,
              size: 25,
              color: state.hasPreviousNeighbour
                  ? chassis.inkPrimary
                  : chassis.inkSecondary.withValues(alpha: 0.40),
            ),
          ),
          const SizedBox(width: AppSpacing.s8),

          // 3. Hero Play / Pause brushed-titanium rectangular actuator key
          _BrushedMetalKey(
            width: playKeyWidth,
            height: keyHeight,
            radius: keyRadius,
            chassis: chassis,
            activeColor: activeColor,
            isHero: true,
            isActive: isPlaying,
            tooltip: isPlaying ? context.l10n.pause : context.l10n.play,
            onTap: () {
              PulsrHaptics.lightImpact();
              cubit.togglePlayPause();
            },
            child: isBuffering
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: chassis.heroKeyInk,
                    ),
                  )
                : Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 30,
                    color: chassis.heroKeyInk,
                  ),
          ),
          const SizedBox(width: AppSpacing.s8),

          // 4. Next >>| rectangular metal key
          _BrushedMetalKey(
            width: sideKeyWidth,
            height: keyHeight,
            radius: keyRadius,
            chassis: chassis,
            activeColor: activeColor,
            tooltip: context.l10n.next,
            onTap: state.hasNextNeighbour
                ? () {
                    PulsrHaptics.light();
                    cubit.next();
                  }
                : null,
            child: Icon(
              Icons.skip_next_rounded,
              size: 25,
              color: state.hasNextNeighbour
                  ? chassis.inkPrimary
                  : chassis.inkSecondary.withValues(alpha: 0.40),
            ),
          ),
          const SizedBox(width: AppSpacing.s8),

          // 5. Repeat rectangular metal key
          _BrushedMetalKey(
            width: auxKeyWidth,
            height: keyHeight,
            radius: keyRadius,
            chassis: chassis,
            activeColor: activeColor,
            isActive: repeatMode != PlayerRepeatMode.off,
            tooltip: context.l10n.repeat,
            onTap: () {
              PulsrHaptics.selection();
              cubit.toggleRepeat();
              final nextMode = switch (repeatMode) {
                PlayerRepeatMode.off => PlayerRepeatMode.all,
                PlayerRepeatMode.all => PlayerRepeatMode.one,
                PlayerRepeatMode.one => PlayerRepeatMode.off,
              };
              final nextLabel = switch (nextMode) {
                PlayerRepeatMode.one => context.l10n.repeatOne,
                PlayerRepeatMode.all => context.l10n.repeatAll,
                PlayerRepeatMode.off => context.l10n.repeatOff,
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
            child: Icon(
              repeatMode == PlayerRepeatMode.one
                  ? Icons.repeat_one_rounded
                  : Icons.repeat_rounded,
              size: 19,
              color: repeatMode != PlayerRepeatMode.off
                  ? activeColor
                  : chassis.inkSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Single precision-machined rectangular brushed-metal Discman button with
/// metallic sheen gradient, 1px top specular bevel, >= 48dp hit target, and
/// active optical indicator bar.
class _BrushedMetalKey extends StatelessWidget {
  final double width;
  final double height;
  final double radius;
  final _CdChassisPalette chassis;
  final Color activeColor;
  final bool isHero;
  final bool isActive;
  final String tooltip;
  final VoidCallback? onTap;
  final Widget child;

  const _BrushedMetalKey({
    required this.width,
    required this.height,
    required this.radius,
    required this.chassis,
    required this.activeColor,
    required this.tooltip,
    required this.onTap,
    required this.child,
    this.isHero = false,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = AppRadii.circular(radius);
    return Semantics(
      button: true,
      toggled: isActive,
      enabled: onTap != null,
      label: tooltip,
      excludeSemantics: true,
      child: Material(
        color: AppColors.specularAt(0.0),
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius,
          child: Ink(
            width: math.max(width, AppSpacing.minTouchTarget),
            height: math.max(height, AppSpacing.minTouchTarget),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isHero
                    ? [chassis.heroKeyTop, chassis.heroKeyBottom]
                    : [
                        chassis.metalKeyTop,
                        chassis.metalKeyMid,
                        chassis.metalKeyBottom,
                      ],
              ),
              borderRadius: borderRadius,
              border: Border.all(
                color: isActive && !isHero
                    ? activeColor.withValues(alpha: 0.65)
                    : chassis.metalKeyBorder,
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.scrimAt(chassis.isDark ? 0.42 : 0.16),
                  blurRadius: isHero ? 10 : 6,
                  offset: const Offset(0, 2),
                ),
                if (isHero && isActive)
                  BoxShadow(
                    color: activeColor.withValues(alpha: 0.24),
                    blurRadius: 12,
                    spreadRadius: -2,
                  ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Crisp 1px top specular chamfer highlight.
                PositionedDirectional(
                  top: 0,
                  start: 3,
                  end: 3,
                  child: Container(
                    height: 1.0,
                    color: chassis.metalKeyTopSpecular,
                  ),
                ),
                child,
                if (isActive)
                  PositionedDirectional(
                    bottom: 4,
                    child: Container(
                      width: isHero ? 18 : 10,
                      height: 2.2,
                      decoration: BoxDecoration(
                        color: activeColor,
                        borderRadius: AppRadii.full,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact secondary Discman action strip housing Lyrics, Queue, and the
/// expandable [PlayerToolsTriggerButton] (which tucks A/B Loop and the 7-icon
/// dock cleanly into [PlayerToolsSheet]).
class _CdSecondaryActionStrip extends StatelessWidget {
  final PlayerThemeProps props;
  final _CdChassisPalette chassis;
  final bool isInSplitView;

  const _CdSecondaryActionStrip({
    required this.props,
    required this.chassis,
    required this.isInSplitView,
  });

  @override
  Widget build(BuildContext context) {
    final state = props.state;
    final cubit = props.cubit;
    final song = state.currentSong;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: chassis.actionDeckSurface,
        borderRadius: AppRadii.r12All,
        border: Border.all(color: chassis.hairline, width: 1.0),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (!isInSplitView)
            PlayerIconActionButton(
              icon: Icons.lyrics_rounded,
              tooltip: context.l10n.lyrics,
              isActive: state.isLyricsVisible,
              iconColor: chassis.inkSecondary,
              activeColor: props.activeColor,
              showActiveDot: true,
              onTap: cubit.toggleLyricsVisibility,
            ),
          if (isInSplitView)
            PlayerIconActionButton(
              icon: Icons.high_quality_rounded,
              tooltip: context.l10n.audioQuality,
              iconColor: chassis.inkSecondary,
              activeColor: props.activeColor,
              onTap: song == null
                  ? null
                  : () => AudioQualitySheet.show(
                        context,
                        song,
                        props.activeColor,
                      ),
            ),
          if (!isInSplitView)
            PlayerIconActionButton(
              icon: Icons.queue_music_rounded,
              tooltip: context.l10n.queue,
              isActive: state.isQueueVisible,
              iconColor: chassis.inkSecondary,
              activeColor: props.activeColor,
              showActiveDot: true,
              onTap: cubit.toggleQueueVisibility,
            ),
          PlayerToolsTriggerButton(
            props: props,
            iconColor: chassis.inkSecondary,
          ),
        ],
      ),
    );
  }
}
