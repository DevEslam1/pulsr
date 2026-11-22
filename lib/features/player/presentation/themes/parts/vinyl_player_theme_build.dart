part of '../vinyl_player_theme.dart';

/// Warm analog hi-fi palette resolved cleanly for both dark walnut/brushed
/// aluminum and light champagne brushed-silver receivers.
class _VinylStudioPalette {
  final bool isDark;
  final Color chassisTop;
  final Color chassisMid;
  final Color chassisBottom;
  final Color grainLight;
  final Color grainDark;
  final Color amberAccent;
  final Color brassHighlight;
  final Color brassDeep;
  final Color primaryInk;
  final Color secondaryInk;
  final Color hardwareSurface;
  final Color hardwareBorder;
  final Color consoleSurface;
  final Color ledActive;
  final Color ledStandby;

  const _VinylStudioPalette({
    required this.isDark,
    required this.chassisTop,
    required this.chassisMid,
    required this.chassisBottom,
    required this.grainLight,
    required this.grainDark,
    required this.amberAccent,
    required this.brassHighlight,
    required this.brassDeep,
    required this.primaryInk,
    required this.secondaryInk,
    required this.hardwareSurface,
    required this.hardwareBorder,
    required this.consoleSurface,
    required this.ledActive,
    required this.ledStandby,
  });

  factory _VinylStudioPalette.resolve(
    BuildContext context,
    Color activeColor,
  ) {
    final p = context.palette;
    final isDark = p.isDark;
    final amber = Color.lerp(AppColors.amberDeep, activeColor, 0.32)!;
    final brassHi = Color.lerp(AppColors.giltGold, AppColors.onGiltLight, 0.34)!;
    final brassLo = Color.lerp(AppColors.giltGold, AppColors.onGiltDark, 0.45)!;

    if (isDark) {
      final walnutTop =
          Color.lerp(PlayerMaterialColors.deckGradStart, AppColors.onGiltDark, 0.42)!;
      final walnutMid =
          Color.lerp(PlayerMaterialColors.plinthSurface, AppColors.onGiltDark, 0.36)!;
      final walnutBottom =
          Color.lerp(PlayerMaterialColors.immersiveBackdrop, AppColors.onGiltDark, 0.25)!;

      return _VinylStudioPalette(
        isDark: true,
        chassisTop: walnutTop,
        chassisMid: walnutMid,
        chassisBottom: walnutBottom,
        grainLight: AppColors.onGiltLight.withValues(alpha: 0.045),
        grainDark: AppColors.scrimAt(0.18),
        amberAccent: amber,
        brassHighlight: brassHi,
        brassDeep: brassLo,
        primaryInk: AppColors.onGiltLight,
        secondaryInk: Color.lerp(AppColors.onGiltLight, AppColors.giltGold, 0.34)!
            .withValues(alpha: 0.78),
        hardwareSurface: Color.lerp(
          PlayerMaterialColors.gimbalMid,
          AppColors.onGiltDark,
          0.35,
        )!,
        hardwareBorder: brassHi.withValues(alpha: 0.26),
        consoleSurface: Color.lerp(
          PlayerMaterialColors.plinthSurface,
          AppColors.onGiltDark,
          0.42,
        )!,
        ledActive: AppColors.amberDeep,
        ledStandby: AppColors.onGiltLight.withValues(alpha: 0.24),
      );
    }

    // Light mode: brushed champagne-aluminum Braun/Marantz studio receiver
    final silverTop = Color.lerp(p.bg, AppColors.onGiltLight, 0.55)!;
    final silverMid = Color.lerp(p.surface, AppColors.onGiltLight, 0.38)!;
    final silverBottom = Color.lerp(p.surfaceContainer, AppColors.giltGold, 0.14)!;
    final warmDarkAmber = Color.lerp(AppColors.onGiltDark, amber, 0.62)!;

    return _VinylStudioPalette(
      isDark: false,
      chassisTop: silverTop,
      chassisMid: silverMid,
      chassisBottom: silverBottom,
      grainLight: AppColors.specularAt(0.45),
      grainDark: AppColors.onGiltDark.withValues(alpha: 0.055),
      amberAccent: warmDarkAmber,
      brassHighlight: brassHi,
      brassDeep: brassLo,
      primaryInk: AppColors.onGiltDark,
      secondaryInk: Color.lerp(AppColors.onGiltDark, p.textSecondary, 0.45)!,
      hardwareSurface: Color.lerp(p.surfaceContainer, AppColors.onGiltLight, 0.50)!,
      hardwareBorder: AppColors.onGiltDark.withValues(alpha: 0.16),
      consoleSurface: Color.lerp(p.surfaceContainer, AppColors.giltGold, 0.10)!,
      ledActive: AppColors.amberDeep,
      ledStandby: AppColors.onGiltDark.withValues(alpha: 0.22),
    );
  }
}

