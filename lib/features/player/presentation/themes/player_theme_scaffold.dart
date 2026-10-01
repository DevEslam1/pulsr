// lib/features/player/presentation/themes/player_theme_scaffold.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/responsive/pulsr_layout_metrics.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/widgets/waveform_logo.dart';
import '../../../../data/db/app_database.dart';
import '../../../sheets/song_info_sheet.dart';
import '../../../ytm_search/presentation/widgets/ytm_download_button.dart';
import '../widgets/advanced_playback_bar.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/now_playing_queue_view.dart';
import '../widgets/player_controls.dart';
import '../widgets/player_seek_bar.dart';
import 'player_theme.dart';
import 'player_theme_chrome.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/responsive/pulsr_responsive_tokens.dart';
import '../../../../core/responsive/breakpoints.dart';
import '../../../../core/utils/adaptive.dart';

/// Computed responsive metrics used by [PlayerThemeScaffold].
///
/// Renamed from the former `PlayerScaffoldMetrics` to avoid colliding with the
/// canonical `PlayerScaffoldMetrics` in `player_theme_metrics.dart`.
class PlayerScaffoldMetrics {
  final BoxConstraints constraints;
  final bool isTablet;
  final bool isLandscape;
  final double heightRatio;
  final double spacingTrackToSeek;
  final double spacingSeekToControls;
  final double spacingControlsToDock;
  final double spacingBelowDock;
  final double switcherTopPad;
  final double switcherBottomPad;
  final double pillBarWidth;
  final double pillBarHeight;
  final double artworkSize;
  final double controlSize;
  final double seekBarHeight;
  final double titleFontSize;
  final bool isSplitMode;
  final bool isCompactHeight;
  final double contentPadding;

  const PlayerScaffoldMetrics({
    required this.constraints,
    required this.isTablet,
    required this.isLandscape,
    required this.heightRatio,
    required this.spacingTrackToSeek,
    required this.spacingSeekToControls,
    required this.spacingControlsToDock,
    required this.spacingBelowDock,
    required this.switcherTopPad,
    required this.switcherBottomPad,
    required this.pillBarWidth,
    required this.pillBarHeight,
    this.artworkSize = 240.0,
    this.controlSize = 64.0,
    this.seekBarHeight = 36.0,
    this.titleFontSize = 20.0,
    this.isSplitMode = false,
    this.isCompactHeight = false,
    this.contentPadding = 20.0,
  });

  factory PlayerScaffoldMetrics.calculate(
    BuildContext context,
    BoxConstraints constraints,
  ) {
    final vp = PulsrViewport.of(context);
    final isTablet = vp.isTablet;
    final isSplitMode =
        PulsrLayoutMetrics.isPlayerSplitMode(context, constraints);
    final isLandscape = isSplitMode;
    final isCompactHeight = constraints.maxHeight < 500.0 || vp.isShortHeight;

    final double heightRatio = isCompactHeight
        ? 0.85
        : (isTablet ? 1.05 : (constraints.maxHeight / 700.0).clamp(0.8, 1.18));

    final double spacingTrackToSeek = (isTablet ? 10.0 : 6.0) * heightRatio;
    final double spacingSeekToControls = (isTablet ? 12.0 : 8.0) * heightRatio;
    final double spacingControlsToDock = (isTablet ? 12.0 : 8.0) * heightRatio;
    final double spacingBelowDock = (isTablet ? 8.0 : 4.0) * heightRatio;
    final double switcherTopPad = (isTablet ? 4.0 : 2.0) * heightRatio;
    final double switcherBottomPad = (isTablet ? 6.0 : 3.0) * heightRatio;

    final double pillBarWidth = math.min(
      constraints.maxWidth - (isTablet ? 64 : 28),
      isTablet ? 440.0 : 336.0,
    );
    final double pillBarHeight =
        (isTablet ? 50.0 : 44.0) * heightRatio.clamp(0.85, 1.15);

    final double controlSize = switch (vp.sizeClass) {
      PulsrBreakpoint.compact => isCompactHeight ? 52.0 : 58.0,
      PulsrBreakpoint.medium => 64.0,
      PulsrBreakpoint.expanded => 68.0,
      PulsrBreakpoint.large => 74.0,
    };

    final double seekBarHeight = isTablet ? 40.0 : 32.0;
    final double titleFontSize = isTablet ? 24.0 : 20.0;
    final double contentPadding = vp.pagePadding;

    final double maxArt = isSplitMode
        ? (isCompactHeight ? 260.0 : 380.0)
        : (isTablet ? 560.0 : 420.0);
    final double rawArt = isSplitMode
        ? math.min(constraints.maxWidth * 0.45, constraints.maxHeight - 48.0)
        : math.min(constraints.maxWidth - (contentPadding * 2),
            constraints.maxHeight * 0.45);
    final double artworkSize = rawArt.clamp(140.0, maxArt);

    return PlayerScaffoldMetrics(
      constraints: constraints,
      isTablet: isTablet,
      isLandscape: isLandscape,
      heightRatio: heightRatio,
      spacingTrackToSeek: spacingTrackToSeek,
      spacingSeekToControls: spacingSeekToControls,
      spacingControlsToDock: spacingControlsToDock,
      spacingBelowDock: spacingBelowDock,
      switcherTopPad: switcherTopPad,
      switcherBottomPad: switcherBottomPad,
      pillBarWidth: pillBarWidth,
      pillBarHeight: pillBarHeight,
      artworkSize: artworkSize,
      controlSize: controlSize,
      seekBarHeight: seekBarHeight,
      titleFontSize: titleFontSize,
      isSplitMode: isSplitMode,
      isCompactHeight: isCompactHeight,
      contentPadding: contentPadding,
    );
  }

