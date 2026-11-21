// lib/features/player/presentation/themes/player_view_switcher.dart
import 'dart:math' as math;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';

import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/utils/pulsr_haptics.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../../settings/cubit/settings_state.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';

/// Readable foreground for a badge painted with an arbitrary (possibly
/// artwork-derived) accent, instead of assuming every accent is dark.
Color _readableOn(Color background) =>
    background.computeLuminance() > 0.179 ? AppColors.onBright : Colors.white;

/// Upgraded fluid overlay transition builder combining FadeTransition,
/// a subtle ScaleTransition (0.95 to 1.0), and a vertical SlideTransition
/// (Offset(0, 0.03) to Offset.zero) driven by context.motionMs(320) and
/// context.motionCurve(Curves.easeOutCubic).
Widget playerOverlayTransitionBuilder(
  BuildContext context,
  Widget child,
  Animation<double> animation,
) {
  if (!PulsrMotion.shouldAnimate(context)) {
    return child;
  }
  // CurveTween instead of CurvedAnimation: this builder runs for every
  // overlay switch, and a CurvedAnimation would register listeners on the
  // switcher's controller that are never removed.
  final curve = CurveTween(curve: context.motionCurve(Curves.easeOutCubic));
  return FadeTransition(
    opacity: animation.drive(curve),
    child: ScaleTransition(
      scale: animation.drive(
        Tween<double>(begin: 0.95, end: 1.0).chain(curve),
      ),
      child: SlideTransition(
        position: animation.drive(
          Tween<Offset>(
            begin: const Offset(0.0, 0.03),
            end: Offset.zero,
          ).chain(curve),
        ),
        child: child,
      ),
    ),
  );
}

