// lib/features/player/presentation/themes/player_theme_scaffold.dart
import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/waveform_logo.dart';
import '../../../../data/db/app_database.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../../settings/cubit/settings_state.dart';
import '../../../sheets/song_options_sheet.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/now_playing_queue_view.dart';
import '../widgets/player_controls.dart';
import '../widgets/player_seek_bar.dart';
import '../widgets/player_volume_bar.dart';
import '../widgets/radio_now_playing_recommendations.dart';
import 'player_theme.dart';
import 'player_theme_chrome.dart';
import 'package:pulsr/core/constants/app_spacing.dart';

/// Computed responsive metrics used across player themes.
class PlayerThemeMetrics {
  final BoxConstraints constraints;
  final bool isTablet;
  final bool isLandscape;
  final double heightRatio;
  final bool isShortHeight;
  final bool isVeryShortHeight;
  final bool isCompactHeight;
  final double spacingTrackToSeek;
  final double spacingSeekToControls;
  final double spacingSeekToAdvanced;
  final double spacingAdvancedToControls;
  final double spacingControlsToDock;
  final double spacingBelowDock;
  final double switcherTopPad;
  final double switcherBottomPad;
  final double pillBarWidth;
  final double pillBarHeight;
  final double mainButtonSize;
  final double sideButtonSize;
  final double waveformHeight;
  final bool showUpNext;
  final double trackHeaderVerticalPadding;
  final double titleFontSize;
  final double artistFontSize;
  final double actionButtonSize;
  final double dockBarHeight;

  const PlayerThemeMetrics({
    required this.constraints,
    required this.isTablet,
    required this.isLandscape,
    required this.heightRatio,
    this.isShortHeight = false,
    this.isVeryShortHeight = false,
    this.isCompactHeight = false,
    required this.spacingTrackToSeek,
    required this.spacingSeekToControls,
    this.spacingSeekToAdvanced = 8.0,
    this.spacingAdvancedToControls = 8.0,
    required this.spacingControlsToDock,
    required this.spacingBelowDock,
    required this.switcherTopPad,
    required this.switcherBottomPad,
    required this.pillBarWidth,
    required this.pillBarHeight,
    this.mainButtonSize = 64.0,
    this.sideButtonSize = 44.0,
    this.waveformHeight = 44.0,
    this.showUpNext = true,
    this.trackHeaderVerticalPadding = 6.0,
    this.titleFontSize = 19.5,
    this.artistFontSize = 13.5,
    this.actionButtonSize = 44.0,
    this.dockBarHeight = 54.0,
  });