  /// Computes a safe artwork or deck dimension that never overflows available bounds.
  static double safeArtworkSize({
    required double availableWidth,
    required double availableHeight,
    required bool isTablet,
    double? maxAllowedOverride,
  }) {
    final double maxAllowed = maxAllowedOverride ?? (isTablet ? 560.0 : 420.0);
    final double raw = math.min(availableWidth, availableHeight);
    if (raw <= 0) return 0.0;
    return math.min(raw, maxAllowed);
  }
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
    final hasDownload = song != null &&
        (song.source == SongSource.youtube ||
            (song.remoteId != null && song.remoteId!.isNotEmpty));

    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
          color: p.textPrimary,
          tooltip: context.l10n.close,
          onPressed: onBack ?? () => Navigator.of(context).maybePop(),
        ),
        Expanded(
          child: Center(
            child: titleWidget ??
                WaveformLogo(
                  animate: props.state.isPlaying,
                  color: props.activeColor,
                  size: 13,
                ),
          ),
        ),
        if (customActions != null)
          ...customActions!
        else ...[
          if (hasDownload)
            YtmDownloadButton(
              song: song,
              activeColor: props.activeColor,
              iconColor: p.textSecondary,
              iconSize: 20,
            ),
          PlayerAnimatedFavoriteButton(
            isFavorite: song?.isFavorite == true,
            semanticLabel: song?.isFavorite == true
                ? context.l10n.unlike
                : context.l10n.like,
            favoriteColor: p.favorite,
            inactiveColor: p.textSecondary,
            onTap: () {
              if (song != null) props.cubit.toggleFavorite(song.id);
            },
          ),
          IconButton(
            icon: const Icon(Icons.more_vert_rounded, size: 22),
            color: p.textPrimary,
            tooltip: context.l10n.moreOptions,
            onPressed: () {
              if (song != null) {
                SongInfoSheet.show(context, song: song);
              }
            },
          ),
        ],
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
  final Widget Function(BuildContext context, PlayerScaffoldMetrics metrics) body;
  final Widget Function(BuildContext context, PlayerScaffoldMetrics metrics)?
      trackInfo;
  final Widget Function(BuildContext context, PlayerScaffoldMetrics metrics)?
      seekBar;
  final Widget Function(BuildContext context, PlayerScaffoldMetrics metrics)?
      controls;
  final Widget Function(BuildContext context, PlayerScaffoldMetrics metrics)?
      bottomDock;
  final Widget Function(BuildContext context, PlayerScaffoldMetrics metrics)?
      viewSwitcher;
  final EdgeInsetsGeometry padding;

  const PlayerThemeScaffold({
    super.key,
    required this.props,
    required this.body,
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
  });

  @override
  Widget build(BuildContext context) {
    final state = props.state;
    final cubit = props.cubit;
    final song = state.currentSong;
    final activeColor = props.activeColor;

    return AnimatedContainer(
      duration: context.motionMs(400),
      curve: context.motionCurve(Curves.easeInOut),
      color: props.bgColor,
      child: Stack(
        children: [
          if (background != null) Positioned.fill(child: background!),
          if (ambientGlow != null) Positioned.fill(child: ambientGlow!),
          SafeArea(
            top: true,
            bottom: false,
            left: !context.isLandscape,
            right: !context.isLandscape,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final metrics =
                    PlayerScaffoldMetrics.calculate(context, constraints);

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
                        barHeight: metrics.pillBarHeight,
                        dockIconStyle: dockIconStyle,
                      );

                final resolvedTopBar = topBar ?? PlayerHeaderBar(props: props);

                final Widget resolvedCenter;
                if (showLyricsAndQueueOverlays && state.isLyricsVisible) {
                  resolvedCenter = LyricsView(
                    key: ValueKey('lyrics_${song?.id}_${song?.remoteId}'),
                    lyrics: state.lyrics,
                    isLoading: state.isLoadingLyrics,
                    activeColor: activeColor,
                    source: state.lyricsSource,
                  );
                } else if (showLyricsAndQueueOverlays && state.isQueueVisible) {
                  resolvedCenter = const NowPlayingQueueView();
                } else {
                  resolvedCenter = body(context, metrics);
                }

                final Widget resolvedSeekBar = seekBar != null
                    ? seekBar!(context, metrics)
                    : PlayerSeekBar(
                        duration: state.duration,
                        activeColor: activeColor,
                        songId: song?.id,
                        filePath: song?.path,
                        loopPointA: state.abPointA,
                        loopPointB: state.abPointB,
                        onSeek: (pos) => cubit.seek(pos),
                      );

                final Widget resolvedControls = controls != null
                    ? controls!(context, metrics)
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          PlayerControls(
                            isPlaying: state.isPlaying,
                            isShuffle: state.isShuffle,
                            repeatMode: state.repeatMode,
                            hasPrevious: state.hasPreviousNeighbour,
                            hasNext: state.hasNextNeighbour,
                            abLoopActive: state.abLoopEnabled,
                            primaryColor: activeColor,
                            mainButtonSize: metrics.isTablet
                                ? 72
                                : (metrics.isLandscape ? 56 : 64),
                            onPlayPause: () => cubit.togglePlayPause(),
                            onNext: () => cubit.next(),
                            onPrevious: () => cubit.previous(),
                            onToggleShuffle: () => cubit.toggleShuffle(),
                            onToggleRepeat: () => cubit.toggleRepeat(),
                          ),
                          const SizedBox(height: 8),
                          const AdvancedPlaybackBar(),
                        ],
                      );

                if (metrics.isLandscape) {
                  final insets = MediaQuery.paddingOf(context);
                  final horizontalPad =
                      math.max(16.0, math.max(insets.left, insets.right));
                  final effectivePadding = EdgeInsets.symmetric(
                    horizontal: metrics.isTablet
                        ? math.max(32.0, horizontalPad)
                        : horizontalPad,
                    vertical: metrics.isCompactHeight ? 4.0 : 8.0,
                  );

                  return Padding(
                    padding: effectivePadding,
                    child: Row(
                      children: [
                        Expanded(
                          flex: 5,
                          child: Column(
                            children: [
                              resolvedTopBar,
                              SizedBox(height: metrics.switcherTopPad),
                              resolvedSwitcher,
                              SizedBox(height: metrics.switcherBottomPad),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius:
                                      BorderRadius.circular(AppRadii.r24),
                                  child: resolvedCenter,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          flex: 5,
                          child: Center(
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (trackInfo != null)
                                    trackInfo!(context, metrics),
                                  SizedBox(height: metrics.spacingTrackToSeek),
                                  resolvedSeekBar,
                                  SizedBox(
                                      height: metrics.spacingSeekToControls),
                                  resolvedControls,
                                  SizedBox(
                                      height: metrics.spacingControlsToDock),
                                  resolvedDock,
                                  SizedBox(height: metrics.spacingBelowDock),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
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
                      if (trackInfo != null) ...[
                        trackInfo!(context, metrics),
                        SizedBox(height: metrics.spacingTrackToSeek),
                      ],
                      resolvedSeekBar,
                      SizedBox(height: metrics.spacingSeekToControls),
                      resolvedControls,
                      SizedBox(height: metrics.spacingControlsToDock),
                      resolvedDock,
                      SizedBox(height: metrics.spacingBelowDock),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
