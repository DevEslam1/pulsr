// lib/features/player/presentation/themes/milkdrop_player_theme.dart
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/widgets/cached_artwork.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../../settings/cubit/settings_state.dart';
import '../widgets/audio_visualizer.dart';
import '../widgets/player_gesture_scope.dart';
import 'player_shape.dart';
import 'player_theme.dart';
import 'player_theme_chrome.dart';
import 'player_theme_scaffold.dart';

/// Full-screen Milkdrop Player Theme.
///
/// Features:
/// 1. Audio-reactive visualizer spanning the entire screen behind the album
///    artwork and controls. The user's `VisualizerStyle` is honoured verbatim:
///    disabling visualizers leaves a static ambient gradient instead of forcing
///    the shader on (which used to defeat the setting and burn battery).
/// 2. Floating center album artwork stage with smooth elevation, a palette rim,
///    ambient drop shadow, and gesture interactions.
/// 3. Frosted scrims above and below the chrome, tinted for the active
///    brightness so the palette-driven text stays readable over bright shader
///    frames.
/// 4. Full phone landscape, tablet split-view, and compact height
///    responsiveness.
class MilkdropPlayerTheme extends StatelessWidget {
  final PlayerThemeProps props;

  const MilkdropPlayerTheme({super.key, required this.props});

  @override
  Widget build(BuildContext context) {
    final state = props.state;
    final activeColor = props.activeColor;
    final song = state.currentSong;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = context.palette;

    final themeMode =
        context.select<SettingsCubit, AppThemeMode>((c) => c.state.themeMode);
    final visualizerStyle = context.select<SettingsCubit, VisualizerStyle>(
      (c) => c.state.visualizerStyle,
    );

    final artRadius = resolveCustomRadius(context, AppRadii.r28);
    final isAmoled = themeMode == AppThemeMode.amoled;

    // AMOLED keeps the backdrop itself pure black so no unlit pixel is lit by
    // the background layer; the shader (or the static washes when visualizers
    // are off) and the scrims then draw on top of it.
    final Color topBg;
    final Color bottomBg;
    if (isAmoled) {
      topBg = Colors.black;
      bottomBg = Colors.black;
    } else if (isDark) {
      topBg = Color.alphaBlend(
        Colors.black.withValues(alpha: 0.40),
        props.bgColor,
      );
      bottomBg = Color.alphaBlend(
        Colors.black.withValues(alpha: 0.60),
        props.bgColor,
      );
    } else {
      topBg = props.bgColor;
      bottomBg = Color.alphaBlend(
        Colors.black.withValues(alpha: 0.06),
        props.bgColor,
      );
    }

    // `off` means off: no shader, no ticker, no per-frame GPU work. Every other
    // style renders as itself instead of being coerced into Milkdrop.
    final VisualizerStyle? effectiveStyle =
        visualizerStyle == VisualizerStyle.off ? null : visualizerStyle;

    // One shader colour for both brightnesses would be white-on-white in light
    // mode; ink waves keep the identity while the palette text stays legible.
    final Color visualizerColor = isDark ? Colors.white : p.textPrimary;

    // The chrome inherits palette text (white glyphs on dark, ink on light), so
    // the veil over the shader has to follow the same brightness. A black veil
    // only protected dark-mode chrome and left light mode unreadable over
    // mid-tone frames.
    final Color veil = isDark ? Colors.black : Colors.white;
    final double topVeilAlpha = isDark ? 0.45 : 0.55;
    final double bottomVeilAlpha = isDark ? 0.62 : 0.64;

    final milkdropBadge = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s2,
      ),
      decoration: BoxDecoration(
        color: p.isDark
            ? Colors.white.withValues(alpha: 0.15)
            : p.textPrimary.withValues(alpha: 0.06),
        borderRadius: AppRadii.r12All,
        border: Border.all(
          color: p.isDark
              ? Colors.white.withValues(alpha: 0.24)
              : p.hairline,
          width: 0.8,
        ),
      ),
      // Decorative brand mark: the label is a proper noun and deliberately kept
      // out of the semantics tree so screen readers reach the real controls.
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.blur_on_rounded, size: 12, color: p.textPrimary),
            const SizedBox(width: 4),
            Text(
              'MILKDROP',
              style: TextStyle(
                fontSize: AppFontSize.tiny,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: p.textPrimary,
              ),
            ),
          ],
        ),
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
            if (effectiveStyle == null)
              _MilkdropAmbientBackdrop(
                activeColor: activeColor,
                isDark: isDark,
              )
            else
              AudioVisualizer(
                style: effectiveStyle,
                color: visualizerColor,
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
                        veil.withValues(alpha: topVeilAlpha),
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
                        veil.withValues(alpha: bottomVeilAlpha),
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
      stage: (context, metrics) => PlayerGestureScope(
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
                    // A palette rim instead of white: it stays visible on the
                    // light deck and keeps the floating-stage edge readable.
                    border: Border.all(
                      color: p.textPrimary.withValues(
                        alpha: state.isPlaying ? 0.28 : 0.16,
                      ),
                      width: 1.4,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.45 : 0.28,
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
                    child: PlayerArtworkSemantics(
                      song: song,
                      child: song != null
                          ? CachedArtwork(
                              id: song.id,
                              albumId: song.albumId,
                              remoteUrl:
                                  song.remoteArtworkUrl ?? song.artworkUri,
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

/// Static stand-in for the shader when the user turned visualizers off.
///
/// Two accent washes keep the full-bleed identity of the theme without a
/// fragment program, a ticker, or a single animated frame — the only honest
/// reading of "visualizers off".
class _MilkdropAmbientBackdrop extends StatelessWidget {
  final Color activeColor;
  final bool isDark;

  const _MilkdropAmbientBackdrop({
    required this.activeColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.7),
              radius: 1.1,
              colors: [
                activeColor.withValues(alpha: isDark ? 0.32 : 0.22),
                activeColor.withValues(alpha: 0),
              ],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, 0.9),
              radius: 1.0,
              colors: [
                activeColor.withValues(alpha: isDark ? 0.18 : 0.12),
                activeColor.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