extension _VinylPlayerThemeBuild on _VinylPlayerThemeState {
  Widget _buildBody(BuildContext context) {
    final state = widget.props.state;
    final song = state.currentSong;
    final vinylPalette =
        _VinylStudioPalette.resolve(context, widget.props.activeColor);
    final customGlow = resolveCustomGlow(context);
    final customRadius = resolveCustomRadius(context, AppRadii.r22);

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

    return PlayerSurfaceShell(
      props: widget.props,
      overlayBackgroundColor: vinylPalette.chassisMid.withValues(alpha: 0.96),
      background: RepaintBoundary(
        child: CustomPaint(
          painter: _VinylBrushedChassisPainter(
            topColor: vinylPalette.chassisTop,
            midColor: vinylPalette.chassisMid,
            bottomColor: vinylPalette.chassisBottom,
            grainLight: vinylPalette.grainLight,
            grainDark: vinylPalette.grainDark,
            amberGlow: customGlow
                ? widget.props.activeColor.withValues(
                    alpha: vinylPalette.isDark ? 0.24 : 0.14,
                  )
                : vinylPalette.amberAccent.withValues(
                    alpha: vinylPalette.isDark ? 0.12 : 0.08,
                  ),
          ),
        ),
      ),
      topBarBuilder: (context, metrics) => PlayerCompactTopBar(
        foregroundColor: vinylPalette.primaryInk,
        buttonSurfaceColor: vinylPalette.hardwareSurface.withValues(alpha: 0.72),
        buttonBorderColor: vinylPalette.hardwareBorder,
        center: _VinylStudioTelemetryBadge(
          palette: vinylPalette,
          telemetry: telemetry,
          isPlaying: state.isPlaying,
          onTap: song == null
              ? null
              : () => AudioQualitySheet.show(
                    context,
                    song,
                    widget.props.activeColor,
                  ),
        ),
        trailing: [
          PlayerIconActionButton(
            icon: Icons.more_horiz_rounded,
            tooltip: context.l10n.moreOptions,
            iconColor: vinylPalette.primaryInk,
            surfaceColor: vinylPalette.hardwareSurface.withValues(alpha: 0.72),
            borderColor: vinylPalette.hardwareBorder,
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
            (metrics.constraints.maxWidth * 0.055).clamp(14.0, 28.0);

        Widget buildStage({double? forcedMaxHeight}) {
          return LayoutBuilder(
            builder: (context, stageConstraints) {
              final double visualizerH = showVisualizer
                  ? (visualizerStyle == VisualizerStyle.circular ? 56.0 : 30.0)
                  : 0.0;
              final double visualizerSpace =
                  showVisualizer ? visualizerH + AppSpacing.xs : 0.0;
              final double capH = forcedMaxHeight ?? stageConstraints.maxHeight;
              final double availableH =
                  math.max(0.0, capH - visualizerSpace);

              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    key: const ValueKey('turntable_view'),
                    child: SizedBox(
                      height: availableH,
                      child: Hero(
                        tag: widget.props.heroTag,
                        child: _VinylTurntableDeck(
                          props: widget.props,
                          isTablet: metrics.isTablet,
                          isLandscape: metrics.isLandscape,
                          rotationController: _rotationController,
                          tonearmAnimation: _tonearmAnimation,
                          plinthRadius: customRadius,
                          ambientGlow: customGlow,
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
                          color: vinylPalette.amberAccent,
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

        final trackHeader = _VinylTrackReadout(
          props: widget.props,
          palette: vinylPalette,
          isCompact: isShort,
          isTablet: metrics.isTablet,
          alignStart: isInSplitView,
          isPreview: isPreview,
        );

        final seekBar = _VinylAnalogSeekBar(
          props: widget.props,
          palette: vinylPalette,
          sliderStyle: sliderStyle,
          isCompact: isShort,
        );

        final transport = _VinylRotaryTransport(
          props: widget.props,
          palette: vinylPalette,
          isCompact: isShort,
          isTablet: metrics.isTablet,
          customGlow: customGlow,
        );

        final footer = _VinylAnalogFooter(
          props: widget.props,
          palette: vinylPalette,
          isInSplitView: isInSplitView,
          outputDevice: settingsState.currentOutputDevice,
        );

        final Widget lowerConsole = Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPad),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              trackHeader,
              SizedBox(height: isVeryShort ? AppSpacing.xxs : AppSpacing.xs),
              seekBar,
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
                  height: isVeryShort
                      ? AppSpacing.xs
                      : (isShort ? AppSpacing.sm : AppSpacing.md),
                ),
              ],
              transport,
              if (!isPreview &&
                  (isInSplitView || metrics.isTablet) &&
                  !isVeryShort) ...[
                const SizedBox(height: AppSpacing.xs),
                PlayerVolumeBar(
                  cubit: widget.props.cubit,
                  activeColor: vinylPalette.amberAccent,
                ),
              ],
              if (!isPreview) ...[
                SizedBox(
                  height: isVeryShort ? AppSpacing.xxs : AppSpacing.sm,
                ),
                footer,
              ],
              SizedBox(height: isVeryShort ? AppSpacing.xxs : AppSpacing.xs),
            ],
          ),
        );

        if (isPreview) {
          return Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Column(
              children: [
                Expanded(child: buildStage()),
                lowerConsole,
              ],
            ),
          );
        }

        if (isInSplitView) {
          return Column(
            children: [
              const SizedBox(height: AppSpacing.xs),
              Expanded(child: buildStage()),
              lowerConsole,
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
                start: AppSpacing.md,
                end: AppSpacing.md,
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Center(child: buildStage()),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    flex: 5,
                    child: Center(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: lowerConsole,
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
        final double scrollThreshold = 600.0 + (textScale - 1.0) * 140.0;
        if (metrics.constraints.maxHeight < scrollThreshold) {
          final double stageCap =
              (metrics.constraints.maxHeight * 0.42).clamp(180.0, 310.0);
          return SafeArea(
            top: false,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: EdgeInsets.only(top: topClearance),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    buildStage(forcedMaxHeight: stageCap),
                    const SizedBox(height: AppSpacing.xs),
                    lowerConsole,
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
                Expanded(child: buildStage()),
                const SizedBox(height: AppSpacing.xs),
                lowerConsole,
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Centered warm hi-fi telemetry nameplate in the compact top bar.
class _VinylStudioTelemetryBadge extends StatelessWidget {
  final _VinylStudioPalette palette;
  final PlayerAudioTelemetry telemetry;
  final bool isPlaying;
  final VoidCallback? onTap;

  const _VinylStudioTelemetryBadge({
    required this.palette,
    required this.telemetry,
    required this.isPlaying,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = telemetry.compactBadge.isNotEmpty
        ? telemetry.compactBadge
        : context.l10n.vinylDirectDrive;

    final badge = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.s6,
      ),
      decoration: BoxDecoration(
        color: palette.hardwareSurface.withValues(alpha: 0.78),
        borderRadius: AppRadii.full,
        border: Border.all(
          color: isPlaying
              ? palette.amberAccent.withValues(alpha: 0.48)
              : palette.hardwareBorder,
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
              color: isPlaying ? palette.ledActive : palette.ledStandby,
              boxShadow: isPlaying
                  ? [
                      BoxShadow(
                        color: palette.ledActive.withValues(alpha: 0.75),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
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
                fontWeight: FontWeight.w700,
                letterSpacing: AppTracking.overline,
                color: palette.primaryInk,
              ),
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return badge;

    return Semantics(
      button: true,
      label: context.l10n.audioQuality,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: AppRadii.full,
        onTap: () {
          PulsrHaptics.selectionClick();
          onTap!();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppSpacing.minTouchTarget,
            minWidth: AppSpacing.minTouchTarget,
          ),
          child: Center(child: badge),
        ),
      ),
    );
  }
}

/// Warm serif/editorial track readout flanked by tactile metallic action buttons.
class _VinylTrackReadout extends StatelessWidget {
  final PlayerThemeProps props;
  final _VinylStudioPalette palette;
  final bool isCompact;
  final bool isTablet;
  final bool alignStart;
  final bool isPreview;

  const _VinylTrackReadout({
    required this.props,
    required this.palette,
    required this.isCompact,
    required this.isTablet,
    required this.alignStart,
    required this.isPreview,
  });

  @override
  Widget build(BuildContext context) {
    final song = props.state.currentSong;
    final isFav = song?.isFavorite == true;
    final hasDownload = song != null &&
        (song.source == SongSource.youtube ||
            (song.remoteId != null && song.remoteId!.isNotEmpty));

    final titleSize = isTablet
        ? AppFontSize.headline
        : (isCompact ? AppFontSize.subtitle : AppFontSize.titleLarge);
    final artistSize = isTablet
        ? AppFontSize.callout
        : (isCompact ? AppFontSize.label : AppFontSize.bodySmall);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (!alignStart && !isPreview)
          SizedBox(
            width: AppSpacing.minTouchTarget,
            height: AppSpacing.minTouchTarget,
            child: Material(
              color: palette.hardwareSurface.withValues(alpha: 0.72),
              shape: CircleBorder(
                side: BorderSide(color: palette.hardwareBorder, width: 1.0),
              ),
              clipBehavior: Clip.antiAlias,
              child: hasDownload
                  ? Center(
                      child: YtmDownloadButton(
                        song: song,
                        activeColor: palette.amberAccent,
                        iconColor: palette.secondaryInk,
                        iconSize: 20,
                      ),
                    )
                  : Semantics(
                      button: true,
                      label: context.l10n.addToPlaylist,
                      excludeSemantics: true,
                      child: InkWell(
                        onTap: song == null
                            ? null
                            : () {
                                PulsrHaptics.lightImpact();
                                AddToPlaylistSheet.show(context, song: song);
                              },
                        child: Center(
                          child: Icon(
                            Icons.playlist_add_rounded,
                            size: 20,
                            color: palette.secondaryInk,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        Expanded(
          child: Padding(
            padding: EdgeInsetsDirectional.only(
              start: alignStart || isPreview ? 0 : AppSpacing.s10,
              end: isPreview ? 0 : AppSpacing.s10,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: alignStart
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: MarqueeText(
                    text: song?.title ?? context.l10n.noTrackSelected,
                    textAlign: alignStart ? TextAlign.start : TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'serif',
                      fontSize: titleSize,
                      fontWeight: FontWeight.w700,
                      letterSpacing: AppTracking.title,
                      height: 1.18,
                      color: palette.primaryInk,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                SizedBox(
                  width: double.infinity,
                  child: MarqueeText(
                    text: song?.artist ?? context.l10n.unknownArtist,
                    textAlign: alignStart ? TextAlign.start : TextAlign.center,
                    style: TextStyle(
                      fontSize: artistSize,
                      fontWeight: FontWeight.w600,
                      letterSpacing: AppTracking.label,
                      color: palette.secondaryInk,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!isPreview)
          Container(
            width: AppSpacing.minTouchTarget,
            height: AppSpacing.minTouchTarget,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isFav
                  ? palette.amberAccent.withValues(alpha: 0.18)
                  : palette.hardwareSurface.withValues(alpha: 0.72),
              border: Border.all(
                color: isFav
                    ? palette.amberAccent.withValues(alpha: 0.55)
                    : palette.hardwareBorder,
                width: 1.0,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Material(
              type: MaterialType.transparency,
              child: PlayerAnimatedFavoriteButton(
                isFavorite: isFav,
                semanticLabel: isFav ? context.l10n.unlike : context.l10n.like,
                favoriteColor: palette.amberAccent,
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
    );
  }
}

/// Warm amber/brass precision analog seek bar driven by BlocSelector.
class _VinylAnalogSeekBar extends StatefulWidget {
  final PlayerThemeProps props;
  final _VinylStudioPalette palette;
  final PlayerSliderStyle sliderStyle;
  final bool isCompact;

  const _VinylAnalogSeekBar({
    required this.props,
    required this.palette,
    required this.sliderStyle,
    required this.isCompact,
  });

  @override
  State<_VinylAnalogSeekBar> createState() => _VinylAnalogSeekBarState();
}

class _VinylAnalogSeekBarState extends State<_VinylAnalogSeekBar> {
  double? _dragValue;
  bool _showRemaining = false;
  Future<List<double>>? _waveformFuture;
  int? _lastSongId;
  String? _lastFilePath;

  @override
  void didUpdateWidget(covariant _VinylAnalogSeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.props.state.currentSong?.id !=
        oldWidget.props.state.currentSong?.id) {
      _dragValue = null;
      _waveformFuture = null;
    }
  }

  Widget _buildSlider({
    required double value,
    required double maxDuration,
    required bool isPlaying,
    required bool isBuffering,
  }) {
    final pal = widget.palette;
    return SizedBox(
      height: widget.isCompact ? 24.0 : 30.0,
      child: PulsrSlider(
        value: value,
        min: 0.0,
        max: maxDuration > 0 ? maxDuration : 1.0,
        height: widget.isCompact ? 24.0 : 30.0,
        activeColor: pal.amberAccent,
        inactiveColor: pal.primaryInk.withValues(alpha: 0.16),
        thumbColor: pal.brassHighlight,
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
            key: ValueKey('vinyl_wf_${song.id}'),
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
                  activeColor: widget.palette.amberAccent,
                  height: widget.isCompact ? 26.0 : 34.0,
                );
              }
              return _buildSlider(
                value: effectiveValue,
                maxDuration: maxDuration,
                isPlaying: isPlaying,
                isBuffering: isBuffering,
              );
            },
          );
        } else {
          trackWidget = _buildSlider(
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
                Text(
                  Formatters.formatDuration(displayDuration),
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: AppFontSize.caption,
                    fontWeight: FontWeight.w700,
                    color: isDragging
                        ? widget.palette.amberAccent
                        : widget.palette.secondaryInk,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                ExcludeSemantics(
                  child: SizedBox(
                    width: 64,
                    height: 8,
                    child: CustomPaint(
                      painter: _AnalogCalibrationTicksPainter(
                        tickColor:
                            widget.palette.secondaryInk.withValues(alpha: 0.35),
                        accentColor: widget.palette.amberAccent,
                        progress: maxDuration > 0
                            ? (effectiveValue / maxDuration).clamp(0.0, 1.0)
                            : 0.0,
                      ),
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
                      child: Text(
                        _showRemaining
                            ? '-${Formatters.formatDuration(remaining)}'
                            : Formatters.formatDuration(duration),
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: AppFontSize.caption,
                          fontWeight: FontWeight.w700,
                          color: widget.palette.secondaryInk,
                          fontFeatures: const [FontFeature.tabularFigures()],
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

/// Tactile metallic/amber rotary-inspired analog hardware transport console.
class _VinylRotaryTransport extends StatelessWidget {
  final PlayerThemeProps props;
  final _VinylStudioPalette palette;
  final bool isCompact;
  final bool isTablet;
  final bool customGlow;

  const _VinylRotaryTransport({
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
    final isShuffle = state.isShuffle;
    final repeatMode = state.repeatMode;
    final hasPrev = state.hasPreviousNeighbour;
    final hasNext = state.hasNextNeighbour;

    final double dialSize = isTablet ? 74.0 : (isCompact ? 56.0 : 68.0);
    final double gap = isCompact ? AppSpacing.s10 : AppSpacing.sm;

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 1. Shuffle switch
          _VinylHardwareSwitch(
            icon: Icons.shuffle_rounded,
            tooltip: context.l10n.shuffle,
            isActive: isShuffle,
            palette: palette,
            iconSize: 20,
            onTap: () {
              PulsrHaptics.selection();
              cubit.toggleShuffle();
            },
          ),
          SizedBox(width: gap),

          // 2. Previous track switch
          _VinylHardwareSwitch(
            icon: Icons.skip_previous_rounded,
            tooltip: context.l10n.previous,
            isActive: false,
            enabled: hasPrev,
            palette: palette,
            iconSize: 26,
            isPrimaryTransport: true,
            onTap: hasPrev
                ? () {
                    PulsrHaptics.selection();
                    cubit.previous();
                  }
                : null,
          ),
          SizedBox(width: gap + AppSpacing.xxs),

          // 3. Centerpiece Warm Amber / Metallic Rotary Play-Pause Dial
          _VinylRotaryPlayDial(
            size: dialSize,
            isPlaying: isPlaying,
            isBuffering: state.isBuffering,
            palette: palette,
            customGlow: customGlow,
            accentGlowColor: props.activeColor,
            onTap: () {
              PulsrHaptics.light();
              cubit.togglePlayPause();
            },
          ),
          SizedBox(width: gap + AppSpacing.xxs),

          // 4. Next track switch
          _VinylHardwareSwitch(
            icon: Icons.skip_next_rounded,
            tooltip: context.l10n.next,
            isActive: false,
            enabled: hasNext,
            palette: palette,
            iconSize: 26,
            isPrimaryTransport: true,
            onTap: hasNext
                ? () {
                    PulsrHaptics.selection();
                    cubit.next();
                  }
                : null,
          ),
          SizedBox(width: gap),

          // 5. Repeat switch
          _VinylHardwareSwitch(
            icon: repeatMode == PlayerRepeatMode.one
                ? Icons.repeat_one_rounded
                : Icons.repeat_rounded,
            tooltip: context.l10n.repeat,
            isActive: repeatMode != PlayerRepeatMode.off,
            palette: palette,
            iconSize: 20,
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
        ],
      ),
    );
  }
}

/// Tactile beveled metallic rotary-inspired Play/Pause dial (>= 48dp target).
class _VinylRotaryPlayDial extends StatelessWidget {
  final double size;
  final bool isPlaying;
  final bool isBuffering;
  final _VinylStudioPalette palette;
  final bool customGlow;
  final Color accentGlowColor;
  final VoidCallback onTap;

  const _VinylRotaryPlayDial({
    required this.size,
    required this.isPlaying,
    required this.isBuffering,
    required this.palette,
    required this.customGlow,
    required this.accentGlowColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final surface = context.playerSurfacePalette;
    final dialDiameter = math.max(size, AppSpacing.minTouchTarget);
    final innerColor = isPlaying
        ? palette.amberAccent
        : (palette.isDark
            ? PlayerMaterialColors.gimbalMid
            : palette.hardwareSurface);
    final iconColor = isPlaying
        ? AppColors.textOnAccent(palette.amberAccent)
        : palette.primaryInk;

    return Semantics(
      button: true,
      label: isPlaying ? context.l10n.pause : context.l10n.play,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: context.motionMs(260),
        curve: context.motionCurve(PulsrMotion.enter),
        width: dialDiameter,
        height: dialDiameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(
            colors: [
              palette.brassDeep,
              palette.brassHighlight,
              surface.platterMetalDeep,
              palette.brassHighlight,
              palette.brassDeep,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.scrimAt(palette.isDark ? 0.58 : 0.22),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
            if (isPlaying || customGlow)
              BoxShadow(
                color: (customGlow ? accentGlowColor : palette.amberAccent)
                    .withValues(alpha: customGlow ? 0.48 : 0.36),
                blurRadius: customGlow ? 26 : 18,
                spreadRadius: customGlow ? 2 : 0,
              ),
          ],
        ),
        padding: const EdgeInsets.all(3.2),
        child: Material(
          color: innerColor,
          shape: CircleBorder(
            side: BorderSide(
              color: isPlaying
                  ? palette.brassHighlight.withValues(alpha: 0.72)
                  : palette.hardwareBorder,
              width: 1.2,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: CustomPaint(
              painter: _RotaryDialKnurlPainter(
                notchColor: isPlaying
                    ? AppColors.textOnAccent(palette.amberAccent)
                        .withValues(alpha: 0.22)
                    : palette.brassHighlight.withValues(alpha: 0.30),
                indicatorColor:
                    isPlaying ? AppColors.onGiltLight : palette.amberAccent,
              ),
              child: Center(
                child: AnimatedOpacity(
                  duration: context.motionMs(200),
                  opacity: isBuffering ? 0.55 : 1.0,
                  child: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: dialDiameter * 0.48,
                    color: iconColor,
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

/// Beveled metallic hardware switch (>= 48dp hit target) with amber status LED.
class _VinylHardwareSwitch extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isActive;
  final bool enabled;
  final bool isPrimaryTransport;
  final _VinylStudioPalette palette;
  final double iconSize;
  final VoidCallback? onTap;

  const _VinylHardwareSwitch({
    required this.icon,
    required this.tooltip,
    required this.isActive,
    required this.palette,
    required this.iconSize,
    required this.onTap,
    this.enabled = true,
    this.isPrimaryTransport = false,
  });

  @override
  Widget build(BuildContext context) {
    final fgColor = !enabled
        ? palette.secondaryInk.withValues(alpha: 0.35)
        : (isActive
            ? palette.amberAccent
            : (isPrimaryTransport ? palette.primaryInk : palette.secondaryInk));

    return Semantics(
      button: true,
      toggled: isActive,
      enabled: enabled,
      label: tooltip,
      excludeSemantics: true,
      child: Material(
        color: isPrimaryTransport
            ? palette.hardwareSurface
            : palette.hardwareSurface.withValues(alpha: 0.55),
        shape: CircleBorder(
          side: BorderSide(
            color: isActive
                ? palette.amberAccent.withValues(alpha: 0.58)
                : palette.hardwareBorder,
            width: isPrimaryTransport ? 1.2 : 1.0,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: AppSpacing.minTouchTarget,
            height: AppSpacing.minTouchTarget,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(icon, size: iconSize, color: fgColor),
                if (isActive)
                  Positioned(
                    bottom: 6,
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: palette.ledActive,
                        boxShadow: [
                          BoxShadow(
                            color: palette.ledActive.withValues(alpha: 0.75),
                            blurRadius: 5,
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

/// Compact analog footer row: Lyrics, Output/DAC, Queue, and PlayerToolsTriggerButton.
class _VinylAnalogFooter extends StatelessWidget {
  final PlayerThemeProps props;
  final _VinylStudioPalette palette;
  final bool isInSplitView;
  final AudioOutputInfo? outputDevice;

  const _VinylAnalogFooter({
    required this.props,
    required this.palette,
    required this.isInSplitView,
    required this.outputDevice,
  });

  @override
  Widget build(BuildContext context) {
    final state = props.state;
    final cubit = props.cubit;
    final song = state.currentSong;

    final IconData outputIcon = outputDevice == null
        ? Icons.headphones_rounded
        : (outputDevice!.isUsb
            ? Icons.usb_rounded
            : (outputDevice!.isBt
                ? Icons.bluetooth_audio_rounded
                : (outputDevice!.isSpeaker
                    ? Icons.speaker_rounded
                    : Icons.headphones_rounded)));

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.s2,
      ),
      decoration: BoxDecoration(
        color: palette.consoleSurface.withValues(alpha: 0.78),
        borderRadius: AppRadii.full,
        border: Border.all(color: palette.hardwareBorder, width: 1.0),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!isInSplitView) ...[
              PlayerIconActionButton(
                icon: Icons.lyrics_rounded,
                tooltip: context.l10n.lyrics,
                isActive: state.isLyricsVisible,
                iconColor: palette.secondaryInk,
                activeColor: palette.amberAccent,
                showActiveDot: true,
                onTap: () => cubit.toggleLyricsVisibility(),
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
            ValueListenableBuilder<CastSessionStatus>(
              valueListenable: CastService().sessionStatusListenable,
              builder: (context, castStatus, _) {
                final isCast = castStatus.connected;
                final isUsbDac = outputDevice?.isUsbDac == true;
                return PlayerIconActionButton(
                  icon: isCast ? Icons.cast_connected_rounded : outputIcon,
                  tooltip: context.l10n.audioOutputAndDac,
                  isActive: isCast || isUsbDac,
                  iconColor: palette.secondaryInk,
                  activeColor:
                      isCast ? AppColors.accentCyan : palette.amberAccent,
                  showActiveDot: true,
                  onTap: song == null
                      ? null
                      : () => AudioQualitySheet.show(
                            context,
                            song,
                            props.activeColor,
                          ),
                );
              },
            ),
            if (!isInSplitView) ...[
              const SizedBox(width: AppSpacing.xs),
              PlayerIconActionButton(
                icon: Icons.queue_music_rounded,
                tooltip: context.l10n.queue,
                isActive: state.isQueueVisible,
                iconColor: palette.secondaryInk,
                activeColor: palette.amberAccent,
                showActiveDot: true,
                onTap: () => cubit.toggleQueueVisibility(),
              ),
            ],
            const SizedBox(width: AppSpacing.xs),
            PlayerToolsTriggerButton(
              props: props,
              iconColor: palette.secondaryInk,
              backgroundColor: palette.hardwareSurface.withValues(alpha: 0.55),
              borderColor: palette.hardwareBorder,
            ),
          ],
        ),
      ),
    );
  }
}