  factory PlayerThemeMetrics.calculate(
    BuildContext context,
    BoxConstraints constraints,
  ) {
    final isTablet = context.isTablet;
    final isLandscape = (context.isLandscape || context.isTwoPane) &&
        (constraints.maxWidth > constraints.maxHeight);
    final double maxH = constraints.maxHeight;
    final double maxW = constraints.maxWidth;

    final double heightRatio = (maxH / 720.0).clamp(0.55, 1.25);

    final bool isShortHeight = maxH < 680.0;
    final bool isVeryShortHeight = maxH < 580.0;
    final bool isCompactHeight = maxH < 760.0;

    final double spacingTrackToSeek = isTablet
        ? 16.0 * heightRatio
        : (isLandscape
            ? 4.0
            : (isShortHeight
                ? 6.0
                : (isCompactHeight ? 9.0 : 12.0 * heightRatio)));

    final double spacingSeekToControls = isTablet
        ? 20.0 * heightRatio
        : (isLandscape
            ? 6.0
            : (isShortHeight
                ? 8.0
                : (isCompactHeight ? 11.0 : 16.0 * heightRatio)));

    final double spacingSeekToAdvanced = isTablet
        ? 12.0 * heightRatio
        : (isLandscape
            ? 4.0
            : (isShortHeight
                ? 4.0
                : (isCompactHeight ? 6.0 : 10.0 * heightRatio)));

    final double spacingAdvancedToControls = isTablet
        ? 14.0 * heightRatio
        : (isLandscape
            ? 4.0
            : (isShortHeight
                ? 4.0
                : (isCompactHeight ? 6.0 : 12.0 * heightRatio)));

    final double spacingControlsToDock = isTablet
        ? 18.0 * heightRatio
        : (isLandscape
            ? 6.0
            : (isShortHeight
                ? 8.0
                : (isCompactHeight ? 11.0 : 14.0 * heightRatio)));

    final double spacingBelowDock = isTablet
        ? 14.0 * heightRatio
        : (isLandscape
            ? 6.0
            : (isShortHeight
                ? 6.0
                : (isCompactHeight ? 8.0 : 10.0 * heightRatio)));

    final double switcherTopPad = isTablet
        ? 4.0 * heightRatio
        : (isLandscape
            ? 1.0
            : (isShortHeight
                ? 1.0
                : (isCompactHeight ? 2.0 : 2.0 * heightRatio)));

    final double switcherBottomPad = isTablet
        ? 6.0 * heightRatio
        : (isLandscape
            ? 2.0
            : (isShortHeight
                ? 2.0
                : (isCompactHeight ? 3.0 : 4.0 * heightRatio)));

    final double pillBarWidth = math.min(
      maxW - (isTablet ? 80 : 36),
      isTablet ? 380.0 : 296.0,
    );
    final double pillBarHeight = isTablet
        ? 44.0 * heightRatio.clamp(0.85, 1.10)
        : (isShortHeight
            ? 34.0
            : (isCompactHeight ? 36.0 : 38.0 * heightRatio.clamp(0.85, 1.10)));

    final double mainButtonSize = isTablet
        ? 72.0
        : (isLandscape
            ? 54.0
            : (isVeryShortHeight
                ? 52.0
                : (isShortHeight
                    ? 56.0
                    : (isCompactHeight
                        ? 62.0
                        : 66.0 * heightRatio.clamp(0.95, 1.15)))));

    // Transport targets are never allowed below the 48 dp accessibility
    // minimum, regardless of height class.
    final double sideButtonSize = isTablet ? 52.0 : 48.0;

    final double waveformHeight = isTablet
        ? 48.0
        : (isLandscape
            ? 28.0
            : (isVeryShortHeight
                ? 28.0
                : (isShortHeight ? 32.0 : (isCompactHeight ? 36.0 : 44.0))));

    final bool showUpNext = !isLandscape && maxH >= 640.0;

    final double trackHeaderVerticalPadding = isTablet
        ? 8.0
        : (isLandscape
            ? 0.0
            : (isShortHeight ? 2.0 : (isCompactHeight ? 4.0 : 6.0)));

    final double titleFontSize = isTablet
        ? 22.0
        : (isVeryShortHeight
            ? 16.0
            : (isShortHeight ? 17.0 : (isCompactHeight ? 18.0 : 19.5)));

    final double artistFontSize = isTablet
        ? 14.5
        : (isVeryShortHeight
            ? 11.5
            : (isShortHeight ? 12.0 : (isCompactHeight ? 13.0 : 14.0)));

    final double actionButtonSize = isTablet
        ? 48.0
        : (isShortHeight ? 38.0 : (isCompactHeight ? 42.0 : 46.0));

    // 54dp outer - 3dp inset each side leaves a 48dp target inside the dock.
    // Five actions now share the bar, so the extra height is what keeps the
    // icons from shrinking below the minimum touch target.
    final double dockBarHeight = isTablet ? 56.0 : 54.0;

    return PlayerThemeMetrics(
      constraints: constraints,
      isTablet: isTablet,
      isLandscape: isLandscape,
      heightRatio: heightRatio,
      isShortHeight: isShortHeight,
      isVeryShortHeight: isVeryShortHeight,
      isCompactHeight: isCompactHeight,
      spacingTrackToSeek: spacingTrackToSeek,
      spacingSeekToControls: spacingSeekToControls,
      spacingSeekToAdvanced: spacingSeekToAdvanced,
      spacingAdvancedToControls: spacingAdvancedToControls,
      spacingControlsToDock: spacingControlsToDock,
      spacingBelowDock: spacingBelowDock,
      switcherTopPad: switcherTopPad,
      switcherBottomPad: switcherBottomPad,
      pillBarWidth: pillBarWidth,
      pillBarHeight: pillBarHeight,
      mainButtonSize: mainButtonSize,
      sideButtonSize: sideButtonSize,
      waveformHeight: waveformHeight,
      showUpNext: showUpNext,
      trackHeaderVerticalPadding: trackHeaderVerticalPadding,
      titleFontSize: titleFontSize,
      artistFontSize: artistFontSize,
      actionButtonSize: actionButtonSize,
      dockBarHeight: dockBarHeight,
    );
  }

