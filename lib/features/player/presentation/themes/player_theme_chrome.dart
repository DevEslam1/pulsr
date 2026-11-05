// lib/features/player/presentation/themes/player_theme_chrome.dart
//
// Shared chrome for the eight now-playing themes (A-13). The view-switcher
// pill, the bottom action dock, the switcher item, the animated favourite
// button and the dock icon button were previously copy-pasted into every theme
// file. They now live here; themes parameterise the handful of visual tokens
// they actually differ on instead of keeping private copies.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/services/sound_feedback_service.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/utils/pulsr_haptics.dart';
import '../../../../core/widgets/marquee_text.dart';
import '../../../../core/widgets/waveform_logo.dart';
import '../../../../data/db/app_database.dart';
import '../../../../data/party/listen_together_service.dart';
import '../../../../data/party/party_models.dart';
import '../../../../data/services/cast_service.dart';
import '../../../../domain/models/audio_output_info.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../../settings/cubit/settings_state.dart';
import '../../../sheets/add_to_playlist_sheet.dart';
import '../../../sheets/sleep_timer_sheet.dart';
import '../../../sheets/song_options_sheet.dart';
import '../../../ytm_search/presentation/widgets/ytm_download_button.dart';
import '../../cubit/player_cubit.dart';
import '../../../../core/services/ambient_sound_service.dart';
import '../../cubit/player_state.dart';
import '../widgets/ambient_sound_sheet.dart';
import '../widgets/audio_quality_badge.dart';
import '../widgets/audio_quality_sheet.dart';
import '../widgets/equalizer_sheet.dart';
import '../widgets/player_controls.dart';
import '../widgets/player_more_sheet.dart';
import '../widgets/player_seek_bar.dart';
import '../widgets/player_volume_bar.dart';
import '../widgets/quran_mode_sheet.dart';
import '../widgets/speed_picker_sheet.dart';
import 'player_theme.dart';
import 'player_theme_scaffold.dart' show PlayerThemeMetrics;

/// Readable foreground for a badge painted with an arbitrary (possibly
/// artwork-derived) accent, instead of assuming every accent is dark.
Color _readableOn(Color background) =>
    background.computeLuminance() > 0.179 ? AppColors.onBright : Colors.white;

/// Human-readable remaining sleep-timer time: seconds below a minute, whole
/// minutes below an hour, then `h`/`m` so a 90-minute timer never reads "90m".
String formatSleepTimerRemaining(Duration remaining) {
  final r = remaining.isNegative ? Duration.zero : remaining;
  if (r.inSeconds < 60) return '${r.inSeconds}s';
  if (r.inMinutes < 60) return '${r.inMinutes}m';
  final hours = r.inHours;
  final minutes = r.inMinutes.remainder(60);
  return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}m';
}

