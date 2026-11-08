// lib/features/player/presentation/themes/milkdrop_player_theme.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';

import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/utils/adaptive.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../../settings/cubit/settings_state.dart';
import '../widgets/audio_visualizer.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/now_playing_queue_view.dart';
import 'player_shape.dart';
import 'player_theme.dart';
import 'player_theme_chrome.dart';
import 'player_theme_scaffold.dart';

/// Full-screen White Transparent Milkdrop Player Theme.
///
/// Features:
/// 1. Audio-reactive MilkDrop visualizer spanning across the entire screen
///    behind the album artwork and controls, rendered in white translucent
///    flowing waves, warped tunnel depth rings, and shimmering particles.
/// 2. Floating center album artwork stage with smooth elevation, frosted border,
///    ambient drop shadow, and gesture interactions.
/// 3. Frosted translucent controls chrome ensuring 100% legibility and contrast
///    over the full-screen visualizer backdrop.
/// 4. Full phone landscape, tablet split-view, and compact height responsiveness.
class MilkdropPlayerTheme extends StatelessWidget {
  final PlayerThemeProps props;

  const MilkdropPlayerTheme({super.key, required this.props});

  @override
  Widget build(BuildContext context) {
    final state = props.state;
    final cubit = props.cubit;
    final activeColor = props.activeColor;
    final song = state.currentSong;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final (
      :nowPlayingDoubleTap,
      :nowPlayingArtworkSwipe,
      :playerSliderStyle,
      :themeMode,
    ) = context.select<
        SettingsCubit,
        ({
          NowPlayingDoubleTapAction nowPlayingDoubleTap,
          NowPlayingArtworkSwipeAction nowPlayingArtworkSwipe,
          PlayerSliderStyle playerSliderStyle,
          AppThemeMode themeMode,
        })>((c) => (
          nowPlayingDoubleTap: c.state.nowPlayingDoubleTap,
          nowPlayingArtworkSwipe: c.state.nowPlayingArtworkSwipe,
          playerSliderStyle: c.state.playerSliderStyle,
          themeMode: c.state.themeMode,
        ));

    final artRadius = resolveCustomRadius(context, AppRadii.r28);
    final isTablet = context.isTablet;
    final isInSplitView = PlayerSplitViewScope.of(context);
    final isAmoled = themeMode == AppThemeMode.amoled;

    final Color topBg = isAmoled
        ? Colors.black
        : Color.alphaBlend(
            Colors.black.withValues(alpha: isDark ? 0.40 : 0.15),
            props.bgColor,
          );
    final Color bottomBg = isAmoled
        ? Colors.black
        : Color.alphaBlend(
            Colors.black.withValues(alpha: isDark ? 0.60 : 0.25),
            props.bgColor,
          );

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Ambient Dynamic Color Gradient Base
        Positioned.fill(
          child: RepaintBoundary(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [topBg, bottomBg],
                ),
              ),
            ),
          ),
        ),

        // 2. Full-Screen Audio-Reactive Milkdrop Visualizer Layer (Across All Screen)
        Positioned.fill(
          child: RepaintBoundary(
            child: AudioVisualizer(
              style: VisualizerStyle.milkdrop,
              color: Colors.white,
              transparentBackground: true,
              isPlaying: state.isPlaying,
              audioSessionId: state.audioSessionId,
              trackId: song?.id,
              trackPath: song?.path,
            ),
          ),
        ),

        // 3. Subtle ambient vignettes for optimal text legibility and contrast
        PositionedDirectional(
          top: 0,
          start: 0,
          end: 0,
          height: 140,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: isDark ? 0.45 : 0.15),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        PositionedDirectional(
          bottom: 0,
          start: 0,
          end: 0,
          height: 220,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: isDark ? 0.60 : 0.20),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),

        // 4. Foreground Content: Floating Artwork + Chrome Controls
        LayoutBuilder(
          builder: (context, constraints) {
            final metrics = PlayerThemeMetrics.calculate(context, constraints);
            final isLandscape = metrics.isLandscape;

            final switcherTopPad =
                (isTablet ? 8.0 : 4.0) * metrics.heightRatio;
            final switcherBottomPad =
                (isTablet ? 12.0 : 8.0) * metrics.heightRatio;
            final landscapeArtSize =
                (constraints.maxHeight - 24).clamp(180.0, 560.0);

            final viewSwitcher = PlayerViewSwitcher(
              state: state,
              cubit: cubit,
              activeColor: activeColor,
              isTablet: isTablet,
              barWidth: isLandscape ? 286.0 : metrics.pillBarWidth,
              barHeight: isLandscape ? 36.0 : metrics.pillBarHeight,
              trackIcon: Icons.blur_on_rounded,
              surfaceFillAlpha: 0.10,
              borderAlpha: 0.18,
            );

            final bottomDock = PlayerBottomActionDock(
              props: props,
              isTablet: isTablet,
              barWidth: metrics.pillBarWidth,
              barHeight: metrics.dockBarHeight,
              dockIconStyle: PlayerDockIconStyle.classic,
            );

            // Floating Artwork Hero Stage ("beehind the image")
            final artworkDisplay = GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => cubit.toggleLyricsVisibility(),
              onDoubleTap: () {
                switch (nowPlayingDoubleTap) {
                  case NowPlayingDoubleTapAction.toggleFavorite:
                    if (song != null) cubit.toggleFavorite(song.id);
                    break;
                  case NowPlayingDoubleTapAction.toggleLyrics:
                    cubit.toggleLyricsVisibility();
                    break;
                  case NowPlayingDoubleTapAction.none:
                    break;
                }
              },
              onHorizontalDragEnd: (details) {
                if (nowPlayingArtworkSwipe ==
                        NowPlayingArtworkSwipeAction.nextPrev &&
                    details.primaryVelocity != null) {
                  if (details.primaryVelocity! < -200) {
                    cubit.next();
                  } else if (details.primaryVelocity! > 200) {
                    cubit.previous();
                  }
                }
              },
              child: Center(
                key: const ValueKey('artwork_view_milkdrop'),
                child: AnimatedScale(
                  scale: state.isPlaying ? 1.0 : 0.97,
                  duration: context.motionMs(320),
                  curve: context.motionCurve(Curves.easeOutCubic),
                  child: AspectRatio(
                    aspectRatio: 1.0,
                    child: Hero(
                      tag: props.heroTag,
                      child: AnimatedContainer(
                        duration: context.motionMs(320),
                        curve: context.motionCurve(Curves.easeOutCubic),
                        decoration: BoxDecoration(
                          borderRadius: AppRadii.circular(artRadius),
                          border: Border.all(
                            color: Colors.white.withValues(
                              alpha: state.isPlaying ? 0.28 : 0.16,
                            ),
                            width: 1.4,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: 0.45,
                              ),
                              blurRadius: 36,
                              spreadRadius: 2,
                              offset: const Offset(0, 16),
                            ),
                            BoxShadow(
                              color: activeColor.withValues(
                                alpha: state.isPlaying ? 0.35 : 0.16,
                              ),
                              blurRadius: state.isPlaying ? 48 : 28,
                              spreadRadius: state.isPlaying ? 2 : 0,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: AppRadii.circular(artRadius),
                          child: song != null
                              ? CachedArtwork(
                                  id: song.id,
                                  albumId: song.albumId,
                                  remoteUrl: song.remoteArtworkUrl ??
                                      song.artworkUri,
                                  type: ArtworkType.AUDIO,
                                  size: double.infinity,
                                  borderRadius: 0,
                                  highQuality: true,
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );

            final centerDisplay = isInSplitView
                ? artworkDisplay
                : AnimatedSwitcher(
                    duration: context.motionMs(320),
                    transitionBuilder: (child, anim) =>
                        playerOverlayTransitionBuilder(context, child, anim),
                    child: state.isLyricsVisible
                        ? LyricsView(
                            key: ValueKey(
                                'lyrics_${song?.id}_${song?.remoteId}'),
                            lyrics: state.lyrics,
                            isLoading: state.isLoadingLyrics,
                            activeColor: activeColor,
                            source: state.lyricsSource,
                            transparentBackground: true,
                          )
                        : state.isQueueVisible
                            ? const NowPlayingQueueView(
                                key: ValueKey('queue_view_milkdrop'),
                              )
                            : KeyedSubtree(
                                key: const ValueKey('stage_milkdrop'),
                                child: artworkDisplay,
                              ),
                  );

            // Milkdrop Pill Badge
            final milkdropBadge = Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s8,
                vertical: AppSpacing.s2,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: AppRadii.r12All,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.24),
                  width: 0.8,
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.blur_on_rounded, size: 12, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    'MILKDROP',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            );

            final controlsColumn = PlayerControlsColumn(
              props: props,
              isTablet: isTablet,
              isLandscape: isLandscape,
              isInSplitView: isInSplitView,
              heightRatio: metrics.heightRatio,
              metrics: metrics,
              trackHeader: PlayerTrackHeader(
                props: props,
                isTablet: isTablet,
                metrics: metrics,
                extraBadge: milkdropBadge,
              ),
              scaleMainButtonByHeight: true,
              dock: bottomDock,
            );

            // 1. Tablet Split-View Mode
            if (isInSplitView) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Column(
                  children: [
                    Expanded(child: artworkDisplay),
                    controlsColumn,
                  ],
                ),
              );
            }

            // 2. Landscape Mode
            if (isLandscape) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      flex: 5,
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: landscapeArtSize,
                            maxHeight: landscapeArtSize,
                          ),
                          child: centerDisplay,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      flex: 6,
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: EdgeInsets.only(
                                bottom: metrics.switcherBottomPad,
                              ),
                              child: viewSwitcher,
                            ),
                            controlsColumn,
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            // 3. Portrait Mode: Fallback to scrolling on very short screens
            final isVeryShort = constraints.maxHeight < 560;
            final isTrackView = !state.isLyricsVisible && !state.isQueueVisible;

            if (isVeryShort && isTrackView) {
              final double scrollSize =
                  (constraints.maxHeight * 0.40).clamp(180.0, 300.0);

              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    const PlayerPlayHandle(),
                    PlayerTopBar(props: props, isTablet: isTablet),
                    Padding(
                      padding: EdgeInsets.only(
                        top: switcherTopPad,
                        bottom: switcherBottomPad,
                      ),
                      child: viewSwitcher,
                    ),
                    Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: scrollSize,
                          maxHeight: scrollSize,
                        ),
                        child: centerDisplay,
                      ),
                    ),
                    SizedBox(
                      height: (isTablet ? 12.0 : 8.0) * metrics.heightRatio,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                      child: controlsColumn,
                    ),
                  ],
                ),
              );
            }

            // Standard Portrait
            final availableW = constraints.maxWidth - (isTablet ? 48.0 : 40.0);
            final availableH = constraints.maxHeight * 0.46;
            final artSize = math.min(availableW, availableH).clamp(180.0, 520.0);

            return SafeArea(
              top: true,
              bottom: true,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isTablet ? AppSpacing.xl : AppSpacing.md,
                ),
                child: Column(
                  children: [
                    const PlayerPlayHandle(),
                    PlayerTopBar(props: props, isTablet: isTablet),
                    Padding(
                      padding: EdgeInsets.only(
                        top: switcherTopPad,
                        bottom: switcherBottomPad,
                      ),
                      child: viewSwitcher,
                    ),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: artSize,
                            maxHeight: artSize,
                          ),
                          child: centerDisplay,
                        ),
                      ),
                    ),
                    SizedBox(height: metrics.spacingBelowDock * 0.3),
                    controlsColumn,
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