  /// Computes a safe artwork or deck dimension that never overflows available bounds.
  static double safeArtworkSize({
    required double availableWidth,
    required double availableHeight,
    required bool isTablet,
    double? maxAllowedOverride,
  }) {
    final double maxAllowed = maxAllowedOverride ?? (isTablet ? 600.0 : 480.0);
    final double raw = math.min(availableWidth, availableHeight);
    if (raw <= 0) return 0.0;
    return math.min(raw, maxAllowed);
  }
}

/// Inherited scope indicating that a player theme is being rendered inside a
/// scaled picker thumbnail ([ThemeRegistry.preview] with `isPreview: true`).
///
/// Themes and shared chrome consult [PlayerThemePreviewScope.of] to suppress
/// transient banners, radio recommendation cards, lyrics/queue overlays, and
/// live tickers so preview thumbnails fit cleanly without overflow.
class PlayerThemePreviewScope extends InheritedWidget {
  final bool isPreview;

  const PlayerThemePreviewScope({
    super.key,
    required this.isPreview,
    required super.child,
  });

  static bool of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<PlayerThemePreviewScope>()
            ?.isPreview ??
        false;
  }

  @override
  bool updateShouldNotify(PlayerThemePreviewScope oldWidget) =>
      isPreview != oldWidget.isPreview;
}

/// Standard player header bar shared by themes.
class PlayerHeaderBar extends StatelessWidget {
  final PlayerThemeProps props;
  final Widget? titleWidget;
  final List<Widget>? customActions;
  final VoidCallback? onBack;

