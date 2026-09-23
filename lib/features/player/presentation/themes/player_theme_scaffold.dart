// lib/features/player/presentation/themes/player_theme_scaffold.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/adaptive.dart';
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

/// Computed responsive metrics used across player themes.
class PlayerThemeMetrics {
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

  const PlayerThemeMetrics({
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
  });

  factory PlayerThemeMetrics.calculate(
    BuildContext context,
    BoxConstraints constraints,
  ) {
    final isTablet = context.isTablet;
    final isLandscape = context.isLandscape &&
        (context.isTwoPane || constraints.maxWidth >= 680);

    final double heightRatio =
        (constraints.maxHeight / 720.0).clamp(0.55, 1.25);
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
    final double pillBarHeight = (isTablet ? 50.0 : 44.0) * heightRatio.clamp(0.85, 1.15);

    return PlayerThemeMetrics(
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
          tooltip: 'Close',
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
            tooltip: 'Options',
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
  final Widget Function(BuildContext context, PlayerThemeMetrics metrics) body;
  final Widget Function(BuildContext context, PlayerThemeMetrics metrics)? trackInfo;
  final Widget Function(BuildContext context, PlayerThemeMetrics metrics)? seekBar;
  final Widget Function(BuildContext context, PlayerThemeMetrics metrics)? controls;
  final Widget Function(BuildContext context, PlayerThemeMetrics metrics)? bottomDock;
  final Widget Function(BuildContext context, PlayerThemeMetrics metrics)? viewSwitcher;
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
            child: LayoutBuilder(
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
                  return Padding(
                    padding: padding,
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
                              Expanded(child: resolvedCenter),
                            ],
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          flex: 5,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (trackInfo != null) trackInfo!(context, metrics),
                              SizedBox(height: metrics.spacingTrackToSeek),
                              resolvedSeekBar,
                              SizedBox(height: metrics.spacingSeekToControls),
                              resolvedControls,
                              SizedBox(height: metrics.spacingControlsToDock),
                              resolvedDock,
                              SizedBox(height: metrics.spacingBelowDock),
                            ],
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