/// Upgraded fluid overlay transition builder combining FadeTransition,
/// a subtle ScaleTransition (0.95 to 1.0), and a vertical SlideTransition
/// (Offset(0, 0.03) to Offset.zero) driven by context.motionMs(320) and
/// context.motionCurve(Curves.easeOutCubic).
Widget playerOverlayTransitionBuilder(
  BuildContext context,
  Widget child,
  Animation<double> animation,
) {
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

/// Visual tokens that differ between the copies of the dock icon button.
///
/// All eight themes build the same button; classic is the one that had already
/// diverged (active border, larger phone icon, tooltip inside the InkWell,
/// different badge metrics). Both variants are preserved exactly.
class PlayerDockIconStyle {
  final double inkWellRadius;

  /// true: `Tooltip` wraps the `InkWell` (card, cassette, circle, lyrics,
  /// minimal, vinyl, waveform). false: `InkWell` wraps the `Tooltip` (classic).
  final bool tooltipOutside;

  /// Padding on phone-sized layouts; tablets always use 8.
  final double phonePadding;
  final double activeFillAlpha;
  final bool activeBorder;
  final double phoneIconSize;
  final double badgeRight;
  final double badgeHPadding;
  final double badgeRadius;
  final bool badgeShadow;
  final double badgeFontSize;

  const PlayerDockIconStyle({
    required this.inkWellRadius,
    required this.tooltipOutside,
    required this.phonePadding,
    required this.activeFillAlpha,
    required this.activeBorder,
    required this.phoneIconSize,
    required this.badgeRight,
    required this.badgeHPadding,
    required this.badgeRadius,
    required this.badgeShadow,
    required this.badgeFontSize,
  });

  double paddingFor(bool isTablet) => isTablet ? 8 : phonePadding;
  double iconSizeFor(bool isTablet) => isTablet ? 22 : phoneIconSize;

  static const PlayerDockIconStyle common = PlayerDockIconStyle(
    inkWellRadius: 18,
    tooltipOutside: true,
    phonePadding: 8,
    activeFillAlpha: 0.18,
    activeBorder: false,
    phoneIconSize: 19,
    badgeRight: -6,
    badgeHPadding: 3.5,
    badgeRadius: 6,
    badgeShadow: false,
    badgeFontSize: 8,
  );

  static const PlayerDockIconStyle classic = PlayerDockIconStyle(
    inkWellRadius: 20,
    tooltipOutside: false,
    phonePadding: 6,
    activeFillAlpha: 0.22,
    activeBorder: true,
    phoneIconSize: 20,
    badgeRight: -4,
    badgeHPadding: 4,
    badgeRadius: 8,
    badgeShadow: true,
    badgeFontSize: 8.5,
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
                  scale: isSelected ? 1.08 : 1.0,
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
                      fontSize: isTablet ? 13.0 : 11.8,
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
                      style: TextStyle(
                        fontSize: isTablet ? 10.5 : 9.5,
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

/// Heart button with the scale animation shared by every theme.
class PlayerAnimatedFavoriteButton extends StatelessWidget {
  final bool isFavorite;
  final Color favoriteColor;
  final Color inactiveColor;
  final double iconSize;
  final String semanticLabel;
  final VoidCallback onTap;

  const PlayerAnimatedFavoriteButton({
    super.key,
    required this.isFavorite,
    required this.favoriteColor,
    required this.inactiveColor,
    this.iconSize = 24,
    required this.semanticLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        child: InkWell(
          onTap: () {
            PulsrHaptics.confirm();
            SoundFeedbackService.playClick();
            onTap();
          },
          child: Center(
            child: AnimatedSwitcher(
              duration: context.motionMs(280),
              transitionBuilder: (child, anim) {
                final isHeart = (child.key as ValueKey<bool>?)?.value == true;
                final curve =
                    isHeart ? Curves.easeOutBack : Curves.easeOutCubic;
                return ScaleTransition(
                  scale: anim.drive(
                    CurveTween(curve: context.motionCurve(curve)),
                  ),
                  child: child,
                );
              },
              child: Icon(
                isFavorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                key: ValueKey(isFavorite),
                color: isFavorite ? favoriteColor : inactiveColor,
                size: iconSize,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Circular action button used inside the bottom action dock with press-scale
/// feedback and refined top-right cutout-bordered badge.
class PlayerDockIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final bool isActive;
  final Color activeColor;
  final Color inactiveColor;
  final String? badgeText;
  final bool isTablet;
  final PlayerDockIconStyle style;
  final VoidCallback onTap;

  const PlayerDockIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.isActive,
    required this.activeColor,
    required this.inactiveColor,
    this.badgeText,
    this.isTablet = false,
    this.style = PlayerDockIconStyle.common,
    required this.onTap,
  });

  @override
  State<PlayerDockIconButton> createState() => _PlayerDockIconButtonState();
}

class _PlayerDockIconButtonState extends State<PlayerDockIconButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final isTablet = widget.isTablet;
    final isActive = widget.isActive;
    final activeColor = widget.activeColor;
    final inactiveColor = widget.inactiveColor;
    final badgeText = widget.badgeText;
    final p = context.palette;

    final inner = Center(
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          AnimatedContainer(
            duration: context.motionMs(200),
            padding: EdgeInsets.all(style.paddingFor(isTablet)),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: isActive
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        activeColor.withValues(
                          alpha: (style.activeFillAlpha + 0.06).clamp(0.0, 1.0),
                        ),
                        activeColor.withValues(
                          alpha: (style.activeFillAlpha * 0.65).clamp(0.0, 1.0),
                        ),
                      ],
                    )
                  : null,
              border: isActive
                  ? Border.all(
                      color: activeColor.withValues(
                        alpha: style.activeBorder ? 0.52 : 0.36,
                      ),
                      width: style.activeBorder ? 1.2 : 1.0,
                    )
                  : null,
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: activeColor.withValues(alpha: 0.24),
                        blurRadius: 10,
                        spreadRadius: -2,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              widget.icon,
              size: style.iconSizeFor(isTablet),
              color: isActive ? activeColor : inactiveColor,
            ),
          ),
          if (badgeText != null && badgeText.isNotEmpty)
            PositionedDirectional(
              top: -3,
              end: style.badgeRight,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: style.badgeHPadding,
                  vertical: 1.5,
                ),
                decoration: BoxDecoration(
                  color: activeColor,
                  borderRadius: AppRadii.circular(style.badgeRadius),
                  border: Border.all(
                    color: p.surface,
                    width: 1.5,
                  ),
                  boxShadow: style.badgeShadow
                      ? [
                          BoxShadow(
                            color: AppColors.scrimAt(0.32),
                            blurRadius: 4,
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    color: _readableOn(activeColor),
                    fontSize: style.badgeFontSize,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    final Widget buttonContent = AnimatedScale(
      scale: _isPressed ? 0.88 : 1.0,
      duration: context.motionMs(120),
      curve: context.motionCurve(Curves.easeOutCubic),
      child: inner,
    );

    // Preserve the original widget nesting order per variant: the classic copy
    // put the tooltip inside the InkWell, the common copy put it outside.
    final Widget body;
    if (style.tooltipOutside) {
      body = Tooltip(
        message: widget.tooltip,
        excludeFromSemantics: true,
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (highlighted) {
            setState(() => _isPressed = highlighted);
          },
          borderRadius: AppRadii.circular(style.inkWellRadius),
          child: buttonContent,
        ),
      );
    } else {
      body = InkWell(
        onTap: widget.onTap,
        onHighlightChanged: (highlighted) {
          setState(() => _isPressed = highlighted);
        },
        borderRadius: AppRadii.circular(style.inkWellRadius),
        child: Tooltip(
          message: widget.tooltip,
          excludeFromSemantics: true,
          child: buttonContent,
        ),
      );
    }

    return Semantics(
      button: true,
      label: widget.tooltip,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: 48,
          minHeight: 48,
        ),
        child: body,
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

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: barWidth,
          minWidth: barWidth,
          maxHeight: barHeight,
          minHeight: barHeight,
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
                  color: p.isDark
                      ? AppColors.specularAt(borderAlpha)
                      : p.hairline,
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
                              HapticFeedback.selectionClick();
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
                              HapticFeedback.selectionClick();
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
                              HapticFeedback.selectionClick();
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

/// Floating glass bottom action dock (EQ / output / speed / timer / Quran /
/// add-to-playlist).
class PlayerBottomActionDock extends StatelessWidget {
  final PlayerThemeProps props;
  final SettingsState? settingsState;
  final bool isTablet;
  final double barWidth;
  final double barHeight;
  final PlayerDockIconStyle dockIconStyle;
  final bool disableBlur;

  const PlayerBottomActionDock({
    super.key,
    required this.props,
    this.settingsState,
    required this.isTablet,
    required this.barWidth,
    required this.barHeight,
    this.dockIconStyle = PlayerDockIconStyle.common,
    this.disableBlur = false,
  });

  @override
  Widget build(BuildContext context) {
    final song = props.state.currentSong;
    final p = context.palette;
    final l10n = context.l10n;
    final outputDevice = settingsState?.currentOutputDevice ??
        context.select<SettingsCubit, AudioOutputInfo?>(
            (c) => c.state.currentOutputDevice);
    final isUsb = outputDevice?.isUsbDac == true;
    final isCast = CastService().sessionStatus.connected;
    final isEqActive = props.state.isEqEnabled;
    final speed = props.state.playbackSpeed;
    int? remainingTracks;
    try {
      remainingTracks = props.state.sleepTimerRemainingTracks ??
          props.cubit.sleepTimerRemainingTracks;
    } catch (_) {
      remainingTracks = props.state.sleepTimerRemainingTracks;
    }
    bool isEndQ = false;
    try {
      isEndQ = props.cubit.isEndOfQueueSleepTimer == true;
    } catch (_) {
      isEndQ = false;
    }
    final hasTimer = props.state.sleepTimerRemaining != null ||
        remainingTracks != null ||
        isEndQ;
    final custom = context
        .select<SettingsCubit, ({double radius, bool glow, bool active})>(
            (c) => (
                  radius: c.state.customThemeRadius,
                  glow: c.state.customThemeGlow,
                  active: c.state.themeColorSource == ThemeColorSource.custom,
                ));
    final barRadius = custom.active ? custom.radius : 24.0;
    final showCustomGlow = custom.active && custom.glow;

    final IconData outputIcon = isCast
        ? Icons.cast_connected_rounded
        : (isUsb
            ? Icons.usb_rounded
            : (outputDevice?.deviceName.contains('Bluetooth') == true ||
                    outputDevice?.deviceName.contains('A2DP') == true
                ? Icons.bluetooth_audio_rounded
                : (outputDevice?.deviceName.contains('Speaker') == true
                    ? Icons.speaker_rounded
                    : Icons.headphones_rounded)));

    final isInSplit = PlayerSplitViewScope.of(context);
    final double effectiveBarWidth = isInSplit
        ? math.min(
            barWidth,
            MediaQuery.sizeOf(context).width * 0.42,
          )
        : math.max(
            barWidth,
            math.min(
              MediaQuery.sizeOf(context).width - (isTablet ? 64.0 : 20.0),
              isTablet ? 480.0 : 364.0,
            ),
          );

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: effectiveBarWidth,
          minWidth: effectiveBarWidth,
          maxHeight: barHeight,
          minHeight: barHeight,
        ),
        child: ClipRRect(
          borderRadius: AppRadii.circular(barRadius),
          child: RepaintBoundary(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 3.0),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.lerp(
                          p.surfaceContainer,
                          Colors.white,
                          p.isDark ? 0.03 : 0.0,
                        ) ??
                        p.surfaceContainer,
                    p.surfaceContainer,
                  ],
                ),
                borderRadius: AppRadii.circular(barRadius),
                border: Border.all(
                  color: showCustomGlow
                      ? props.activeColor.withValues(alpha: 0.42)
                      : (p.isDark ? AppColors.specularAt(0.12) : p.hairline),
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black
                        .withValues(alpha: p.isDark ? 0.28 : 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                  if (showCustomGlow)
                    BoxShadow(
                      color: props.activeColor.withValues(alpha: 0.20),
                      blurRadius: 18,
                      spreadRadius: -2,
                    ),
                ],
              ),
              child: Row(
                children: [
                  // 1. Equalizer & DSP
                  Expanded(
                    child: PlayerDockIconButton(
                      icon: Icons.tune_rounded,
                      tooltip: l10n.equalizer,
                      isActive: isEqActive,
                      activeColor: props.activeColor,
                      inactiveColor: p.textSecondary,
                      isTablet: isTablet,
                      style: dockIconStyle,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        EqualizerSheet.show(context);
                      },
                    ),
                  ),

                  // 2. Audio Output & DAC
                  Expanded(
                    child: PlayerDockIconButton(
                      icon: outputIcon,
                      tooltip: isCast ? 'Google Cast' : l10n.audioOutputAndDac,
                      badgeText: isCast ? 'CAST' : (isUsb ? 'DAC' : null),
                      isActive: isCast || isUsb,
                      activeColor:
                          isCast ? AppColors.accentCyan : AppColors.dacGold,
                      inactiveColor: p.textSecondary,
                      isTablet: isTablet,
                      style: dockIconStyle,
                      onTap: () {
                        if (song != null) {
                          HapticFeedback.lightImpact();
                          AudioQualitySheet.show(
                              context, song, props.activeColor);
                        }
                      },
                    ),
                  ),

                  // 3. Playback Speed
                  Expanded(
                    child: PlayerDockIconButton(
                      icon: Icons.speed_rounded,
                      tooltip: l10n.playbackSpeed,
                      badgeText:
                          speed != 1.0 ? '${speed.toStringAsFixed(1)}x' : null,
                      isActive: speed != 1.0,
                      activeColor: props.activeColor,
                      inactiveColor: p.textSecondary,
                      isTablet: isTablet,
                      style: dockIconStyle,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        SpeedPickerSheet.show(context);
                      },
                    ),
                  ),

                  // 4. Quran Mode
                  Expanded(
                    child: PlayerDockIconButton(
                      icon: Icons.auto_stories_rounded,
                      tooltip: l10n.quranMode,
                      isActive: props.state.isQuranModeEnabled,
                      activeColor: AppColors.quranEmerald,
                      inactiveColor: p.textSecondary,
                      isTablet: isTablet,
                      style: dockIconStyle,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        QuranModeSheet.show(context);
                      },
                    ),
                  ),

                  // 5. Ambient Sounds (Rain logo)
                  Expanded(
                    child: AnimatedBuilder(
                      animation: AmbientSoundService(),
                      builder: (context, _) {
                        final ambient = AmbientSoundService();
                        final isAmbientActive = ambient.isEnabled;
                        return PlayerDockIconButton(
                          icon: Icons.water_drop_rounded,
                          tooltip: l10n.ambientSounds,
                          isActive: isAmbientActive,
                          activeColor: props.activeColor,
                          inactiveColor: p.textSecondary,
                          isTablet: isTablet,
                          style: dockIconStyle,
                          onTap: () {
                            HapticFeedback.lightImpact();
                            AmbientSoundSheet.show(context);
                          },
                        );
                      },
                    ),
                  ),

                  // 6. Sleep Timer
                  Expanded(
                    child: PlayerDockIconButton(
                      icon: Icons.timer_outlined,
                      tooltip: isEndQ
                          ? 'Sleep Timer: End of Queue'
                          : (remainingTracks != null
                              ? 'Sleep Timer: $remainingTracks tracks remaining'
                              : (props.state.sleepTimerRemaining != null
                                  ? 'Sleep Timer: ${formatSleepTimerRemaining(props.state.sleepTimerRemaining!)} remaining'
                                  : l10n.sleepTimer)),
                      badgeText: hasTimer
                          ? (remainingTracks != null
                              ? '$remainingTracks tr'
                              : (isEndQ
                                  ? 'End'
                                  : (props.state.sleepTimerRemaining != null
                                      ? formatSleepTimerRemaining(
                                          props.state.sleepTimerRemaining!)
                                      : '')))
                          : null,
                      isActive: hasTimer,
                      activeColor: props.activeColor,
                      inactiveColor: p.textSecondary,
                      isTablet: isTablet,
                      style: dockIconStyle,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        SleepTimerSheet.show(context);
                      },
                    ),
                  ),

                  // 7. Secondary actions (party / canvas / playlist)
                  Expanded(
                    child: _MoreDockButton(
                      song: song,
                      activeColor: props.activeColor,
                      inactiveColor: p.textSecondary,
                      isTablet: isTablet,
                      style: dockIconStyle,
                    ),
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

/// Reactive "More" dock button. Keeps live party state and Quran mode visible
/// without spending three permanent slots in the transport dock.
class _MoreDockButton extends StatelessWidget {
  final SongsTableData? song;
  final Color activeColor;
  final Color inactiveColor;
  final bool isTablet;
  final PlayerDockIconStyle style;

  const _MoreDockButton({
    required this.song,
    required this.activeColor,
    required this.inactiveColor,
    required this.isTablet,
    required this.style,
  });

  void _open(BuildContext context) {
    HapticFeedback.lightImpact();
    PlayerMoreSheet.show(context, song: song, activeColor: activeColor);
  }

  Widget _button(
    BuildContext context, {
    required bool active,
    String? badge,
  }) {
    return PlayerDockIconButton(
      icon: Icons.apps_rounded,
      tooltip: context.l10n.moreOptions,
      isActive: active,
      badgeText: badge,
      activeColor: activeColor,
      inactiveColor: inactiveColor,
      isTablet: isTablet,
      style: style,
      onTap: () => _open(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isQuranMode = context.select<PlayerCubit, bool>(
      (c) => c.state.isQuranModeEnabled,
    );

    ListenTogetherService? resolved;
    try {
      if (getIt.isRegistered<ListenTogetherService>()) {
        resolved = getIt<ListenTogetherService>();
      }
    } catch (_) {
      resolved = null;
    }
    final partyService = resolved;
    if (partyService == null) {
      return _button(context, active: isQuranMode);
    }

    return ValueListenableBuilder<PartyConnectionState>(
      valueListenable: partyService.connectionState,
      builder: (context, connState, _) {
        return ValueListenableBuilder<PartySnapshot?>(
          valueListenable: partyService.partySnapshot,
          builder: (context, snapshot, _) {
            final isLive = connState == PartyConnectionState.live;
            final isConnecting = connState == PartyConnectionState.connecting;
            final count = snapshot?.members.length ?? 0;
            final badge = isLive
                ? (count > 1 ? '$count' : 'LIVE')
                : (isConnecting ? '...' : null);

            return _button(
              context,
              active: isLive || isConnecting || isQuranMode,
              badge: badge,
            );
          },
        );
      },
    );
  }
}

/// Pull-down grab handle shown above the player top bar.
class PlayerPlayHandle extends StatelessWidget {
  final EdgeInsetsGeometry padding;

  const PlayerPlayHandle({
    super.key,
    this.padding =
        const EdgeInsets.only(top: AppSpacing.xxs, bottom: AppSpacing.s2),
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: padding,
      child: Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: (p.isDark ? Colors.white : Colors.black)
                .withValues(alpha: 0.24),
            borderRadius: AppRadii.r2All,
          ),
        ),
      ),
    );
  }
}

/// Symmetrical top bar: dismiss control, centred "PLAYING FROM" header and the
/// song-info action. Card overrides the title/subtitle colours; classic uses a
/// slightly taller vertical inset.
class PlayerTopBar extends StatelessWidget {
  final PlayerThemeProps props;
  final bool isTablet;
  final Color? titleColor;
  final Color? subtitleColor;
  final double horizontalPadding;
  final double tabletHorizontalPadding;
  final double verticalPadding;
  final VoidCallback? onDismiss;
  final VoidCallback? onMore;
  final Widget? centerWidget;
  final bool showDismiss;
  final bool showMore;

  const PlayerTopBar({
    super.key,
    required this.props,
    required this.isTablet,
    this.titleColor,
    this.subtitleColor,
    this.horizontalPadding = 20,
    this.tabletHorizontalPadding = 28,
    this.verticalPadding = AppSpacing.s2,
    this.onDismiss,
    this.onMore,
    this.centerWidget,
    this.showDismiss = true,
    this.showMore = true,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = props.state;
    final song = state.currentSong;
    final resolvedTitle = titleColor ?? p.textPrimary;
    final resolvedSubtitle = subtitleColor ?? p.textSecondary;

    Widget circleButton({
      required IconData icon,
      required String semanticLabel,
      required double iconSize,
      required VoidCallback onTap,
    }) {
      return SizedBox(
        width: 46,
        height: 46,
        child: Material(
          color: p.isDark ? AppColors.specularAt(0.08) : p.surfaceContainer,
          shape: CircleBorder(
            side: BorderSide(
              color: p.isDark ? AppColors.specularAt(0.14) : p.hairline,
              width: 1.0,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Center(
              child: Icon(
                icon,
                semanticLabel: semanticLabel,
                size: iconSize,
                color: resolvedTitle,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isTablet ? tabletHorizontalPadding : horizontalPadding,
        vertical: verticalPadding,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (showDismiss)
            circleButton(
              icon: Icons.keyboard_arrow_down_rounded,
              semanticLabel: context.l10n.close,
              iconSize: isTablet ? 26 : 24,
              onTap: () {
                HapticFeedback.lightImpact();
                if (onDismiss != null) {
                  onDismiss!();
                } else if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/');
                }
              },
            )
          else if (showMore)
            const SizedBox(width: 46, height: 46),
          Expanded(
            child: centerWidget != null
                ? Center(child: centerWidget!)
                : Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: p.isDark
                                ? AppColors.specularAt(0.05)
                                : p.surfaceContainer.withValues(alpha: 0.6),
                            borderRadius: AppRadii.r12All,
                            border: Border.all(
                              color: p.isDark
                                  ? AppColors.specularAt(0.09)
                                  : p.hairline,
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              WaveformLogo(
                                size: 12,
                                color: state.isPlaying
                                    ? props.activeColor
                                    : resolvedSubtitle,
                                animate: state.isPlaying,
                              ),
                              const SizedBox(width: AppSpacing.s6),
                              Flexible(
                                child: Text(
                                  context.l10n.playingFrom.toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        fontSize: AppFontSize.tiny,
                                        letterSpacing: AppTracking.wide,
                                        fontWeight: FontWeight.w800,
                                        color: resolvedSubtitle.withValues(
                                          alpha: p.isDark ? 0.85 : 1.0,
                                        ),
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          (song?.album != null && song!.album.trim().isNotEmpty)
                              ? song.album.trim()
                              : (song?.artist != null &&
                                      song!.artist.trim().isNotEmpty)
                                  ? song.artist.trim()
                                  : context.l10n.navLibrary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    fontSize: isTablet
                                        ? AppFontSize.body
                                        : AppFontSize.bodySmall,
                                    color: resolvedTitle,
                                  ),
                        ),
                      ],
                    ),
                  ),
          ),
          if (showMore)
            circleButton(
              icon: Icons.more_horiz_rounded,
              semanticLabel: context.l10n.moreOptions,
              iconSize: isTablet ? 24 : 22,
              onTap: () {
                HapticFeedback.lightImpact();
                if (onMore != null) {
                  onMore!();
                } else if (song != null) {
                  SongOptionsSheet.show(context, song: song);
                }
              },
            )
          else if (showDismiss)
            const SizedBox(width: 46, height: 46),
        ],
      ),
    );
  }
}

/// Track header: [download / add-to-playlist] title + artist [favourite],
/// followed by the audio-quality badge (and an optional extra badge chip).
class PlayerTrackHeader extends StatelessWidget {
  final PlayerThemeProps props;
  final bool isTablet;
  final double horizontalPadding;
  final double tabletHorizontalPadding;
  final double? verticalPadding;
  final Color? titleColor;
  final Color? subtitleColor;
  final Widget? extraBadge;
  final double badgeGap;
  final double titleArtistGap;
  final bool showQualityBadge;
  final double? titleFontSize;
  final double? subtitleFontSize;
  final double? actionButtonSize;
  final PlayerThemeMetrics? metrics;

  /// Left-aligns title/artist instead of centering them. Minimal uses this to
  /// read as a typographic layout rather than a re-skinned Classic.
  final bool alignStart;

  const PlayerTrackHeader({
    super.key,
    required this.props,
    required this.isTablet,
    this.horizontalPadding = 16,
    this.tabletHorizontalPadding = 28,
    this.verticalPadding,
    this.titleColor,
    this.subtitleColor,
    this.extraBadge,
    this.badgeGap = AppSpacing.s8,
    this.titleArtistGap = AppSpacing.xs,
    this.showQualityBadge = true,
    this.titleFontSize,
    this.subtitleFontSize,
    this.actionButtonSize,
    this.metrics,
    this.alignStart = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveAlignStart = alignStart || PlayerSplitViewScope.of(context);
    final p = context.palette;
    final state = props.state;
    final song = state.currentSong;
    final isFav = song?.isFavorite == true;
    final resolvedTitle = titleColor ?? p.textPrimary;
    final resolvedSubtitle = subtitleColor ?? p.textSecondary;
    final hasDownload = song != null &&
        (song.source == SongSource.youtube ||
            (song.remoteId != null && song.remoteId!.isNotEmpty));

    final double effectiveVerticalPadding =
        verticalPadding ?? metrics?.trackHeaderVerticalPadding ?? AppSpacing.s6;
    final double resolvedTitleFontSize = titleFontSize ??
        metrics?.titleFontSize ??
        (isTablet ? AppFontSize.headline : AppFontSize.title);
    final double resolvedSubtitleFontSize = subtitleFontSize ??
        metrics?.artistFontSize ??
        (isTablet ? AppFontSize.callout : AppFontSize.bodySmall);
    final double resolvedActionButtonSize = actionButtonSize ??
        metrics?.actionButtonSize ??
        (isTablet ? 48.0 : 44.0);
    final double iconSize =
        isTablet ? 24.0 : (resolvedActionButtonSize < 42.0 ? 18.0 : 20.0);

    final qualityBadge = song == null
        ? null
        : AudioQualityBadge(
            song: song,
            activeColor: props.activeColor,
            compact: true,
            showDevice: false,
          );

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isTablet ? tabletHorizontalPadding : horizontalPadding,
        vertical: effectiveVerticalPadding,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Minimal distils the header: add-to-playlist lives in the More
              // sheet, so the title can start at the screen gutter.
              if (!effectiveAlignStart)
                SizedBox(
                  width: resolvedActionButtonSize,
                  height: resolvedActionButtonSize,
                  child: Material(
                    color: p.isDark
                        ? AppColors.specularAt(0.07)
                        : p.surfaceContainer,
                    shape: CircleBorder(
                      side: BorderSide(
                        color:
                            p.isDark ? AppColors.specularAt(0.13) : p.hairline,
                        width: 1.0,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: hasDownload
                        ? Center(
                            child: YtmDownloadButton(
                              song: song,
                              activeColor: props.activeColor,
                              iconColor: resolvedSubtitle,
                              iconSize: iconSize,
                            ),
                          )
                        : InkWell(
                            onTap: () {
                              if (song != null) {
                                HapticFeedback.lightImpact();
                                AddToPlaylistSheet.show(context, song: song);
                              }
                            },
                            child: Center(
                              child: Icon(
                                Icons.playlist_add_rounded,
                                semanticLabel: context.l10n.addToPlaylist,
                                size: iconSize,
                                color: resolvedSubtitle,
                              ),
                            ),
                          ),
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: EdgeInsetsDirectional.only(
                    start: effectiveAlignStart ? 0 : AppSpacing.s10,
                    end: AppSpacing.s10,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: effectiveAlignStart
                        ? CrossAxisAlignment.start
                        : CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: MarqueeText(
                          text: song?.title ?? context.l10n.noTrackSelected,
                          textAlign: effectiveAlignStart
                              ? TextAlign.start
                              : TextAlign.center,
                          style: TextStyle(
                            fontSize: resolvedTitleFontSize,
                            fontWeight: FontWeight.w900,
                            color: resolvedTitle,
                            height: 1.22,
                            letterSpacing: AppTracking.title,
                          ),
                        ),
                      ),
                      SizedBox(height: titleArtistGap),
                      SizedBox(
                        width: double.infinity,
                        child: MarqueeText(
                          text: song?.artist ?? context.l10n.unknownArtist,
                          textAlign: effectiveAlignStart
                              ? TextAlign.start
                              : TextAlign.center,
                          style: TextStyle(
                            fontSize: resolvedSubtitleFontSize,
                            fontWeight: FontWeight.w600,
                            color: resolvedSubtitle,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedContainer(
                duration: context.motionMs(220),
                width: resolvedActionButtonSize,
                height: resolvedActionButtonSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isFav
                      ? p.favorite.withValues(alpha: p.isDark ? 0.16 : 0.12)
                      : (p.isDark
                          ? AppColors.specularAt(0.07)
                          : p.surfaceContainer),
                  border: Border.all(
                    color: isFav
                        ? p.favorite.withValues(alpha: 0.45)
                        : (p.isDark ? AppColors.specularAt(0.13) : p.hairline),
                    width: 1.0,
                  ),
                  boxShadow: isFav
                      ? [
                          BoxShadow(
                            color: p.favorite.withValues(alpha: 0.20),
                            blurRadius: 10,
                            spreadRadius: -2,
                          ),
                        ]
                      : null,
                ),
                clipBehavior: Clip.antiAlias,
                child: Material(
                  color: Colors.transparent,
                  child: PlayerAnimatedFavoriteButton(
                    isFavorite: isFav,
                    semanticLabel:
                        isFav ? context.l10n.unlike : context.l10n.like,
                    favoriteColor: p.favorite,
                    inactiveColor: resolvedSubtitle,
                    iconSize: iconSize,
                    onTap: () {
                      if (song != null) {
                        props.cubit.toggleFavorite(song.id);
                      }
                    },
                  ),
                ),
              ),
              if (effectiveAlignStart) ...[
                const SizedBox(width: AppSpacing.s6),
                SizedBox(
                  width: resolvedActionButtonSize,
                  height: resolvedActionButtonSize,
                  child: Material(
                    color: p.isDark
                        ? AppColors.specularAt(0.07)
                        : p.surfaceContainer,
                    shape: CircleBorder(
                      side: BorderSide(
                        color: p.isDark
                            ? AppColors.specularAt(0.13)
                            : p.hairline,
                        width: 1.0,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        PlayerMoreSheet.show(context,
                            song: song, activeColor: props.activeColor);
                      },
                      child: Center(
                        child: Icon(
                          Icons.more_horiz_rounded,
                          size: iconSize,
                          color: resolvedSubtitle,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (showQualityBadge && qualityBadge != null) ...[
            SizedBox(height: badgeGap),
            Align(
              alignment: effectiveAlignStart
                  ? AlignmentDirectional.centerStart
                  : AlignmentDirectional.center,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    qualityBadge,
                    if (extraBadge != null) ...[
                      const SizedBox(width: AppSpacing.xs),
                      extraBadge!,
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shared studio-styled bookmark resume prompt banner used by both
/// [PlayerControlsColumn] and [PlayerThemeScaffold].
class PlayerBookmarkPromptBanner extends StatelessWidget {
  final PlayerCubit cubit;
  final Duration position;

  const PlayerBookmarkPromptBanner({
    super.key,
    required this.cubit,
    required this.position,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xxs,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm + 2,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              p.warning.withValues(alpha: p.isDark ? 0.20 : 0.14),
              p.warning.withValues(alpha: p.isDark ? 0.08 : 0.06),
            ],
          ),
          borderRadius: AppRadii.r16All,
          border: Border.all(
            color: p.warning.withValues(alpha: 0.42),
            width: 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: p.warning.withValues(alpha: 0.22),
              ),
              child: Icon(
                Icons.bookmark_rounded,
                size: 16,
                color: p.warning,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                l10n.resumeFromPrompt(Formatters.formatDuration(position)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppFontSize.bodySmall,
                  fontWeight: FontWeight.w700,
                  color: p.textPrimary,
                ),
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: p.warning,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(48, 34),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(
                  fontSize: AppFontSize.label,
                  fontWeight: FontWeight.w800,
                ),
              ),
              onPressed: () {
                HapticFeedback.selectionClick();
                cubit.seekToBookmark();
              },
              child: Text(l10n.resume),
            ),
            SizedBox(
              width: 34,
              height: 34,
              child: IconButton(
                padding: EdgeInsets.zero,
                tooltip: l10n.close,
                onPressed: () {
                  HapticFeedback.lightImpact();
                  cubit.dismissBookmark();
                },
                icon: Icon(
                  Icons.close_rounded,
                  size: 17,
                  color: p.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Seek bar + advanced playback bar + transport controls + optional volume bar
/// + bottom dock, with per-theme spacing/sizing deltas.
class PlayerControlsColumn extends StatelessWidget {
  final PlayerThemeProps props;
  final bool isTablet;
  final bool isLandscape;
  final bool isInSplitView;
  final Widget dock;
  final Widget? trackHeader;
  final double? mainButtonSize;
  final double? sideButtonSize;
  final bool classicSizing;
  final bool scaleMainButtonByHeight;
  final bool dense;
  final bool showAdvancedBar;
  final bool abLoopActive;
  final double heightRatio;
  final PlayerThemeMetrics? metrics;

  const PlayerControlsColumn({
    super.key,
    required this.props,
    required this.isTablet,
    required this.isLandscape,
    this.isInSplitView = false,
    required this.dock,
    this.trackHeader,
    this.mainButtonSize,
    this.sideButtonSize,
    this.classicSizing = false,
    this.scaleMainButtonByHeight = false,
    this.dense = false,
    this.showAdvancedBar = true,
    this.abLoopActive = false,
    this.heightRatio = 1.0,
    this.metrics,
  });

  @override
  Widget build(BuildContext context) {
    final state = props.state;
    final cubit = props.cubit;

    ExperienceMode mode = ExperienceMode.normal;
    try {
      mode = context
          .select<SettingsCubit, ExperienceMode>((c) => c.state.experienceMode);
    } catch (_) {
      mode = ExperienceMode.normal;
    }
    final showAbControls = showAdvancedBar &&
        (mode == ExperienceMode.professional ||
            state.abPointA != null ||
            state.abPointB != null);

    final double spacingTrackToSeek = metrics?.spacingTrackToSeek ??
        ((isTablet
                ? (classicSizing ? 18.0 : 14.0)
                : (isLandscape ? 4.0 : (classicSizing ? 14.0 : 12.0))) *
            heightRatio);
    final double spacingSeekToControls = metrics?.spacingSeekToControls ??
        ((isTablet
                ? (classicSizing ? 22.0 : 18.0)
                : (isLandscape ? 6.0 : (classicSizing ? 18.0 : 16.0))) *
            heightRatio);
    final double spacingSeekToAdvanced = metrics?.spacingSeekToAdvanced ??
        ((isTablet ? 12.0 : (isLandscape ? 4.0 : 10.0)) * heightRatio);
    final double spacingAdvancedToControls =
        metrics?.spacingAdvancedToControls ??
            ((isTablet ? 14.0 : (isLandscape ? 4.0 : 12.0)) * heightRatio);
    final double spacingControlsToDock = metrics?.spacingControlsToDock ??
        ((isTablet
                ? (classicSizing ? 20.0 : 16.0)
                : (isLandscape ? 6.0 : (classicSizing ? 16.0 : 14.0))) *
            heightRatio);
    final double spacingBelowDock = metrics?.spacingBelowDock ??
        ((isTablet
                ? (classicSizing ? 16.0 : 12.0)
                : (isLandscape ? 6.0 : (classicSizing ? 12.0 : 10.0))) *
            heightRatio);

    final double resolvedMainButtonSize = mainButtonSize ??
        metrics?.mainButtonSize ??
        ((isTablet
                ? (classicSizing ? 74.0 : 72.0)
                : (isLandscape
                    ? (classicSizing ? 58.0 : 56.0)
                    : (classicSizing ? 66.0 : 64.0))) *
            (scaleMainButtonByHeight ? heightRatio.clamp(0.85, 1.10) : 1.0));

    final double? resolvedSideButtonSize =
        sideButtonSize ?? metrics?.sideButtonSize;
    final double? resolvedWaveformHeight = metrics?.waveformHeight;
    final bool resolvedShowUpNext =
        !isInSplitView && (metrics?.showUpNext ?? true);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (trackHeader != null) trackHeader!,
        SizedBox(height: spacingTrackToSeek),
        PlayerSeekBar(
          duration: state.duration,
          activeColor: props.activeColor,
          songId: state.currentSong?.id,
          filePath: state.currentSong?.path,
          loopPointA: state.abPointA,
          loopPointB: state.abPointB,
          showUpNext: resolvedShowUpNext,
          waveformHeight: resolvedWaveformHeight,
          onSeek: (pos) => cubit.seek(pos),
        ),
        if (state.bookmarkPosition != null) ...[
          SizedBox(height: spacingSeekToAdvanced),
          PlayerBookmarkPromptBanner(
            cubit: cubit,
            position: state.bookmarkPosition!,
          ),
          SizedBox(height: spacingAdvancedToControls),
        ] else ...[
          SizedBox(height: spacingSeekToControls),
        ],
        PlayerControls(
          isPlaying: state.isPlaying,
          isBuffering: state.isBuffering,
          isShuffle: state.isShuffle,
          repeatMode: state.repeatMode,
          hasPrevious: state.hasPreviousNeighbour,
          hasNext: state.hasNextNeighbour,
          abLoopActive: abLoopActive,
          showAbControls: showAbControls,
          abPointA: state.abPointA,
          abPointB: state.abPointB,
          onSetAbPointA: () => cubit.setAbPointA(),
          onSetAbPointB: () => cubit.setAbPointB(),
          onToggleAbLoop: () => cubit.toggleAbLoop(),
          onClearAbLoop: () => cubit.clearAbLoop(),
          primaryColor: props.activeColor,
          mainButtonSize: resolvedMainButtonSize,
          sideButtonSize: resolvedSideButtonSize,
          onPlayPause: () => cubit.togglePlayPause(),
          onNext: () => cubit.next(),
          onPrevious: () => cubit.previous(),
          onToggleShuffle: () => cubit.toggleShuffle(),
          onToggleRepeat: () => cubit.toggleRepeat(),
        ),
        if (isInSplitView || isTablet) ...[
          const SizedBox(height: AppSpacing.s8),
          PlayerVolumeBar(cubit: cubit, activeColor: props.activeColor),
        ],
        SizedBox(height: spacingControlsToDock),
        dock,
        if (!dense) SizedBox(height: spacingBelowDock),
      ],
    );
  }
}