  const PlayerHeaderBar({
    super.key,
    required this.props,
    this.titleWidget,
    this.customActions,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final song = props.state.currentSong;
    final allowMotion = PulsrMotion.shouldAnimate(context);

    return Row(
      children: [
        IconButton(
          constraints: const BoxConstraints(
              minWidth: AppSpacing.minTouchTarget,
              minHeight: AppSpacing.minTouchTarget),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
          color: p.textPrimary,
          tooltip: context.l10n.close,
          onPressed: onBack ?? () => Navigator.of(context).maybePop(),
        ),
        Expanded(
          child: Semantics(
            header: true,
            child: Center(
              child: titleWidget ??
                  ExcludeSemantics(
                    child: WaveformLogo(
                      animate: props.state.isPlaying && allowMotion,
                      color: props.activeColor,
                      size: 13,
                    ),
                  ),
            ),
          ),
        ),
        // Download and favourite live in the track header beside the title;
        // repeating them here duplicated the actions and crowded the bar.
        if (customActions != null)
          ...customActions!
        else
          IconButton(
            constraints: const BoxConstraints(
                minWidth: AppSpacing.minTouchTarget,
                minHeight: AppSpacing.minTouchTarget),
            icon: const Icon(Icons.more_vert_rounded, size: 22),
            color: p.textPrimary,
            tooltip: context.l10n.moreOptions,
            onPressed: () {
              if (song != null) {
                SongOptionsSheet.show(context, song: song);
              }
            },
          ),
      ],
    );
  }
}

/// Unified scaffold for Now-Playing themes.
///
/// Handles responsive layout constraints, view switching (Track/Lyrics/Queue),
/// header bar, bottom dock, and standard seek bar / controls placement.
class PlayerThemeScaffold extends StatelessWidget {
  final PlayerThemeProps props;
  final Widget? background;
  final Widget? ambientGlow;
  final Widget? topBar;
  final IconData trackIcon;
  final double switcherSurfaceFillAlpha;
  final double switcherBorderAlpha;
  final PlayerDockIconStyle dockIconStyle;
  final bool showLyricsAndQueueOverlays;
  final Widget Function(BuildContext context, PlayerThemeMetrics metrics) body;
  final Widget Function(BuildContext context, PlayerThemeMetrics metrics)?
      chrome;
  final Widget Function(BuildContext context, PlayerThemeMetrics metrics)?
      trackInfo;
  final Widget Function(BuildContext context, PlayerThemeMetrics metrics)?
      seekBar;
  final Widget Function(BuildContext context, PlayerThemeMetrics metrics)?
      controls;
  final Widget Function(BuildContext context, PlayerThemeMetrics metrics)?
      bottomDock;
  final Widget Function(BuildContext context, PlayerThemeMetrics metrics)?
      viewSwitcher;
  final EdgeInsetsGeometry padding;
  final bool hideTopBarInLandscape;
  final bool showLegibilityScrims;

  PlayerThemeScaffold({
    super.key,
    required this.props,
    Widget Function(BuildContext context, PlayerThemeMetrics metrics)? body,
    Widget Function(BuildContext context, PlayerThemeMetrics metrics)? stage,
    this.chrome,
    this.background,
    this.ambientGlow,
    this.topBar,
    this.trackIcon = Icons.album_rounded,
    this.switcherSurfaceFillAlpha = 0.06,
    this.switcherBorderAlpha = 0.12,
    this.dockIconStyle = PlayerDockIconStyle.common,
    this.showLyricsAndQueueOverlays = true,
    this.trackInfo,
    this.seekBar,
    this.controls,
    this.bottomDock,
    this.viewSwitcher,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
    this.hideTopBarInLandscape = false,
    this.showLegibilityScrims = false,
  }) : body = stage ?? body ?? ((context, metrics) => const SizedBox.shrink());

  @override
  Widget build(BuildContext context) {
    final state = props.state;
    final cubit = props.cubit;
    final song = state.currentSong;
    final activeColor = props.activeColor;
    final isInSplitView = PlayerSplitViewScope.of(context);
    final isPreview = PlayerThemePreviewScope.of(context);
    final surface = context.playerSurfacePalette;
    final effectiveShowOverlays = showLyricsAndQueueOverlays && !isPreview;
    final textScale =
        MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 2.0);

