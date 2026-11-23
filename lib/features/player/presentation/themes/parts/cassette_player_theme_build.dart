part of '../cassette_player_theme.dart';

/// Physical Walkman / hi-fi tape deck anodized chassis palette supporting
/// both dark anodized gunmetal and vintage brushed silver-aluminum light mode.
class _CassetteDeckPalette {
  final bool isDark;
  final Color chassisTop;
  final Color chassisMid;
  final Color chassisBottom;
  final Color bayRecess;
  final Color bayBorder;
  final Color panelSurface;
  final Color panelBorder;
  final Color keyFaceTop;
  final Color keyFaceBottom;
  final Color keyDepressedTop;
  final Color keyDepressedBottom;
  final Color keyBorder;
  final Color keyTray;
  final Color primaryInk;
  final Color secondaryInk;
  final Color vfdBackground;
  final Color vfdBorder;
  final Color ledGreen;
  final Color ledAmber;
  final Color ledRed;
  final Color accentTone;
  final Color screwColor;
  final Color seamHighlight;
  final Color seamShadow;

  const _CassetteDeckPalette({
    required this.isDark,
    required this.chassisTop,
    required this.chassisMid,
    required this.chassisBottom,
    required this.bayRecess,
    required this.bayBorder,
    required this.panelSurface,
    required this.panelBorder,
    required this.keyFaceTop,
    required this.keyFaceBottom,
    required this.keyDepressedTop,
    required this.keyDepressedBottom,
    required this.keyBorder,
    required this.keyTray,
    required this.primaryInk,
    required this.secondaryInk,
    required this.vfdBackground,
    required this.vfdBorder,
    required this.ledGreen,
    required this.ledAmber,
    required this.ledRed,
    required this.accentTone,
    required this.screwColor,
    required this.seamHighlight,
    required this.seamShadow,
  });

  factory _CassetteDeckPalette.resolve(
    BuildContext context,
    Color activeColor,
  ) {
    final p = context.palette;
    final surface = context.playerSurfacePalette;
    final isDark = p.isDark;
    final isHighContrast =
        p.isHighContrast || MediaQuery.highContrastOf(context);
    final accent = Color.lerp(AppColors.amberDeep, activeColor, 0.45)!;

    if (isDark) {
      return _CassetteDeckPalette(
        isDark: true,
        chassisTop: isHighContrast ? p.bg : PlayerMaterialColors.cassetteBodyTop,
        chassisMid:
            isHighContrast ? p.surface : PlayerMaterialColors.cassetteBodyMid,
        chassisBottom:
            isHighContrast ? p.bg : PlayerMaterialColors.cassetteWell,
        bayRecess: PlayerMaterialColors.immersiveBackdrop,
        bayBorder: isHighContrast
            ? p.borderStrong
            : PlayerMaterialColors.cassetteBodyBorder,
        panelSurface: isHighContrast
            ? p.surfaceContainer
            : PlayerMaterialColors.cassetteShell,
        panelBorder: isHighContrast
            ? p.borderStrong
            : PlayerMaterialColors.cassetteShellBorder,
        keyFaceTop: PlayerMaterialColors.cdWeightMid,
        keyFaceBottom: PlayerMaterialColors.cassetteShell,
        keyDepressedTop: PlayerMaterialColors.cassetteBodyBottom,
        keyDepressedBottom: PlayerMaterialColors.cassetteBodyMid,
        keyBorder: isHighContrast
            ? p.borderStrong
            : PlayerMaterialColors.cassetteBridgeBorder,
        keyTray: PlayerMaterialColors.immersiveBackdrop,
        primaryInk: surface.highContrastInk,
        secondaryInk: isHighContrast ? p.textSecondary : surface.mutedInk,
        vfdBackground: PlayerMaterialColors.cassetteWell,
        vfdBorder: isHighContrast
            ? p.borderStrong
            : PlayerMaterialColors.cassetteCapstanBorder,
        ledGreen: PlayerMaterialColors.cassetteVuNormal,
        ledAmber: AppColors.warning,
        ledRed: PlayerMaterialColors.cassetteVuPeak,
        accentTone: accent,
        screwColor: PlayerMaterialColors.cassetteScrew,
        seamHighlight: AppColors.specularAt(0.06),
        seamShadow: AppColors.scrimAt(0.45),
      );
    }

    // Light mode: brushed silver-anodized Sony WM-DD vintage Walkman chassis
    final silverTop = Color.lerp(p.bg, AppColors.surfaceGreyLight, 0.55)!;
    final silverMid = Color.lerp(p.surface, AppColors.discSilver, 0.16)!;
    final silverBottom =
        Color.lerp(p.surfaceContainer, AppColors.discSilver, 0.28)!;
    final deepAccent = Color.lerp(p.textPrimary, accent, 0.65)!;

    return _CassetteDeckPalette(
      isDark: false,
      chassisTop: isHighContrast ? p.bg : silverTop,
      chassisMid: isHighContrast ? p.surface : silverMid,
      chassisBottom: isHighContrast ? p.surfaceContainer : silverBottom,
      bayRecess: PlayerMaterialColors.cassetteWell,
      bayBorder: isHighContrast
          ? p.borderStrong
          : AppColors.discSteel.withValues(alpha: 0.45),
      panelSurface: isHighContrast
          ? p.surface
          : Color.lerp(p.surface, AppColors.surfaceGreyLight, 0.35)!,
      panelBorder: isHighContrast
          ? p.borderStrong
          : AppColors.discSteel.withValues(alpha: 0.28),
      keyFaceTop: AppColors.surfaceGreyLight,
      keyFaceBottom: Color.lerp(AppColors.discSilver, p.surfaceContainer, 0.45)!,
      keyDepressedTop: Color.lerp(AppColors.discAluminum, p.surface, 0.35)!,
      keyDepressedBottom: AppColors.discSilver,
      keyBorder: isHighContrast
          ? p.borderStrong
          : AppColors.discSteel.withValues(alpha: 0.42),
      keyTray: Color.lerp(AppColors.discGraphite, p.textPrimary, 0.35)!,
      primaryInk: p.textPrimary,
      secondaryInk: p.textSecondary,
      vfdBackground: PlayerMaterialColors.cassetteWell,
      vfdBorder: isHighContrast
          ? p.borderStrong
          : AppColors.discSteel.withValues(alpha: 0.42),
      ledGreen: AppColors.emeraldDeep,
      ledAmber: AppColors.warning,
      ledRed: AppColors.error,
      accentTone: isHighContrast ? p.accent : deepAccent,
      screwColor: AppColors.discSteel,
      seamHighlight: AppColors.specularAt(0.65),
      seamShadow: AppColors.scrimAt(0.14),
    );
  }
}

