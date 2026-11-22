part of '../waveform_player_theme.dart';

extension _WaveformPlayerThemeBuild on _WaveformPlayerThemeState {
  Widget _buildBody(BuildContext context) {
    final p = context.palette;
    final state = widget.props.state;
    final activeColor = widget.props.activeColor;
    final bgColor = widget.props.bgColor;
    final customGlow = resolveCustomGlow(context);

    final Color consoleTop = p.isDark
        ? Color.lerp(p.bg, bgColor, 0.36) ?? p.bg
        : Color.lerp(p.bg, p.surfaceContainer, 0.30) ?? p.bg;
    final Color consoleMid = Color.lerp(
          consoleTop,
          activeColor,
          p.isDark ? (customGlow ? 0.14 : 0.08) : (customGlow ? 0.08 : 0.04),
        ) ??
        consoleTop;

    return PlayerSurfaceShell(
      props: widget.props,
      background: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.08),
            radius: 1.25,
            colors: [
              consoleMid,
              consoleTop,
              p.bg,
            ],
            stops: const [0.0, 0.52, 1.0],
          ),
        ),
      ),
      topBarBuilder: (context, metrics) => _StudioTopBar(props: widget.props),
      builder: (context, metrics, isInSplitView, isPreview) {
        final textScale =
            MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 2.0);
        final horizontalPad = metrics.isTablet ? AppSpacing.xl : AppSpacing.lg;
        final double topBarReserve = (!isInSplitView && !isPreview)
            ? AppSpacing.minTouchTarget + AppSpacing.xs
            : AppSpacing.xs;

        // 1. Short Landscape Layout (e.g. 844x390)
        if (metrics.isLandscape && !isInSplitView && !isPreview) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                AppSpacing.md,
                topBarReserve,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Left 60%: Tall Interactive Oscilloscope Bay
                  Expanded(
                    flex: 6,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.xs,
                      ),
                      child: _StudioOscilloscopeBay(
                        key: const ValueKey('waveform_hero_stage'),
                        props: widget.props,
                        isCompact: true,
                        isPreview: false,
                        customGlow: customGlow,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  // Right 40%: Compact Artwork + Metadata + Telemetry + Transport
                  Expanded(
                    flex: 5,
                    child: Center(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.xs,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _StudioTrackBayHeader(
                              props: widget.props,
                              thumbSize: 48.0,
                              isCompact: true,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            _StudioTelemetryStrip(
                              props: widget.props,
                              isCompact: true,
                              isPreview: false,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            _StudioTransportRow(
                              props: widget.props,
                              isCompact: true,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            _StudioBottomBar(
                              props: widget.props,
                              isInSplitView: false,
                            ),
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

        // 2. Theme Picker / Theme Studio Mini-Preview
        if (isPreview) {
          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StudioTrackBayHeader(
                  props: widget.props,
                  thumbSize: 48.0,
                  isCompact: true,
                ),
                const SizedBox(height: AppSpacing.xs),
                _StudioTelemetryStrip(
                  props: widget.props,
                  isCompact: true,
                  isPreview: true,
                ),
                const SizedBox(height: AppSpacing.sm),
                Expanded(
                  child: _StudioOscilloscopeBay(
                    key: const ValueKey('waveform_hero_stage'),
                    props: widget.props,
                    isCompact: true,
                    isPreview: true,
                    customGlow: customGlow,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                _StudioTransportRow(
                  props: widget.props,
                  isCompact: true,
                ),
              ],
            ),
          );
        }

        // 3. Portrait / Tablet / Split-View Layout
        final double scrollThreshold =
            (isInSplitView ? 520.0 : 620.0) + (textScale - 1.0) * 140.0;
        final bool needsScroll =
            metrics.constraints.maxHeight < scrollThreshold;
        final bool isCompact = metrics.isShortHeight ||
            metrics.isVeryShortHeight ||
            textScale > 1.35;
        final double thumbSize =
            metrics.isTablet ? 70.0 : (isCompact ? 54.0 : 62.0);
        final double gapSm = isCompact ? AppSpacing.xs : AppSpacing.sm;
        final double gapMd = isCompact ? AppSpacing.sm : AppSpacing.md;

        if (needsScroll) {
          final double boundedScopeH =
              (metrics.constraints.maxHeight * 0.38).clamp(150.0, 260.0);
          return SafeArea(
            top: !isInSplitView,
            bottom: !isInSplitView,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsetsDirectional.fromSTEB(
                horizontalPad,
                topBarReserve,
                horizontalPad,
                AppSpacing.md,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _StudioTrackBayHeader(
                    props: widget.props,
                    thumbSize: thumbSize,
                    isCompact: true,
                  ),
                  SizedBox(height: gapSm),
                  _StudioTelemetryStrip(
                    props: widget.props,
                    isCompact: true,
                    isPreview: false,
                  ),
                  SizedBox(height: gapMd),
                  SizedBox(
                    height: boundedScopeH,
                    child: _StudioOscilloscopeBay(
                      key: const ValueKey('waveform_hero_stage'),
                      props: widget.props,
                      isCompact: true,
                      isPreview: false,
                      customGlow: customGlow,
                    ),
                  ),
                  if (state.bookmarkPosition != null) ...[
                    SizedBox(height: gapSm),
                    PlayerBookmarkPromptBanner(
                      cubit: widget.props.cubit,
                      position: state.bookmarkPosition!,
                    ),
                  ],
                  SizedBox(height: gapMd),
                  _StudioTransportRow(
                    props: widget.props,
                    isCompact: true,
                  ),
                  if (isInSplitView && !metrics.isVeryShortHeight) ...[
                    SizedBox(height: gapSm),
                    PlayerVolumeBar(
                      cubit: widget.props.cubit,
                      activeColor: activeColor,
                    ),
                  ],
                  SizedBox(height: gapMd),
                  _StudioBottomBar(
                    props: widget.props,
                    isInSplitView: isInSplitView,
                  ),
                ],
              ),
            ),
          );
        }

        // Standard spacious Portrait / Tablet / Split-View:
        // Oscilloscope bay expands naturally to dominate ~40% of the viewport.
        return SafeArea(
          top: !isInSplitView,
          bottom: !isInSplitView,
          child: Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              horizontalPad,
              topBarReserve,
              horizontalPad,
              AppSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Compact corner artwork thumbnail + left-aligned metadata
                _StudioTrackBayHeader(
                  props: widget.props,
                  thumbSize: thumbSize,
                  isCompact: isCompact,
                ),
                SizedBox(height: gapSm),

                // 2. Bold monospace audio telemetry strip (tappable -> Quality)
                _StudioTelemetryStrip(
                  props: widget.props,
                  isCompact: isCompact,
                  isPreview: false,
                ),
                SizedBox(height: gapMd),

                // 3. Tall interactive seekable oscilloscope centerpiece (~40%+)
                Expanded(
                  child: _StudioOscilloscopeBay(
                    key: const ValueKey('waveform_hero_stage'),
                    props: widget.props,
                    isCompact: isCompact,
                    isPreview: false,
                    customGlow: customGlow,
                  ),
                ),

                if (state.bookmarkPosition != null) ...[
                  SizedBox(height: gapSm),
                  PlayerBookmarkPromptBanner(
                    cubit: widget.props.cubit,
                    position: state.bookmarkPosition!,
                  ),
                ],

                SizedBox(height: gapMd),

                // 4. Precision minimal studio transport controls
                _StudioTransportRow(
                  props: widget.props,
                  isCompact: isCompact,
                ),

                if (isInSplitView && !metrics.isVeryShortHeight) ...[
                  SizedBox(height: gapSm),
                  PlayerVolumeBar(
                    cubit: widget.props.cubit,
                    activeColor: activeColor,
                  ),
                ],

                SizedBox(height: gapMd),

                // 5. Compact studio bottom strip (Lyrics, EQ, Queue, Tools)
                _StudioBottomBar(
                  props: widget.props,
                  isInSplitView: isInSplitView,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Minimal studio console top bar with monospace channel indicator & song menu.
class _StudioTopBar extends StatelessWidget {
  final PlayerThemeProps props;

  const _StudioTopBar({required this.props});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final song = props.state.currentSong;
    return PlayerCompactTopBar(
      foregroundColor: p.textPrimary,
      buttonSurfaceColor: p.surfaceContainer.withValues(alpha: 0.72),
      buttonBorderColor: p.hairline,
      center: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: p.surfaceContainer.withValues(alpha: 0.78),
          borderRadius: AppRadii.r8All,
          border: Border.all(
            color: props.activeColor.withValues(alpha: 0.30),
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.graphic_eq_rounded,
              size: 13,
              color: props.activeColor,
            ),
            const SizedBox(width: AppSpacing.s6),
            Flexible(
              child: Text(
                context.l10n.waveformLabel.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: AppFontSize.caption,
                  fontWeight: FontWeight.w800,
                  letterSpacing: AppTracking.wide,
                  color: props.activeColor,
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
          iconColor: p.textPrimary,
          surfaceColor: p.surfaceContainer.withValues(alpha: 0.72),
          borderColor: p.hairline,
          onTap: song == null
              ? null
              : () => SongOptionsSheet.show(context, song: song),
        ),
      ],
    );
  }
}

/// Compact corner artwork thumbnail paired with bold left-aligned track title,
/// artist subtitle, and animated favorite heart.
class _StudioTrackBayHeader extends StatelessWidget {
  final PlayerThemeProps props;
  final double thumbSize;
  final bool isCompact;

  const _StudioTrackBayHeader({
    required this.props,
    required this.thumbSize,
    required this.isCompact,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final song = props.state.currentSong;
    final isFav = song?.isFavorite == true;
    final thumbRadius = resolveCustomRadius(context, AppRadii.r12).clamp(
      AppRadii.r4,
      AppRadii.r24,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Compact rounded corner cover thumbnail (NOT a giant square cover).
        Hero(
          tag: props.heroTag,
          child: Container(
            width: thumbSize,
            height: thumbSize,
            decoration: BoxDecoration(
              borderRadius: AppRadii.circular(thumbRadius),
              border: Border.all(
                color: p.isDark
                    ? AppColors.specularAt(0.18)
                    : p.hairline.withValues(alpha: 0.90),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.scrimAt(p.isDark ? 0.36 : 0.14),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: PlayerArtworkSemantics(
              song: song,
              child: song != null
                  ? CachedArtwork(
                      id: song.id,
                      albumId: song.albumId,
                      remoteUrl: song.remoteArtworkUrl ?? song.artworkUri,
                      type: ArtworkType.AUDIO,
                      size: thumbSize,
                      borderRadius: thumbRadius,
                      highQuality: true,
                      fallbackIcon: Icons.graphic_eq_rounded,
                    )
                  : ExcludeSemantics(
                      child: ColoredBox(
                        color: p.surfaceContainerHigh,
                        child: Center(
                          child: Icon(
                            Icons.graphic_eq_rounded,
                            size: thumbSize * 0.44,
                            color: p.textSecondary,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),

        // Bold left-aligned track title & artist metadata.
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
                      isCompact ? AppFontSize.bodyLarge : AppFontSize.titleLarge,
                  fontWeight: FontWeight.w800,
                  color: p.textPrimary,
                  letterSpacing: AppTracking.heading,
                  height: 1.18,
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
                  color: p.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.xs),

        // Favorite heart (>= 48dp hit target).
        Container(
          decoration: BoxDecoration(
            color: isFav
                ? p.favorite.withValues(alpha: p.isDark ? 0.16 : 0.12)
                : p.surfaceContainer.withValues(alpha: 0.72),
            borderRadius: AppRadii.r12All,
            border: Border.all(
              color: isFav
                  ? p.favorite.withValues(alpha: 0.45)
                  : p.hairline.withValues(alpha: 0.85),
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
              inactiveColor: p.textSecondary,
              iconSize: 22,
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

/// Bold monospace studio audio telemetry readout strip powered by
/// [formatPlayerAudioTelemetry]. Tapping opens [AudioQualitySheet].
class _StudioTelemetryStrip extends StatelessWidget {
  final PlayerThemeProps props;
  final bool isCompact;
  final bool isPreview;

  const _StudioTelemetryStrip({
    required this.props,
    required this.isCompact,
    required this.isPreview,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final song = props.state.currentSong;
    final settings =
        context.select<SettingsCubit, SettingsState>((c) => c.state);
    final telemetry = formatPlayerAudioTelemetry(song, settings);

    final String primaryReadout;
    if (telemetry.fullLine.isNotEmpty) {
      primaryReadout = telemetry.fullLine;
    } else if (telemetry.compactBadge.isNotEmpty) {
      primaryReadout = telemetry.compactBadge;
    } else if (song != null) {
      final info = AudioQualityInfo.fromSong(
        song,
        streamingQuality: settings.streamingQuality,
      );
      primaryReadout = info.shortBadgeLabel.toUpperCase();
    } else {
      primaryReadout = context.l10n.audioQuality.toUpperCase();
    }

    final Color tierTint = telemetry.isUsbDac || telemetry.isHiRes
        ? p.goldAccent
        : (telemetry.isBitPerfect
            ? AppColors.studioGreen
            : props.activeColor);

    final stripRadius = resolveCustomRadius(context, AppRadii.r10).clamp(
      AppRadii.r4,
      AppRadii.r16,
    );

    final Widget stripBody = Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: isCompact ? AppSpacing.s6 : AppSpacing.s8,
      ),
      decoration: BoxDecoration(
        color: p.isDark
            ? Color.alphaBlend(
                tierTint.withValues(alpha: 0.08),
                p.surfaceContainer.withValues(alpha: 0.90),
              )
            : Color.alphaBlend(
                tierTint.withValues(alpha: 0.06),
                p.surfaceContainer,
              ),
        borderRadius: AppRadii.circular(stripRadius),
        border: Border.all(
          color: tierTint.withValues(alpha: p.isDark ? 0.36 : 0.42),
          width: 1.0,
        ),
      ),
      child: Row(
        children: [
          ExcludeSemantics(
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tierTint,
                boxShadow: [
                  BoxShadow(
                    color: tierTint.withValues(alpha: 0.55),
                    blurRadius: 6,
                    spreadRadius: 0.5,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          Expanded(
            child: Text(
              primaryReadout,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize:
                    isCompact ? AppFontSize.caption : AppFontSize.label,
                fontWeight: FontWeight.w800,
                letterSpacing: AppTracking.overline,
                color: p.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (telemetry.isHiRes || telemetry.isLossless) ...[
            const SizedBox(width: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s6,
                vertical: AppSpacing.s2,
              ),
              decoration: BoxDecoration(
                color: tierTint.withValues(alpha: p.isDark ? 0.18 : 0.14),
                borderRadius: AppRadii.r4All,
                border: Border.all(
                  color: tierTint.withValues(alpha: 0.45),
                  width: 0.8,
                ),
              ),
              child: Text(
                telemetry.isHiRes
                    ? context.l10n.badgeHiResLossless
                    : context.l10n.badgeLossless,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: AppFontSize.caption,
                  fontWeight: FontWeight.w800,
                  color: tierTint,
                ),
              ),
            ),
          ],
          if (!isPreview) ...[
            const SizedBox(width: AppSpacing.xxs),
            Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: p.textSecondary,
            ),
          ],
        ],
      ),
    );

    if (song == null || isPreview) return stripBody;

    return Semantics(
      button: true,
      label: '${context.l10n.audioQuality}: $primaryReadout',
      excludeSemantics: true,
      child: Material(
        color: AppColors.specularAt(0.0),
        borderRadius: AppRadii.circular(stripRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: AppRadii.circular(stripRadius),
          onTap: () => AudioQualitySheet.show(context, song, props.activeColor),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppSpacing.minTouchTarget,
            ),
            child: Align(
              alignment: Alignment.center,
              child: stripBody,
            ),
          ),
        ),
      ),
    );
  }
}

/// Precision minimal studio transport row (Shuffle, Prev, Play/Pause, Next,
/// Repeat — zero A/B clutter).
class _StudioTransportRow extends StatelessWidget {
  final PlayerThemeProps props;
  final bool isCompact;

  const _StudioTransportRow({
    required this.props,
    required this.isCompact,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = props.state;
    final cubit = props.cubit;
    final activeColor = props.activeColor;
    final isPlaying = state.isPlaying;
    final isBuffering = state.isBuffering;
    final isShuffle = state.isShuffle;
    final repeatMode = state.repeatMode;

    final double playSize = isCompact ? 54.0 : 62.0;
    final double playRadius = resolveCustomRadius(context, AppRadii.r18).clamp(
      AppRadii.r8,
      playSize / 2,
    );
    final double gap = isCompact ? AppSpacing.xs : AppSpacing.sm;
    final Color onAccent = AppColors.textOnAccent(activeColor);

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 1. Shuffle
          PlayerIconActionButton(
            icon: Icons.shuffle_rounded,
            tooltip: context.l10n.shuffle,
            isActive: isShuffle,
            iconColor: p.textSecondary,
            activeColor: activeColor,
            showActiveDot: true,
            iconSize: isCompact ? 20 : 22,
            onTap: cubit.toggleShuffle,
          ),
          SizedBox(width: gap),

          // 2. Previous
          PlayerIconActionButton(
            icon: Icons.skip_previous_rounded,
            tooltip: context.l10n.previous,
            iconColor: state.hasPreviousNeighbour
                ? p.textPrimary
                : p.textSecondary.withValues(alpha: 0.35),
            surfaceColor: p.surfaceContainer.withValues(alpha: 0.72),
            borderColor: p.hairline,
            iconSize: isCompact ? 26 : 28,
            onTap: state.hasPreviousNeighbour ? cubit.previous : null,
          ),
          SizedBox(width: gap + AppSpacing.xxs),

          // 3. Precision Studio Play / Pause Actuator
          Semantics(
            button: true,
            label: isPlaying ? context.l10n.pause : context.l10n.play,
            excludeSemantics: true,
            child: Material(
              color: activeColor,
              borderRadius: AppRadii.circular(playRadius),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {
                  PulsrHaptics.lightImpact();
                  cubit.togglePlayPause();
                },
                child: Ink(
                  width: playSize,
                  height: playSize,
                  decoration: BoxDecoration(
                    color: activeColor,
                    borderRadius: AppRadii.circular(playRadius),
                    border: Border.all(
                      color: AppColors.specularAt(0.28),
                      width: 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: activeColor.withValues(
                          alpha: isPlaying ? 0.38 : 0.22,
                        ),
                        blurRadius: isPlaying ? 20 : 12,
                        spreadRadius: -2,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: isBuffering
                        ? SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: onAccent,
                            ),
                          )
                        : Icon(
                            isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: isCompact ? 30 : 34,
                            color: onAccent,
                          ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: gap + AppSpacing.xxs),

          // 4. Next
          PlayerIconActionButton(
            icon: Icons.skip_next_rounded,
            tooltip: context.l10n.next,
            iconColor: state.hasNextNeighbour
                ? p.textPrimary
                : p.textSecondary.withValues(alpha: 0.35),
            surfaceColor: p.surfaceContainer.withValues(alpha: 0.72),
            borderColor: p.hairline,
            iconSize: isCompact ? 26 : 28,
            onTap: state.hasNextNeighbour ? cubit.next : null,
          ),
          SizedBox(width: gap),

          // 5. Repeat
          PlayerIconActionButton(
            icon: repeatMode == PlayerRepeatMode.one
                ? Icons.repeat_one_rounded
                : Icons.repeat_rounded,
            tooltip: context.l10n.repeat,
            isActive: repeatMode != PlayerRepeatMode.off,
            iconColor: p.textSecondary,
            activeColor: activeColor,
            showActiveDot: true,
            iconSize: isCompact ? 20 : 22,
            onTap: () {
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

/// Compact studio console bottom strip: Lyrics, EQ/DSP, Queue, and the
/// expandable [PlayerToolsTriggerButton] housing A/B loop & the 7-icon dock.
class _StudioBottomBar extends StatelessWidget {
  final PlayerThemeProps props;
  final bool isInSplitView;

  const _StudioBottomBar({
    required this.props,
    required this.isInSplitView,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = props.state;
    final cubit = props.cubit;
    final activeColor = props.activeColor;
    final isEqActive = state.isEqEnabled || state.dsp.isDspActive;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: p.surfaceContainer.withValues(alpha: p.isDark ? 0.68 : 0.82),
        borderRadius: AppRadii.r14All,
        border: Border.all(color: p.hairline, width: 1.0),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (!isInSplitView)
            PlayerIconActionButton(
              icon: Icons.lyrics_rounded,
              tooltip: context.l10n.lyrics,
              isActive: state.isLyricsVisible,
              iconColor: p.textSecondary,
              activeColor: activeColor,
              showActiveDot: true,
              onTap: cubit.toggleLyricsVisibility,
            ),
          PlayerIconActionButton(
            icon: Icons.equalizer_rounded,
            tooltip: context.l10n.equalizer,
            isActive: isEqActive,
            iconColor: p.textSecondary,
            activeColor: activeColor,
            showActiveDot: true,
            onTap: () => EqualizerSheet.show(context),
          ),
          if (!isInSplitView)
            PlayerIconActionButton(
              icon: Icons.queue_music_rounded,
              tooltip: context.l10n.queue,
              isActive: state.isQueueVisible,
              iconColor: p.textSecondary,
              activeColor: activeColor,
              showActiveDot: true,
              onTap: cubit.toggleQueueVisibility,
            ),
          PlayerToolsTriggerButton(
            props: props,
            iconColor: p.textSecondary,
          ),
        ],
      ),
    );
  }
}