    final content = LayoutBuilder(
      builder: (context, constraints) {
        final metrics = PlayerThemeMetrics.calculate(context, constraints);

        final resolvedSwitcher = viewSwitcher != null
            ? viewSwitcher!(context, metrics)
            : PlayerViewSwitcher(
                state: state,
                cubit: cubit,
                activeColor: activeColor,
                isTablet: metrics.isTablet,
                barWidth: metrics.pillBarWidth,
                barHeight: metrics.pillBarHeight,
                trackIcon: trackIcon,
                surfaceFillAlpha: switcherSurfaceFillAlpha,
                borderAlpha: switcherBorderAlpha,
              );

        final resolvedDock = bottomDock != null
            ? bottomDock!(context, metrics)
            : PlayerBottomActionDock(
                props: props,
                isTablet: metrics.isTablet,
                barWidth: metrics.pillBarWidth,
                barHeight: metrics.dockBarHeight,
                dockIconStyle: dockIconStyle,
              );

        final resolvedTopBar = topBar ?? PlayerHeaderBar(props: props);

        final Widget resolvedChild;
        if (effectiveShowOverlays && state.isLyricsVisible) {
          resolvedChild = LyricsView(
            key: ValueKey('lyrics_${song?.id}_${song?.remoteId}'),
            lyrics: state.lyrics,
            isLoading: state.isLoadingLyrics,
            activeColor: activeColor,
            source: state.lyricsSource,
          );
        } else if (effectiveShowOverlays && state.isQueueVisible) {
          resolvedChild =
              const NowPlayingQueueView(key: ValueKey('queue_view'));
        } else {
          resolvedChild = KeyedSubtree(
            key: const ValueKey('stage_body'),
            child: body(context, metrics),
          );
        }

        final Widget resolvedCenter = effectiveShowOverlays
            ? AnimatedSwitcher(
                duration: context.motionMs(320),
                transitionBuilder: (child, anim) =>
                    playerOverlayTransitionBuilder(context, child, anim),
                child: resolvedChild,
              )
            : resolvedChild;

        final Widget resolvedSeekBar = seekBar != null
            ? seekBar!(context, metrics)
            : PlayerSeekBar(
                duration: state.duration,
                activeColor: activeColor,
                songId: song?.id,
                filePath: song?.path,
                loopPointA: isPreview ? null : state.abPointA,
                loopPointB: isPreview ? null : state.abPointB,
                showUpNext: !isPreview && metrics.showUpNext,
                waveformHeight: metrics.waveformHeight,
                onSeek: (pos) => cubit.seek(pos),
              );

        ExperienceMode mode = ExperienceMode.normal;
        try {
          mode = context.select<SettingsCubit, ExperienceMode>(
              (c) => c.state.experienceMode);
        } catch (_) {}
        final showAbControls = !isPreview &&
            (mode == ExperienceMode.professional ||
                state.abPointA != null ||
                state.abPointB != null);

        final Widget resolvedControls = controls != null
            ? controls!(context, metrics)
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isPreview && state.bookmarkPosition != null) ...[
                    PlayerBookmarkPromptBanner(
                      cubit: cubit,
                      position: state.bookmarkPosition!,
                    ),
                    const SizedBox(height: 8),
                  ],
                  PlayerControls(
                    isPlaying: state.isPlaying,
                    isBuffering: state.isBuffering,
                    isShuffle: state.isShuffle,
                    repeatMode: state.repeatMode,
                    hasPrevious: state.hasPreviousNeighbour,
                    hasNext: state.hasNextNeighbour,
                    abLoopActive: isPreview ? false : state.abLoopEnabled,
                    showAbControls: showAbControls,
                    abPointA: isPreview ? null : state.abPointA,
                    abPointB: isPreview ? null : state.abPointB,
                    onSetAbPointA: () => cubit.setAbPointA(),
                    onSetAbPointB: () => cubit.setAbPointB(),
                    onToggleAbLoop: () => cubit.toggleAbLoop(),
                    onClearAbLoop: () => cubit.clearAbLoop(),
                    primaryColor: activeColor,
                    mainButtonSize: metrics.mainButtonSize,
                    sideButtonSize: metrics.sideButtonSize,
                    onPlayPause: () => cubit.togglePlayPause(),
                    onNext: () => cubit.next(),
                    onPrevious: () => cubit.previous(),
                    onToggleShuffle: () => cubit.toggleShuffle(),
                    onToggleRepeat: () => cubit.toggleRepeat(),
                  ),
                ],
              );