extension _CassettePlayerThemeBuild on _CassettePlayerThemeState {
  Widget _buildBody(BuildContext context) {
    final state = widget.props.state;
    final activeColor = widget.props.activeColor;
    final song = state.currentSong;
    final deckPalette = _CassetteDeckPalette.resolve(context, activeColor);
    final customRadius = resolveCustomRadius(context, AppRadii.r18);
    final customGlow = resolveCustomGlow(context);

    final (
      :visualizerStyle,
      :sliderStyle,
      :settingsState,
    ) = context.select<
        SettingsCubit,
        ({
          VisualizerStyle visualizerStyle,
          PlayerSliderStyle sliderStyle,
          SettingsState settingsState,
        })>((c) => (
          visualizerStyle: c.state.visualizerStyle,
          sliderStyle: c.state.playerSliderStyle,
          settingsState: c.state,
        ));

    final telemetry = formatPlayerAudioTelemetry(song, settingsState);

    // The deck is one painted object, so it publishes one semantics node
    // instead of decorative sticker print.
    final deckStatus = state.isPlaying
        ? context.l10n.ambientStatusPlaying
        : context.l10n.ambientStatusPaused;
    final deckLabel = song == null
        ? '${context.l10n.nowPlaying}, $deckStatus'
        : '${context.l10n.nowPlayingSemantics(song.title, song.artist)}, '
            '$deckStatus';

    return PlayerSurfaceShell(
      props: widget.props,
      overlayBackgroundColor: deckPalette.chassisMid.withValues(alpha: 0.96),
      background: RepaintBoundary(
        child: CustomPaint(
          painter: _AnodizedDeckChassisPainter(
            topColor: deckPalette.chassisTop,
            midColor: deckPalette.chassisMid,
            bottomColor: deckPalette.chassisBottom,
            seamHighlight: deckPalette.seamHighlight,
            seamShadow: deckPalette.seamShadow,
            screwColor: deckPalette.screwColor,
            glowColor: customGlow
                ? activeColor.withValues(alpha: deckPalette.isDark ? 0.22 : 0.12)
                : deckPalette.ledAmber
                    .withValues(alpha: deckPalette.isDark ? 0.08 : 0.04),
          ),
        ),
      ),
      topBarBuilder: (context, metrics) => PlayerCompactTopBar(
        foregroundColor: deckPalette.primaryInk,
        buttonSurfaceColor: deckPalette.panelSurface.withValues(alpha: 0.85),
        buttonBorderColor: deckPalette.panelBorder,
        center: _CassetteDeckNameplate(
          palette: deckPalette,
          telemetry: telemetry,
          isPlaying: state.isPlaying,
          onTap: song == null
              ? null
              : () => AudioQualitySheet.show(context, song, activeColor),
        ),
        trailing: [
          PlayerIconActionButton(
            icon: Icons.more_horiz_rounded,
            tooltip: context.l10n.moreOptions,
            iconColor: deckPalette.primaryInk,
            surfaceColor: deckPalette.panelSurface.withValues(alpha: 0.85),
            borderColor: deckPalette.panelBorder,
            onTap: song == null
                ? null
                : () => SongOptionsSheet.show(context, song: song),
          ),
        ],
      ),
      builder: (context, metrics, isInSplitView, isPreview) {
        final showVisualizer = visualizerStyle != VisualizerStyle.off &&
            !state.isLyricsVisible &&
            !state.isQueueVisible &&
            !isInSplitView &&
            !isPreview;
        final textScale =
            MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 2.0);
        final isShort = metrics.isShortHeight ||
            (isInSplitView && metrics.constraints.maxHeight < 560);
        final isVeryShort = metrics.isVeryShortHeight ||
            (isInSplitView && metrics.constraints.maxHeight < 460);
        final horizontalPad =
            (metrics.constraints.maxWidth * 0.045).clamp(12.0, 24.0);
        final bayRadius = customRadius.clamp(8.0, 30.0);

        Widget buildRecessedBay({double? forcedMaxHeight}) {
          return LayoutBuilder(
            builder: (context, stageConstraints) {
              final double visualizerH = showVisualizer
                  ? (visualizerStyle == VisualizerStyle.circular ? 52.0 : 28.0)
                  : 0.0;
              final double visualizerSpace =
                  showVisualizer ? visualizerH + AppSpacing.s6 : 0.0;
              final double capH = forcedMaxHeight ?? stageConstraints.maxHeight;
              final double availableH = math.max(0.0, capH - visualizerSpace);

              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    key: const ValueKey('cassette_view'),
                    child: SizedBox(
                      height: availableH,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: horizontalPad,
                          vertical: AppSpacing.xxs,
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(AppSpacing.xs),
                          decoration: BoxDecoration(
                            color: deckPalette.bayRecess,
                            borderRadius: AppRadii.circular(bayRadius),
                            border: Border.all(
                              color: deckPalette.bayBorder,
                              width: 1.8,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.scrimAt(0.55),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                              if (customGlow)
                                BoxShadow(
                                  color: activeColor.withValues(alpha: 0.28),
                                  blurRadius: 28,
                                  spreadRadius: 1,
                                ),
                            ],
                          ),
                          child: Semantics(
                            container: true,
                            label: deckLabel,
                            child: Hero(
                              tag: widget.props.heroTag,
                              child: _CassetteBody(
                                props: widget.props,
                                activeColor: activeColor,
                                spoolController: _spoolController,
                                isLandscape: metrics.isLandscape,
                                isTablet: metrics.isTablet,
                              ),
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
                          vertical: AppSpacing.xxs,
                        ),
                        child: AudioVisualizer(
                          style: visualizerStyle,
                          color: activeColor,
                          height: visualizerH,
                          isPlaying: state.isPlaying,
                          audioSessionId: state.audioSessionId,
                          trackSeed: song?.id,
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        }

        final vuMeterPanel = _DeckSegmentedLedVuMeter(
          palette: deckPalette,
          isPlaying: state.isPlaying,
          isPreview: isPreview,
          isCompact: isShort,
        );

        final trackStrip = _CassetteVfdTrackStrip(
          props: widget.props,
          palette: deckPalette,
          isCompact: isShort,
          isPreview: isPreview,
        );

        final tapeScrubber = _CassetteMagneticTapeScrubber(
          props: widget.props,
          palette: deckPalette,
          sliderStyle: sliderStyle,
          isCompact: isShort,
        );

        final mechanicalKeys = _CassetteMechanicalDeckKeys(
          props: widget.props,
          palette: deckPalette,
          isCompact: isShort,
          isTablet: metrics.isTablet,
          customGlow: customGlow,
        );

        final functionSwitches = _CassetteFunctionSwitches(
          props: widget.props,
          palette: deckPalette,
          isInSplitView: isInSplitView,
        );

        final Widget lowerDeckConsole = Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPad),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              vuMeterPanel,
              SizedBox(height: isVeryShort ? AppSpacing.xxs : AppSpacing.xs),
              trackStrip,
              SizedBox(height: isVeryShort ? AppSpacing.xxs : AppSpacing.s6),
              tapeScrubber,
              if (!isPreview && song?.source == SongSource.radio) ...[
                const SizedBox(height: AppSpacing.xs),
                RadioNowPlayingRecommendations(
                  props: widget.props,
                  cubit: widget.props.cubit,
                  metrics: metrics,
                ),
                const SizedBox(height: AppSpacing.xs),
              ] else if (!isPreview && state.bookmarkPosition != null) ...[
                const SizedBox(height: AppSpacing.xs),
                PlayerBookmarkPromptBanner(
                  cubit: widget.props.cubit,
                  position: state.bookmarkPosition!,
                ),
                const SizedBox(height: AppSpacing.xs),
              ] else ...[
                SizedBox(
                  height: isVeryShort ? AppSpacing.xs : AppSpacing.s10,
                ),
              ],
              mechanicalKeys,
              if (!isPreview &&
                  (isInSplitView || metrics.isTablet) &&
                  !isVeryShort) ...[
                const SizedBox(height: AppSpacing.xs),
                PlayerVolumeBar(
                  cubit: widget.props.cubit,
                  activeColor: deckPalette.ledAmber,
                ),
              ],
              if (!isPreview) ...[
                SizedBox(
                  height: isVeryShort ? AppSpacing.xxs : AppSpacing.s8,
                ),
                functionSwitches,
              ],
              SizedBox(height: isVeryShort ? AppSpacing.xxs : AppSpacing.xs),
            ],
          ),
        );

        if (isPreview) {
          return Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Column(
              children: [
                Expanded(child: buildRecessedBay()),
                lowerDeckConsole,
              ],
            ),
          );
        }

        if (isInSplitView) {
          return Column(
            children: [
              const SizedBox(height: AppSpacing.xs),
              Expanded(child: buildRecessedBay()),
              lowerDeckConsole,
            ],
          );
        }

        if (metrics.isLandscape) {
          final topInset = MediaQuery.paddingOf(context).top + 52.0;
          return SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsetsDirectional.only(
                top: topInset,
                start: AppSpacing.sm,
                end: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Center(child: buildRecessedBay()),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    flex: 5,
                    child: Center(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: lowerDeckConsole,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // Portrait: scroll fallback on short viewports or large text scales.
        final topClearance = MediaQuery.paddingOf(context).top + 56.0;
        final double scrollThreshold = 620.0 + (textScale - 1.0) * 140.0;
        if (metrics.constraints.maxHeight < scrollThreshold) {
          final double bayCap =
              (metrics.constraints.maxHeight * 0.36).clamp(160.0, 270.0);
          return SafeArea(
            top: false,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: EdgeInsets.only(top: topClearance),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    buildRecessedBay(forcedMaxHeight: bayCap),
                    const SizedBox(height: AppSpacing.xs),
                    lowerDeckConsole,
                  ],
                ),
              ),
            ),
          );
        }

        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(top: topClearance),
            child: Column(
              children: [
                Expanded(child: buildRecessedBay()),
                const SizedBox(height: AppSpacing.xs),
                lowerDeckConsole,
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Top engraved aluminum deck nameplate with live format telemetry.
class _CassetteDeckNameplate extends StatelessWidget {
  final _CassetteDeckPalette palette;
  final PlayerAudioTelemetry telemetry;
  final bool isPlaying;
  final VoidCallback? onTap;

  const _CassetteDeckNameplate({
    required this.palette,
    required this.telemetry,
    required this.isPlaying,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = telemetry.compactBadge.isNotEmpty
        ? telemetry.compactBadge
        : context.l10n.cassettePulsrTape;

    final plate = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.s6,
      ),
      decoration: BoxDecoration(
        color: palette.vfdBackground,
        borderRadius: AppRadii.r8All,
        border: Border.all(
          color: isPlaying
              ? palette.ledGreen.withValues(alpha: 0.45)
              : palette.vfdBorder,
          width: 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isPlaying ? palette.ledGreen : palette.ledAmber,
              boxShadow: [
                BoxShadow(
                  color: (isPlaying ? palette.ledGreen : palette.ledAmber)
                      .withValues(alpha: 0.8),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: AppFontSize.caption,
                fontWeight: FontWeight.w800,
                letterSpacing: AppTracking.overline,
                color: isPlaying
                    ? palette.ledGreen
                    : AppColors.onGiltLight.withValues(alpha: 0.82),
              ),
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return plate;

    return Semantics(
      button: true,
      label: context.l10n.audioQuality,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: AppRadii.r8All,
        onTap: () {
          PulsrHaptics.selectionClick();
          onTap!();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppSpacing.minTouchTarget,
            minWidth: AppSpacing.minTouchTarget,
          ),
          child: Center(child: plate),
        ),
      ),
    );
  }
}

/// Twin L/R segmented glowing LED peak-meter bars (green -> amber -> red).
/// Zero tickers under Reduce Motion or Preview.
class _DeckSegmentedLedVuMeter extends StatefulWidget {
  final _CassetteDeckPalette palette;
  final bool isPlaying;
  final bool isPreview;
  final bool isCompact;

  const _DeckSegmentedLedVuMeter({
    required this.palette,
    required this.isPlaying,
    required this.isPreview,
    required this.isCompact,
  });

  @override
  State<_DeckSegmentedLedVuMeter> createState() =>
      _DeckSegmentedLedVuMeterState();
}

class _DeckSegmentedLedVuMeterState extends State<_DeckSegmentedLedVuMeter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _meterController;
  double _leftPeak = 0.12;
  double _rightPeak = 0.12;
  int _leftHold = 0;
  int _rightHold = 0;
  bool? _lastAllowMotion;

  @override
  void initState() {
    super.initState();
    _meterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  bool _allowMotion(BuildContext context) =>
      !widget.isPreview &&
      !PlayerThemePreviewScope.of(context) &&
      PulsrMotion.shouldAnimate(context) &&
      context.motionEnabled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMeter();
  }

  @override
  void didUpdateWidget(covariant _DeckSegmentedLedVuMeter oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMeter();
  }

  void _syncMeter({bool? allowMotionOverride}) {
    final allowMotion = allowMotionOverride ?? _allowMotion(context);
    if (widget.isPlaying && allowMotion) {
      if (!_meterController.isAnimating) {
        _meterController.repeat(reverse: true);
      }
    } else {
      if (_meterController.isAnimating) {
        _meterController.stop();
      }
      if (!allowMotion) {
        _meterController.value = 0.0;
      } else if (_meterController.value > 0.0) {
        _meterController.animateTo(0.0, duration: context.motionMs(260));
      }
    }
  }

  @override
  void dispose() {
    _meterController.dispose();
    super.dispose();
  }

  void _updatePeaks(double left, double right) {
    if (left >= _leftPeak) {
      _leftPeak = left;
      _leftHold = 16;
    } else if (_leftHold > 0) {
      _leftHold--;
    } else {
      _leftPeak = math.max(0.10, _leftPeak - 0.03);
    }

    if (right >= _rightPeak) {
      _rightPeak = right;
      _rightHold = 16;
    } else if (_rightHold > 0) {
      _rightHold--;
    } else {
      _rightPeak = math.max(0.10, _rightPeak - 0.03);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allowMotion = _allowMotion(context);
    if (_lastAllowMotion != allowMotion) {
      _lastAllowMotion = allowMotion;
      if (!allowMotion) {
        if (_meterController.isAnimating) {
          _meterController.stop();
        }
        _meterController.value = 0.0;
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _syncMeter(allowMotionOverride: allowMotion);
        });
      }
    }

    final segHeight = widget.isCompact ? 6.0 : 7.5;
    final totalHeight = segHeight * 2 + AppSpacing.s4;

    return ExcludeSemantics(
      child: MediaQuery.withNoTextScaling(
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: widget.isCompact ? AppSpacing.s4 : AppSpacing.s6,
          ),
          decoration: BoxDecoration(
            color: widget.palette.vfdBackground,
            borderRadius: AppRadii.r10All,
            border: Border.all(color: widget.palette.vfdBorder, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: AppColors.scrimAt(0.42),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: RepaintBoundary(
            child: Row(
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      height: segHeight,
                      width: 16,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'L',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: AppFontSize.caption,
                          fontWeight: FontWeight.w900,
                          color: widget.isPlaying
                              ? widget.palette.ledAmber
                              : AppColors.onGiltLight.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s4),
                    Container(
                      height: segHeight,
                      width: 16,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'R',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: AppFontSize.caption,
                          fontWeight: FontWeight.w900,
                          color: widget.isPlaying
                              ? widget.palette.ledAmber
                              : AppColors.onGiltLight.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: AppSpacing.s6),
                Expanded(
                  child: SizedBox(
                    height: totalHeight,
                    child: CustomPaint(
                      painter: _DeckSegmentedLedVuPainter(
                        controller: _meterController,
                        isPlaying: widget.isPlaying,
                        allowMotion: allowMotion,
                        palette: widget.palette,
                        isCompact: widget.isCompact,
                        state: this,
                      ),
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

class _DeckSegmentedLedVuPainter extends CustomPainter {
  static final Paint _shadowPaint = Paint()
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);
  static final Paint _cellPaint = Paint()..style = PaintingStyle.fill;

  final AnimationController controller;
  final bool isPlaying;
  final bool allowMotion;
  final _CassetteDeckPalette palette;
  final bool isCompact;
  final _DeckSegmentedLedVuMeterState state;

  _DeckSegmentedLedVuPainter({
    required this.controller,
    required this.isPlaying,
    required this.allowMotion,
    required this.palette,
    required this.isCompact,
    required this.state,
  }) : super(repaint: controller);

  @override
  void paint(Canvas canvas, Size size) {
    final double leftLevel;
    final double rightLevel;
    final double leftPeak;
    final double rightPeak;

    if (!isPlaying) {
      leftLevel = 0.0;
      rightLevel = 0.0;
      leftPeak = 0.0;
      rightPeak = 0.0;
    } else if (!allowMotion) {
      leftLevel = 0.64;
      rightLevel = 0.56;
      leftPeak = 0.80;
      rightPeak = 0.72;
    } else {
      final t = controller.value * 2 * math.pi;
      final base = math.sin(t).abs() * 0.42 +
          math.sin(t * 2.0 + 0.6).abs() * 0.22;
      final harmonicL = math.sin(t * 3.0 + 0.3).abs() * 0.20 +
          math.cos(t * 7.0).abs() * 0.10;
      final harmonicR = math.cos(t * 5.0 - 0.4).abs() * 0.20 +
          math.sin(t * 11.0).abs() * 0.10;
      leftLevel = (0.14 + base + harmonicL).clamp(0.06, 0.96);
      rightLevel = (0.14 + base + harmonicR).clamp(0.06, 0.96);
      state._updatePeaks(leftLevel, rightLevel);
      leftPeak = state._leftPeak;
      rightPeak = state._rightPeak;
    }

    final segHeight = isCompact ? 6.0 : 7.5;
    _paintRow(canvas, size.width, 0.0, segHeight, leftLevel, leftPeak);
    _paintRow(canvas, size.width, segHeight + AppSpacing.s4, segHeight,
        rightLevel, rightPeak);
  }

  void _paintRow(Canvas canvas, double width, double top, double height,
      double level, double peak) {
    const int totalSegments = 16;
    final int activeCount =
        (level * totalSegments).clamp(0, totalSegments).round();
    final int peakIdx = peak > 0.05
        ? (peak * totalSegments).clamp(1, totalSegments).round() - 1
        : -1;

    final segSlotWidth = width / totalSegments;
    final segWidth = segSlotWidth - 2.4;

    for (int idx = 0; idx < totalSegments; idx++) {
      final bool isLit = idx < activeCount;
      final bool isPeak = idx == peakIdx && idx >= activeCount;
      final Color segAccent = idx >= 13
          ? palette.ledRed
          : (idx >= 9 ? palette.ledAmber : palette.ledGreen);
      final Color cellColor = isLit
          ? segAccent
          : (isPeak
              ? segAccent.withValues(alpha: 0.92)
              : AppColors.specularAt(0.08));

      final segX = idx * segSlotWidth + 1.2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(segX, top, segWidth, height),
        const Radius.circular(AppRadii.r2),
      );

      if ((isLit || isPeak) && !GpuBudget.isGpuSaverActive) {
        final shadowPaint = _shadowPaint
          ..color = segAccent.withValues(alpha: 0.55);
        canvas.drawRRect(rect, shadowPaint);
      }

      final cellPaint = _cellPaint..color = cellColor;
      canvas.drawRRect(rect, cellPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _DeckSegmentedLedVuPainter oldDelegate) {
    return oldDelegate.isPlaying != isPlaying ||
        oldDelegate.allowMotion != allowMotion ||
        oldDelegate.palette != palette ||
        oldDelegate.isCompact != isCompact;
  }
}

/// Recessed OLED/VFD track readout panel with favorite toggle.
class _CassetteVfdTrackStrip extends StatelessWidget {
  final PlayerThemeProps props;
  final _CassetteDeckPalette palette;
  final bool isCompact;
  final bool isPreview;

  const _CassetteVfdTrackStrip({
    required this.props,
    required this.palette,
    required this.isCompact,
    required this.isPreview,
  });

  @override
  Widget build(BuildContext context) {
    final song = props.state.currentSong;
    final isFav = song?.isFavorite == true;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: MarqueeText(
                  text: song?.title ?? context.l10n.noTrackSelected,
                  textAlign: TextAlign.start,
                  style: TextStyle(
                    fontSize:
                        isCompact ? AppFontSize.bodyLarge : AppFontSize.title,
                    fontWeight: FontWeight.w800,
                    letterSpacing: AppTracking.title,
                    color: palette.primaryInk,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.s2),
              SizedBox(
                width: double.infinity,
                child: MarqueeText(
                  text: song?.artist ?? context.l10n.unknownArtist,
                  textAlign: TextAlign.start,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize:
                        isCompact ? AppFontSize.caption : AppFontSize.label,
                    fontWeight: FontWeight.w600,
                    letterSpacing: AppTracking.label,
                    color: palette.secondaryInk,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (!isPreview) ...[
          const SizedBox(width: AppSpacing.xs),
          Container(
            width: AppSpacing.minTouchTarget,
            height: AppSpacing.minTouchTarget,
            decoration: BoxDecoration(
              color: isFav
                  ? palette.ledAmber.withValues(alpha: 0.16)
                  : palette.panelSurface,
              borderRadius: AppRadii.r10All,
              border: Border.all(
                color: isFav
                    ? palette.ledAmber.withValues(alpha: 0.55)
                    : palette.panelBorder,
                width: 1.0,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Material(
              type: MaterialType.transparency,
              child: PlayerAnimatedFavoriteButton(
                isFavorite: isFav,
                semanticLabel: isFav ? context.l10n.unlike : context.l10n.like,
                favoriteColor: palette.ledAmber,
                inactiveColor: palette.secondaryInk,
                iconSize: 20,
                onTap: () {
                  if (song != null) {
                    props.cubit.toggleFavorite(song.id);
                  }
                },
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Tape-counter styled monospace elapsed/total readout + magnetic-tape scrubber.
class _CassetteMagneticTapeScrubber extends StatefulWidget {
  final PlayerThemeProps props;
  final _CassetteDeckPalette palette;
  final PlayerSliderStyle sliderStyle;
  final bool isCompact;

  const _CassetteMagneticTapeScrubber({
    required this.props,
    required this.palette,
    required this.sliderStyle,
    required this.isCompact,
  });

  @override
  State<_CassetteMagneticTapeScrubber> createState() =>
      _CassetteMagneticTapeScrubberState();
}

class _CassetteMagneticTapeScrubberState
    extends State<_CassetteMagneticTapeScrubber> {
  double? _dragValue;
  bool _showRemaining = false;
  Future<List<double>>? _waveformFuture;
  int? _lastSongId;
  String? _lastFilePath;

  @override
  void didUpdateWidget(covariant _CassetteMagneticTapeScrubber oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.props.state.currentSong?.id !=
        oldWidget.props.state.currentSong?.id) {
      _dragValue = null;
      _waveformFuture = null;
    }
  }

  Widget _buildTapeSlider({
    required double value,
    required double maxDuration,
    required bool isPlaying,
    required bool isBuffering,
  }) {
    final pal = widget.palette;
    return SizedBox(
      height: widget.isCompact ? 22.0 : 28.0,
      child: PulsrSlider(
        value: value,
        min: 0.0,
        max: maxDuration > 0 ? maxDuration : 1.0,
        height: widget.isCompact ? 22.0 : 28.0,
        activeColor: pal.ledAmber,
        inactiveColor: pal.primaryInk.withValues(alpha: 0.16),
        thumbColor: pal.ledGreen,
        sliderStyle: widget.sliderStyle,
        isWavy: widget.sliderStyle == PlayerSliderStyle.wavy,
        animateWave: isPlaying && !isBuffering,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final song = widget.props.state.currentSong;
    final duration = widget.props.state.duration;
    final isPlaying = widget.props.state.isPlaying;
    final isBuffering = widget.props.state.isBuffering;
    final waveformEnabled = context.select<SettingsCubit, bool>(
      (c) => c.state.waveformSeekBarEnabled,
    );

    return BlocSelector<PlayerCubit, PlayerState, Duration>(
      selector: (s) => s.position,
      builder: (context, livePosition) {
        final double maxDuration = duration.inMilliseconds.toDouble();
        final double currentMs = livePosition.inMilliseconds.toDouble();
        final double effectiveValue = (_dragValue ?? currentMs)
            .clamp(0.0, maxDuration > 0 ? maxDuration : 1.0);
        final bool isDragging = _dragValue != null;
        final Duration displayDuration = isDragging
            ? Duration(milliseconds: _dragValue!.round())
            : livePosition;
        final Duration remaining = duration > displayDuration
            ? duration - displayDuration
            : Duration.zero;

        final Widget trackWidget;
        if (waveformEnabled && song != null) {
          if (_lastSongId != song.id || _lastFilePath != song.path) {
            _lastSongId = song.id;
            _lastFilePath = song.path;
            _waveformFuture = null;
          }
          final instantSamples = WaveformService.instance.getInstantWaveform(
            songId: song.id,
            filePath: song.path,
          );
          _waveformFuture ??= WaveformService.instance.getWaveform(
            songId: song.id,
            filePath: song.path,
          );

          trackWidget = FutureBuilder<List<double>>(
            key: ValueKey('cassette_wf_${song.id}'),
            initialData: instantSamples,
            future: _waveformFuture,
            builder: (context, snapshot) {
              final samples = (snapshot.hasData && snapshot.data!.isNotEmpty)
                  ? snapshot.data!
                  : instantSamples;
              if (samples.isNotEmpty) {
                return WaveformSeekBar(
                  position: displayDuration,
                  duration: duration,
                  onSeek: (pos) => widget.props.cubit.seek(pos),
                  samples: samples,
                  enabled: !isBuffering,
                  activeColor: widget.palette.ledAmber,
                  height: widget.isCompact ? 24.0 : 32.0,
                );
              }
              return _buildTapeSlider(
                value: effectiveValue,
                maxDuration: maxDuration,
                isPlaying: isPlaying,
                isBuffering: isBuffering,
              );
            },
          );
        } else {
          trackWidget = _buildTapeSlider(
            value: effectiveValue,
            maxDuration: maxDuration,
            isPlaying: isPlaying,
            isBuffering: isBuffering,
          );
        }

        Duration clampSeek(Duration delta) {
          final target = displayDuration + delta;
          if (target < Duration.zero) return Duration.zero;
          if (target > duration) return duration;
          return target;
        }

        String seekLabelFor(Duration value) =>
            '${Formatters.formatDuration(value)} / '
            '${Formatters.formatDuration(duration)}';

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              container: true,
              slider: true,
              label: context.l10n.seekLabel,
              value: seekLabelFor(displayDuration),
              increasedValue:
                  seekLabelFor(clampSeek(const Duration(seconds: 10))),
              decreasedValue:
                  seekLabelFor(clampSeek(const Duration(seconds: -10))),
              onIncrease: () => widget.props.cubit
                  .seek(clampSeek(const Duration(seconds: 10))),
              onDecrease: () => widget.props.cubit
                  .seek(clampSeek(const Duration(seconds: -10))),
              excludeSemantics: true,
              child: trackWidget,
            ),
            const SizedBox(height: AppSpacing.s2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s6,
                    vertical: AppSpacing.s2,
                  ),
                  decoration: BoxDecoration(
                    color: widget.palette.vfdBackground,
                    borderRadius: AppRadii.r4All,
                    border: Border.all(
                      color: widget.palette.vfdBorder,
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    Formatters.formatDuration(displayDuration),
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: AppFontSize.caption,
                      fontWeight: FontWeight.w800,
                      color: isDragging
                          ? widget.palette.ledGreen
                          : widget.palette.ledAmber,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    PulsrHaptics.selectionClick();
                    setState(() => _showRemaining = !_showRemaining);
                  },
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: AppSpacing.minTouchTarget,
                      minHeight: 28,
                    ),
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s6,
                          vertical: AppSpacing.s2,
                        ),
                        decoration: BoxDecoration(
                          color: widget.palette.vfdBackground,
                          borderRadius: AppRadii.r4All,
                          border: Border.all(
                            color: widget.palette.vfdBorder,
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          _showRemaining
                              ? '-${Formatters.formatDuration(remaining)}'
                              : Formatters.formatDuration(duration),
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: AppFontSize.caption,
                            fontWeight: FontWeight.w700,
                            color: AppColors.onGiltLight.withValues(alpha: 0.78),
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
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

/// Physical Walkman mechanical rectangular keybank: << | ▶ | ❚❚ | >>.
/// Completely replaces the generic circular play button.
class _CassetteMechanicalDeckKeys extends StatelessWidget {
  final PlayerThemeProps props;
  final _CassetteDeckPalette palette;
  final bool isCompact;
  final bool isTablet;
  final bool customGlow;

  const _CassetteMechanicalDeckKeys({
    required this.props,
    required this.palette,
    required this.isCompact,
    required this.isTablet,
    required this.customGlow,
  });

  @override
  Widget build(BuildContext context) {
    final state = props.state;
    final cubit = props.cubit;
    final isPlaying = state.isPlaying;
    final hasPrev = state.hasPreviousNeighbour;
    final hasNext = state.hasNextNeighbour;
    final keyHeight = isTablet ? 62.0 : (isCompact ? 50.0 : 56.0);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: palette.keyTray,
        borderRadius: AppRadii.r12All,
        border: Border.all(color: palette.bayBorder, width: 1.4),
        boxShadow: [
          BoxShadow(
            color: AppColors.scrimAt(palette.isDark ? 0.65 : 0.20),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
          if (customGlow)
            BoxShadow(
              color: props.activeColor.withValues(alpha: 0.28),
              blurRadius: 20,
              spreadRadius: 1,
            ),
        ],
      ),
      child: Row(
        children: [
          // 1. REW / Previous Key (<<)
          Expanded(
            child: _MechanicalDeckKey(
              icon: Icons.fast_rewind_rounded,
              legend: 'REW',
              semanticLabel: context.l10n.previous,
              height: keyHeight,
              palette: palette,
              isDepressed: false,
              enabled: hasPrev,
              ledColor: palette.ledAmber,
              onTap: hasPrev
                  ? () {
                      PulsrHaptics.selection();
                      cubit.previous();
                    }
                  : null,
            ),
          ),
          const SizedBox(width: AppSpacing.s4),

          // 2. PLAY Key (▶) — latches down with glowing green LED strip when playing
          Expanded(
            flex: 2,
            child: _MechanicalDeckKey(
              icon: Icons.play_arrow_rounded,
              legend: 'PLAY',
              semanticLabel: context.l10n.play,
              height: keyHeight,
              palette: palette,
              isDepressed: isPlaying,
              enabled: true,
              ledColor: palette.ledGreen,
              isPrimaryKey: true,
              onTap: () {
                PulsrHaptics.light();
                if (!isPlaying) {
                  cubit.play();
                }
              },
            ),
          ),
          const SizedBox(width: AppSpacing.s4),

          // 3. PAUSE Key (❚❚) — latches down with glowing amber LED strip when paused
          Expanded(
            flex: 2,
            child: _MechanicalDeckKey(
              icon: Icons.pause_rounded,
              legend: 'PAUSE',
              semanticLabel: context.l10n.pause,
              height: keyHeight,
              palette: palette,
              isDepressed: !isPlaying,
              enabled: true,
              ledColor: palette.ledAmber,
              isPrimaryKey: true,
              onTap: () {
                PulsrHaptics.light();
                if (isPlaying) {
                  cubit.pause();
                }
              },
            ),
          ),
          const SizedBox(width: AppSpacing.s4),

          // 4. FF / Next Key (>>)
          Expanded(
            child: _MechanicalDeckKey(
              icon: Icons.fast_forward_rounded,
              legend: 'FF',
              semanticLabel: context.l10n.next,
              height: keyHeight,
              palette: palette,
              isDepressed: false,
              enabled: hasNext,
              ledColor: palette.ledAmber,
              onTap: hasNext
                  ? () {
                      PulsrHaptics.selection();
                      cubit.next();
                    }
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Single physical beveled rectangular mechanical Walkman deck key (>= 48dp target).
class _MechanicalDeckKey extends StatelessWidget {
  final IconData icon;
  final String legend;
  final String semanticLabel;
  final double height;
  final _CassetteDeckPalette palette;
  final bool isDepressed;
  final bool enabled;
  final bool isPrimaryKey;
  final Color ledColor;
  final VoidCallback? onTap;

  const _MechanicalDeckKey({
    required this.icon,
    required this.legend,
    required this.semanticLabel,
    required this.height,
    required this.palette,
    required this.isDepressed,
    required this.enabled,
    required this.ledColor,
    required this.onTap,
    this.isPrimaryKey = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveHeight = math.max(height, AppSpacing.minTouchTarget);
    final iconColor = !enabled
        ? palette.secondaryInk.withValues(alpha: 0.35)
        : (isDepressed ? ledColor : palette.primaryInk);

    return Semantics(
      button: true,
      toggled: isDepressed,
      enabled: enabled,
      label: semanticLabel,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: context.motionMs(200),
        curve: context.motionCurve(PulsrMotion.enter),
        height: effectiveHeight,
        transform: Matrix4.translationValues(0, isDepressed ? 1.5 : 0.0, 0),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDepressed
                ? [palette.keyDepressedTop, palette.keyDepressedBottom]
                : [palette.keyFaceTop, palette.keyFaceBottom],
          ),
          borderRadius: AppRadii.r8All,
          border: Border.all(
            color: isDepressed
                ? ledColor.withValues(alpha: 0.65)
                : palette.keyBorder,
            width: isDepressed ? 1.3 : 1.0,
          ),
          boxShadow: isDepressed
              ? null
              : [
                  BoxShadow(
                    color: AppColors.scrimAt(palette.isDark ? 0.50 : 0.18),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: enabled ? onTap : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: AppSpacing.minTouchTarget,
                minHeight: AppSpacing.minTouchTarget,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xxs,
                  vertical: AppSpacing.s4,
                ),
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.15,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Glowing active key LED strip along top edge
                      Container(
                        width: isPrimaryKey ? 26 : 16,
                        height: 3.0,
                        decoration: BoxDecoration(
                          borderRadius: AppRadii.full,
                          color: isDepressed
                              ? ledColor
                              : palette.secondaryInk.withValues(alpha: 0.18),
                          boxShadow: isDepressed
                              ? [
                                  BoxShadow(
                                    color: ledColor.withValues(alpha: 0.85),
                                    blurRadius: 6,
                                    spreadRadius: 0.5,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Icon(
                            icon,
                            size: isPrimaryKey ? 24 : 20,
                            color: iconColor,
                          ),
                        ),
                      ),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            legend,
                            maxLines: 1,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: AppFontSize.caption,
                              fontWeight: FontWeight.w800,
                              letterSpacing: AppTracking.overline,
                              color: isDepressed
                                  ? ledColor
                                  : palette.secondaryInk.withValues(
                                      alpha: enabled ? 0.82 : 0.35,
                                    ),
                            ),
                          ),
                        ),
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
}

/// Mechanical deck function switches row: Shuffle, Repeat, Lyrics, Queue, Tools.
class _CassetteFunctionSwitches extends StatelessWidget {
  final PlayerThemeProps props;
  final _CassetteDeckPalette palette;
  final bool isInSplitView;

  const _CassetteFunctionSwitches({
    required this.props,
    required this.palette,
    required this.isInSplitView,
  });

  @override
  Widget build(BuildContext context) {
    final state = props.state;
    final cubit = props.cubit;
    final isShuffle = state.isShuffle;
    final repeatMode = state.repeatMode;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s6,
        vertical: AppSpacing.s2,
      ),
      decoration: BoxDecoration(
        color: palette.panelSurface.withValues(alpha: 0.85),
        borderRadius: AppRadii.r12All,
        border: Border.all(color: palette.panelBorder, width: 1.0),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CassetteMicroSwitch(
              icon: Icons.shuffle_rounded,
              tooltip: context.l10n.shuffle,
              isActive: isShuffle,
              palette: palette,
              onTap: () {
                PulsrHaptics.selection();
                cubit.toggleShuffle();
              },
            ),
            const SizedBox(width: AppSpacing.xxs),
            _CassetteMicroSwitch(
              icon: repeatMode == PlayerRepeatMode.one
                  ? Icons.repeat_one_rounded
                  : Icons.repeat_rounded,
              tooltip: context.l10n.repeat,
              isActive: repeatMode != PlayerRepeatMode.off,
              palette: palette,
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
            ),
            if (!isInSplitView) ...[
              const SizedBox(width: AppSpacing.xxs),
              _CassetteMicroSwitch(
                icon: Icons.lyrics_rounded,
                tooltip: context.l10n.lyrics,
                isActive: state.isLyricsVisible,
                palette: palette,
                onTap: () {
                  PulsrHaptics.selectionClick();
                  cubit.toggleLyricsVisibility();
                },
              ),
              const SizedBox(width: AppSpacing.xxs),
              _CassetteMicroSwitch(
                icon: Icons.queue_music_rounded,
                tooltip: context.l10n.queue,
                isActive: state.isQueueVisible,
                palette: palette,
                onTap: () {
                  PulsrHaptics.selectionClick();
                  cubit.toggleQueueVisibility();
                },
              ),
            ],
            const SizedBox(width: AppSpacing.xxs),
            PlayerToolsTriggerButton(
              props: props,
              iconColor: palette.secondaryInk,
              backgroundColor: palette.keyFaceBottom.withValues(alpha: 0.45),
              borderColor: palette.panelBorder,
            ),
          ],
        ),
      ),
    );
  }
}

/// Tactile rectangular mechanical toggle switch (>= 48dp hit target).
class _CassetteMicroSwitch extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isActive;
  final _CassetteDeckPalette palette;
  final VoidCallback onTap;

  const _CassetteMicroSwitch({
    required this.icon,
    required this.tooltip,
    required this.isActive,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeLed = palette.ledGreen;
    return Semantics(
      button: true,
      toggled: isActive,
      label: tooltip,
      excludeSemantics: true,
      child: Material(
        color: isActive
            ? activeLed.withValues(alpha: 0.14)
            : palette.keyFaceBottom.withValues(alpha: 0.35),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.r8All,
          side: BorderSide(
            color: isActive
                ? activeLed.withValues(alpha: 0.55)
                : palette.panelBorder,
            width: 1.0,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: AppSpacing.minTouchTarget,
            height: AppSpacing.minTouchTarget,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isActive ? activeLed : palette.secondaryInk,
                ),
                if (isActive)
                  Positioned(
                    bottom: 6,
                    child: Container(
                      width: 10,
                      height: 2.5,
                      decoration: BoxDecoration(
                        borderRadius: AppRadii.full,
                        color: activeLed,
                        boxShadow: [
                          BoxShadow(
                            color: activeLed.withValues(alpha: 0.8),
                            blurRadius: 4,
                          ),
                        ],
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