/// One segment of the Track / Lyrics / Queue pill bar.
class PlayerSwitcherItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final Color activeColor;
  final int? badgeCount;
  final bool isTablet;
  final VoidCallback onTap;

  const PlayerSwitcherItem({
    super.key,
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.activeColor,
    this.badgeCount,
    this.isTablet = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final allowMotion = PulsrMotion.shouldAnimate(context);
    final semanticsLabel = (badgeCount != null && badgeCount! > 0)
        ? '$label ($badgeCount)'
        : label;
    return Semantics(
      button: true,
      selected: isSelected,
      label: semanticsLabel,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadii.r20All,
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: const BoxDecoration(
              color: Colors.transparent,
              borderRadius: AppRadii.r20All,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedScale(
                  scale: (isSelected && allowMotion) ? 1.08 : 1.0,
                  duration: context.motionMs(200),
                  curve: context.motionCurve(Curves.easeOutCubic),
                  child: Icon(
                    icon,
                    size: isTablet ? 15.0 : 13.5,
                    color: isSelected ? activeColor : p.textSecondary,
                  ),
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: AnimatedDefaultTextStyle(
                    duration: context.motionMs(200),
                    curve: context.motionCurve(Curves.easeOutCubic),
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize:
                          isTablet ? AppFontSize.bodySmall : AppFontSize.label,
                      fontWeight:
                          isSelected ? FontWeight.w800 : FontWeight.w600,
                      color: isSelected ? p.textPrimary : p.textSecondary,
                      letterSpacing: AppTracking.label,
                    ),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (badgeCount != null && badgeCount! > 0) ...[
                  const SizedBox(width: 5),
                  AnimatedContainer(
                    duration: context.motionMs(200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5.0,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? activeColor
                          : p.textPrimary.withValues(alpha: 0.12),
                      borderRadius: AppRadii.r8All,
                    ),
                    child: Text(
                      '$badgeCount',
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: AppFontSize.caption,
                        fontWeight: FontWeight.w800,
                        color: isSelected
                            ? _readableOn(activeColor)
                            : p.textSecondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Track / Lyrics / Queue pill bar.
class PlayerViewSwitcher extends StatelessWidget {
  final PlayerState state;
  final PlayerCubit cubit;
  final Color activeColor;
  final bool isTablet;
  final double barWidth;
  final double barHeight;

  /// The Track segment icon differs per theme (see [PlayerViewSwitcher] call
  /// sites): card uses layers, cassette radio, classic a note, the rest album.
  final IconData trackIcon;
  final double surfaceFillAlpha;
  final double borderAlpha;

  const PlayerViewSwitcher({
    super.key,
    required this.state,
    required this.cubit,
    required this.activeColor,
    required this.isTablet,
    required this.barWidth,
    required this.barHeight,
    this.trackIcon = Icons.album_rounded,
    this.surfaceFillAlpha = 0.06,
    this.borderAlpha = 0.12,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isLyrics = state.isLyricsVisible;
    final isQueue = state.isQueueVisible;
    final isTrack = !isLyrics && !isQueue;
    final l10n = context.l10n;
    // Custom Theme Studio shape controls apply when the user picked the custom
    // colour source, so preset themes keep their hand-tuned geometry.
    final custom =
        context.select<SettingsCubit, ({double radius, bool active})>((c) => (
              radius: c.state.customThemeRadius,
              active: c.state.themeColorSource == ThemeColorSource.custom,
            ));
    final barRadius = custom.active ? custom.radius : 20.0;
    final thumbRadius = math.max(4.0, barRadius - 3.0);
    final textScale =
        MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 2.0);
    final effectiveBarHeight =
        math.max(barHeight, (isTablet ? 28.0 : 24.0) * textScale + 12.0);

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: barWidth,
          minWidth: barWidth,
          maxHeight: effectiveBarHeight,
          minHeight: effectiveBarHeight,
        ),
        child: ClipRRect(
          borderRadius: AppRadii.circular(barRadius),
          child: RepaintBoundary(
            child: Container(
              padding: const EdgeInsets.all(3.0),
              decoration: BoxDecoration(
                color: Color.lerp(
                      p.surfaceContainer,
                      Colors.white,
                      p.isDark ? surfaceFillAlpha * 0.35 : 0.0,
                    ) ??
                    p.surfaceContainer,
                borderRadius: AppRadii.circular(barRadius),
                border: Border.all(
                  color:
                      p.isDark ? AppColors.specularAt(borderAlpha) : p.hairline,
                  width: 1.0,
                ),
                boxShadow: PulsrElevation.level1(context),
              ),
              child: Stack(
                children: [
                  AnimatedAlign(
                    duration: context.motionMs(260),
                    curve: context.motionCurve(Curves.easeOutCubic),
                    alignment: isTrack
                        ? const AlignmentDirectional(-1.0, 0.0)
                        : isLyrics
                            ? const AlignmentDirectional(0.0, 0.0)
                            : const AlignmentDirectional(1.0, 0.0),
                    child: FractionallySizedBox(
                      widthFactor: 1 / 3,
                      heightFactor: 1.0,
                      child: AnimatedContainer(
                        duration: context.motionMs(260),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              activeColor.withValues(
                                alpha: p.isDark ? 0.28 : 0.20,
                              ),
                              activeColor.withValues(
                                alpha: p.isDark ? 0.14 : 0.10,
                              ),
                            ],
                          ),
                          borderRadius: AppRadii.circular(thumbRadius),
                          border: Border.all(
                            color: activeColor.withValues(
                              alpha: p.isDark ? 0.55 : 0.45,
                            ),
                            width: 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: activeColor.withValues(alpha: 0.18),
                              blurRadius: 10,
                              spreadRadius: -2,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: PlayerSwitcherItem(
                          label: l10n.trackNumber,
                          icon: trackIcon,
                          isSelected: isTrack,
                          activeColor: activeColor,
                          isTablet: isTablet,
                          onTap: () {
                            if (!isTrack) {
                              PulsrHaptics.selectionClick();
                              cubit.resetOverlayViews();
                            }
                          },
                        ),
                      ),
                      Expanded(
                        child: PlayerSwitcherItem(
                          label: l10n.lyrics,
                          icon: Icons.lyrics_rounded,
                          isSelected: isLyrics,
                          activeColor: activeColor,
                          isTablet: isTablet,
                          onTap: () {
                            if (!isLyrics) {
                              PulsrHaptics.selectionClick();
                              cubit.toggleLyricsVisibility();
                            }
                          },
                        ),
                      ),
                      Expanded(
                        child: PlayerSwitcherItem(
                          label: l10n.queue,
                          icon: Icons.queue_music_rounded,
                          isSelected: isQueue,
                          badgeCount: state.queue.length,
                          activeColor: activeColor,
                          isTablet: isTablet,
                          onTap: () {
                            if (!isQueue) {
                              PulsrHaptics.selectionClick();
                              cubit.toggleQueueVisibility();
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