        final Widget resolvedChrome = chrome != null
            ? chrome!(context, metrics)
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (trackInfo != null) ...[
                    trackInfo!(context, metrics),
                    SizedBox(height: metrics.spacingTrackToSeek),
                  ],
                  resolvedSeekBar,
                  if (!isPreview && song?.source == SongSource.radio) ...[
                    const SizedBox(height: AppSpacing.xs),
                    RadioNowPlayingRecommendations(
                      props: props,
                      cubit: cubit,
                      metrics: metrics,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                  ] else ...[
                    SizedBox(height: metrics.spacingSeekToControls),
                  ],
                  resolvedControls,
                  if (!isPreview && isInSplitView && !metrics.isVeryShortHeight)
                    PlayerVolumeBar(cubit: cubit, activeColor: activeColor),
                  SizedBox(height: metrics.spacingControlsToDock),
                  resolvedDock,
                  SizedBox(height: metrics.spacingBelowDock),
                ],
              );

        if (isPreview) {
          return Padding(
            padding: padding,
            child: Column(
              children: [
                const SizedBox(height: AppSpacing.sm),
                Expanded(child: resolvedCenter),
                resolvedChrome,
              ],
            ),
          );
        }

        if (isInSplitView) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                const SizedBox(height: 8),
                Expanded(child: Center(child: resolvedCenter)),
                resolvedChrome,
              ],
            ),
          );
        }

        if (metrics.isLandscape) {
          return Padding(
            padding: padding,
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: hideTopBarInLandscape
                      ? Center(child: resolvedCenter)
                      : Column(
                          children: [
                            resolvedTopBar,
                            Expanded(
                              child: Center(child: resolvedCenter),
                            ),
                          ],
                        ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 5,
                  child: Center(
                    key: const ValueKey('track_controls_pane'),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Padding(
                            padding: EdgeInsets.only(
                              bottom: metrics.switcherBottomPad,
                            ),
                            child: resolvedSwitcher,
                          ),
                          resolvedChrome,
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        // Portrait Mode: Fallback to scrolling on very short screens or large
        // accessibility text scales so chrome never overflows the viewport.
        final double portraitScrollThreshold =
            560.0 + (textScale - 1.0) * 120.0;
        if (constraints.maxHeight < portraitScrollThreshold &&
            !state.isLyricsVisible &&
            !state.isQueueVisible) {
          final double scrollSize =
              (constraints.maxHeight * 0.40).clamp(180.0, 300.0);
          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: padding,
              child: Column(
                children: [
                  resolvedTopBar,
                  SizedBox(height: metrics.switcherTopPad),
                  resolvedSwitcher,
                  SizedBox(height: metrics.switcherBottomPad),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: scrollSize,
                      maxHeight: scrollSize,
                    ),
                    child: resolvedCenter,
                  ),
                  resolvedChrome,
                ],
              ),
            ),
          );
        }

        return Padding(
          padding: padding,
          child: Column(
            children: [
              resolvedTopBar,
              SizedBox(height: metrics.switcherTopPad),
              resolvedSwitcher,
              SizedBox(height: metrics.switcherBottomPad),
              Expanded(child: resolvedCenter),
              resolvedChrome,
            ],
          ),
        );
      },
    );

    if (isInSplitView) {
      return content;
    }

    final isHighContrast =
        context.palette.isHighContrast || MediaQuery.highContrastOf(context);
    final bool effectiveScrims = !isHighContrast &&
        (showLegibilityScrims || (background == null && !isPreview));

    return AnimatedContainer(
      duration: context.motionMs(400),
      curve: context.motionCurve(Curves.easeInOut),
      color: props.bgColor,
      child: Stack(
        children: [
          if (background != null)
            Positioned.fill(child: ExcludeSemantics(child: background!)),
          if (ambientGlow != null)
            Positioned.fill(child: ExcludeSemantics(child: ambientGlow!)),
          if (effectiveScrims) ...[
            PositionedDirectional(
              top: 0,
              start: 0,
              end: 0,
              height: 120,
              child: ExcludeSemantics(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          surface.scrimStart.withValues(alpha: 0.48),
                          surface.scrimStart.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            PositionedDirectional(
              bottom: 0,
              start: 0,
              end: 0,
              height: 200,
              child: ExcludeSemantics(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          surface.scrimEnd.withValues(alpha: 0.52),
                          surface.scrimEnd.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          SafeArea(child: content),
        ],
      ),
    );
  }
}
