// lib/features/player/presentation/themes/milkdrop_player_theme.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';

import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../../settings/cubit/settings_state.dart';
import '../widgets/audio_visualizer.dart';
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
      :themeMode,
    ) = context.select<
        SettingsCubit,
        ({
          NowPlayingDoubleTapAction nowPlayingDoubleTap,
          NowPlayingArtworkSwipeAction nowPlayingArtworkSwipe,
          AppThemeMode themeMode,
        })>((c) => (
          nowPlayingDoubleTap: c.state.nowPlayingDoubleTap,
          nowPlayingArtworkSwipe: c.state.nowPlayingArtworkSwipe,
          themeMode: c.state.themeMode,
        ));

    final artRadius = resolveCustomRadius(context, AppRadii.r28);
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

    return PlayerThemeScaffold(
      props: props,
      trackIcon: Icons.blur_on_rounded,
      dockIconStyle: PlayerDockIconStyle.classic,
      background: RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [topBg, bottomBg],
                ),
              ),
            ),
            AudioVisualizer(
              style: VisualizerStyle.milkdrop,
              color: Colors.white,
              transparentBackground: true,
              isPlaying: state.isPlaying,
              audioSessionId: state.audioSessionId,
              trackId: song?.id,
              trackPath: song?.path,
            ),
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
          ],
        ),
      ),
      stage: (context, metrics) => GestureDetector(
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
                        color: Colors.black.withValues(alpha: 0.45),
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
      ),
      chrome: (context, metrics) => PlayerControlsColumn(
        props: props,
        isTablet: metrics.isTablet,
        isLandscape: metrics.isLandscape,
        isInSplitView: PlayerSplitViewScope.of(context),
        heightRatio: metrics.heightRatio,
        metrics: metrics,
        trackHeader: PlayerTrackHeader(
          props: props,
          isTablet: metrics.isTablet,
          metrics: metrics,
          extraBadge: milkdropBadge,
        ),
        scaleMainButtonByHeight: true,
        dock: PlayerBottomActionDock(
          props: props,
          isTablet: metrics.isTablet,
          barWidth: metrics.pillBarWidth,
          barHeight: metrics.dockBarHeight,
          dockIconStyle: PlayerDockIconStyle.classic,
        ),
      ),
    );
  }
}
