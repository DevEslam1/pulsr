// lib/features/player/presentation/themes/player_theme_chrome.dart
//
// Shared chrome for the eight now-playing themes (A-13). The view-switcher
// pill, the bottom action dock, the switcher item, the animated favourite
// button and the dock icon button were previously copy-pasted into every theme
// file. They now live here; themes parameterise the handful of visual tokens
// they actually differ on instead of keeping private copies.
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:go_router/go_router.dart';

import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/performance/gpu_budget.dart';
import '../../../../core/services/sound_feedback_service.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/utils/pulsr_haptics.dart';
import '../../../../core/widgets/marquee_text.dart';
import '../../../../core/widgets/waveform_logo.dart';
import '../../../../data/db/app_database.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../../settings/cubit/settings_state.dart';
import '../../../sheets/add_to_playlist_sheet.dart';
import '../../../sheets/sleep_timer_sheet.dart';
import '../../../sheets/song_info_sheet.dart';
import '../../../ytm_search/presentation/widgets/ytm_download_button.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';
import '../widgets/advanced_playback_bar.dart';
import '../widgets/audio_quality_badge.dart';
import '../widgets/audio_quality_sheet.dart';
import '../widgets/equalizer_sheet.dart';
import '../widgets/player_controls.dart';
import '../widgets/player_seek_bar.dart';
import '../widgets/player_volume_bar.dart';
import '../widgets/quran_mode_button.dart';
import '../widgets/speed_picker_sheet.dart';
import '../../../../domain/services/cast_service.dart';
import '../../../../domain/models/audio_output_info.dart';
import 'player_theme.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/constants/app_colors.dart';

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
      label: semanticsLabel,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadii.r20All,
          child: AnimatedContainer(
            duration: context.motionMs(200),
            curve: context.motionCurve(Curves.easeOutCubic),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected
                  ? activeColor.withValues(alpha: 0.22)
                  : Colors.transparent,
              borderRadius: AppRadii.r20All,
              border: isSelected
                  ? Border.all(
                      color: activeColor.withValues(alpha: 0.45),
                      width: 1.0,
                    )
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: isTablet ? 16 : 14,
                  color: isSelected ? activeColor : p.textSecondary,
                ),
                const SizedBox(width: AppSpacing.xxs),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize:
                          isTablet ? AppFontSize.bodySmall : AppFontSize.label,
                      fontWeight:
                          isSelected ? FontWeight.w800 : FontWeight.w600,
                      color: isSelected ? p.textPrimary : p.textSecondary,
                      letterSpacing: AppTracking.label,
                    ),
                  ),
                ),
                if (badgeCount != null && badgeCount! > 0) ...[
                  const SizedBox(width: AppSpacing.xxs),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4.5, vertical: AppSpacing.s2),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? activeColor
                          : p.textPrimary.withValues(alpha: 0.15),
                      borderRadius: AppRadii.r8All,
                    ),
                    child: Text(
                      '$badgeCount',
                      style: TextStyle(
                        fontSize: AppFontSize.tiny,
                        fontWeight: FontWeight.w800,
                        color: isSelected ? p.onAccent : p.textSecondary,
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
                  scale: CurvedAnimation(
                    parent: anim,
                    curve: context.motionCurve(curve),
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

/// Circular action button used inside the bottom action dock.
class PlayerDockIconButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
              color: isActive
                  ? activeColor.withValues(alpha: style.activeFillAlpha)
                  : Colors.transparent,
              border: style.activeBorder && isActive
                  ? Border.all(
                      color: activeColor.withValues(alpha: 0.45),
                      width: 1.2,
                    )
                  : null,
            ),
            child: Icon(
              icon,
              size: style.iconSizeFor(isTablet),
              color: isActive ? activeColor : inactiveColor,
            ),
          ),
          if (badgeText != null)
            PositionedDirectional(
              top: -2,
              end: style.badgeRight,
              child: Container(
                padding: EdgeInsets.symmetric(
                    horizontal: style.badgeHPadding, vertical: AppSpacing.s2),
                decoration: BoxDecoration(
                  color: activeColor,
                  borderRadius: AppRadii.circular(style.badgeRadius),
                  boxShadow: style.badgeShadow
                      ? [
                          BoxShadow(
                            color: AppColors.scrimAt(0.3),
                            blurRadius: 4,
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  badgeText!,
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: style.badgeFontSize,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    // Preserve the original widget nesting order per variant: the classic copy
    // put the tooltip inside the InkWell, the common copy put it outside.
    final Widget body;
    if (style.tooltipOutside) {
      body = Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadii.circular(style.inkWellRadius),
          child: inner,
        ),
      );
    } else {
      body = InkWell(
        onTap: onTap,
        borderRadius: AppRadii.circular(style.inkWellRadius),
        child: Tooltip(
          message: tooltip,
          excludeFromSemantics: true,
          child: inner,
        ),
      );
    }

    return Semantics(
      button: true,
      label: tooltip,
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
    final surfaceBase = p.isDark ? Colors.white : Colors.black;
    // Custom Theme Studio shape controls apply when the user picked the custom
    // colour source, so preset themes keep their hand-tuned geometry.
    final custom = context
        .select<SettingsCubit, ({double radius, bool glow, bool active})>(
            (c) => (
                  radius: c.state.customThemeRadius,
                  glow: c.state.customThemeGlow,
                  active: c.state.themeColorSource == ThemeColorSource.custom,
                ));
    final barRadius = custom.active ? custom.radius : 24.0;
    final showGlow = custom.active && custom.glow;

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
          child: Builder(
            builder: (context) {
              final pillContainer = Container(
                padding: const EdgeInsets.all(3.0),
                decoration: BoxDecoration(
                  color: GpuBudget.isGpuSaverActive
                      ? surfaceBase
                      : surfaceBase.withValues(alpha: surfaceFillAlpha),
                  borderRadius: AppRadii.circular(barRadius),
                  border: Border.all(
                    color: surfaceBase.withValues(alpha: borderAlpha),
                    width: 1.0,
                  ),
                  boxShadow: [
                    if (showGlow)
                      BoxShadow(
                        color: activeColor.withValues(alpha: 0.30),
                        blurRadius: 20,
                        spreadRadius: 1,
                      ),
                    BoxShadow(
                      color: AppColors.scrimAt(0.20),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
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
              );

              if (GpuBudget.isGpuSaverActive) {
                return pillContainer;
              }
              return BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: pillContainer,
              );
            },
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
    } catch (_) {}
    bool isEndQ = false;
    try {
      isEndQ = props.cubit.isEndOfQueueSleepTimer == true;
    } catch (_) {}
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
    final showGlow = custom.active && custom.glow;

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
          child: Builder(
            builder: (context) {
              final dockContainer = Container(
                padding: const EdgeInsets.all(3.0),
                decoration: BoxDecoration(
                  color: GpuBudget.isGpuSaverActive
                      ? p.surface
                      : (p.isDark ? Colors.white : Colors.black)
                          .withValues(alpha: 0.06),
                  borderRadius: AppRadii.circular(barRadius),
                  border: Border.all(
                    color: (p.isDark ? Colors.white : Colors.black)
                        .withValues(alpha: 0.12),
                    width: 1.0,
                  ),
                  boxShadow: [
                    if (showGlow)
                      BoxShadow(
                        color: props.activeColor.withValues(alpha: 0.28),
                        blurRadius: 20,
                        spreadRadius: 1,
                      ),
                    BoxShadow(
                      color: AppColors.scrimAt(0.20),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
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
                        tooltip:
                            isCast ? 'Google Cast' : l10n.audioOutputAndDac,
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
                        badgeText: speed != 1.0
                            ? '${speed.toStringAsFixed(1)}x'
                            : null,
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

                    // 4. Sleep Timer
                    Expanded(
                      child: PlayerDockIconButton(
                        icon: Icons.timer_outlined,
                        tooltip: isEndQ
                            ? 'Sleep Timer: End of Queue'
                            : (remainingTracks != null
                                ? 'Sleep Timer: $remainingTracks tracks remaining'
                                : (props.state.sleepTimerRemaining != null
                                    ? 'Sleep Timer: ${props.state.sleepTimerRemaining!.inMinutes}m remaining'
                                    : l10n.sleepTimer)),
                        badgeText: hasTimer
                            ? (remainingTracks != null
                                ? '$remainingTracks tr'
                                : (isEndQ
                                    ? 'End'
                                    : (props.state.sleepTimerRemaining != null
                                        ? '${props.state.sleepTimerRemaining!.inMinutes}m'
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

                    // 5. Quran Mode
                    Expanded(
                      child: QuranModeDockButton(
                        activeColor: props.activeColor,
                        inactiveColor: p.textSecondary,
                        isTablet: isTablet,
                      ),
                    ),

                    // 6. Add to Playlist
                    Expanded(
                      child: PlayerDockIconButton(
                        icon: Icons.playlist_add_rounded,
                        tooltip: l10n.addToPlaylist,
                        isActive: false,
                        activeColor: props.activeColor,
                        inactiveColor: p.textSecondary,
                        isTablet: isTablet,
                        style: dockIconStyle,
                        onTap: () {
                          if (song != null) {
                            HapticFeedback.lightImpact();
                            AddToPlaylistSheet.show(context, song: song);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              );

              if (disableBlur || GpuBudget.isGpuSaverActive) {
                return dockContainer;
              }
              return BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: dockContainer,
              );
            },
          ),
        ),
      ),
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
    return Padding(
      padding: padding,
      child: Center(
        child: Container(
          width: 38,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.specularAt(0.22),
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
        width: 48,
        height: 48,
        child: Material(
          color: AppColors.specular,
          shape: const CircleBorder(),
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
          ),
          Expanded(
            child: centerWidget != null
                ? Center(child: centerWidget!)
                : Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            WaveformLogo(
                              size: 13,
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
                                    color:
                                        resolvedSubtitle.withValues(alpha: 0.8),
                                  ),
                            )),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.s2),
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
          circleButton(
            icon: Icons.more_horiz_rounded,
            semanticLabel: context.l10n.songInfo,
            iconSize: isTablet ? 24 : 22,
            onTap: () {
              HapticFeedback.lightImpact();
              if (onMore != null) {
                onMore!();
              } else if (song != null) {
                SongInfoSheet.show(context, song: song);
              }
            },
          ),
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
  final double verticalPadding;
  final Color? titleColor;
  final Color? subtitleColor;
  final Widget? extraBadge;
  final double badgeGap;
  final double titleArtistGap;
  final bool showQualityBadge;

  const PlayerTrackHeader({
    super.key,
    required this.props,
    required this.isTablet,
    this.horizontalPadding = 16,
    this.tabletHorizontalPadding = 28,
    this.verticalPadding = AppSpacing.s2,
    this.titleColor,
    this.subtitleColor,
    this.extraBadge,
    this.badgeGap = AppSpacing.s6,
    this.titleArtistGap = AppSpacing.xxs,
    this.showQualityBadge = true,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = props.state;
    final song = state.currentSong;
    final resolvedTitle = titleColor ?? p.textPrimary;
    final resolvedSubtitle = subtitleColor ?? p.textSecondary;
    final hasDownload = song != null &&
        (song.source == SongSource.youtube ||
            (song.remoteId != null && song.remoteId!.isNotEmpty));

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
        vertical: verticalPadding,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: isTablet ? 48 : 44,
                height: isTablet ? 48 : 44,
                child: Material(
                  color: AppColors.specularAt(0.06),
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: hasDownload
                      ? Center(
                          child: YtmDownloadButton(
                            song: song,
                            activeColor: props.activeColor,
                            iconColor: resolvedSubtitle,
                            iconSize: isTablet ? 24 : 22,
                          ),
                        )
                      : InkWell(
                          onTap: () {
                            if (song != null) {
                              HapticFeedback.lightImpact();
                              SongInfoSheet.show(context, song: song);
                            }
                          },
                          child: Center(
                            child: Icon(
                              Icons.info_outline_rounded,
                              semanticLabel: context.l10n.songInfo,
                              size: isTablet ? 24 : 22,
                              color: resolvedSubtitle,
                            ),
                          ),
                        ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.s10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MarqueeText(
                        text: song?.title ?? context.l10n.noTrackSelected,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: isTablet
                              ? AppFontSize.headline
                              : AppFontSize.title,
                          fontWeight: FontWeight.w900,
                          color: resolvedTitle,
                          height: 1.22,
                          letterSpacing: AppTracking.title,
                        ),
                      ),
                      SizedBox(height: titleArtistGap),
                      MarqueeText(
                        text: song?.artist ?? context.l10n.unknownArtist,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: isTablet
                              ? AppFontSize.callout
                              : AppFontSize.bodySmall,
                          fontWeight: FontWeight.w600,
                          color: resolvedSubtitle,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: AppSpacing.xxl,
                height: 48,
                child: Material(
                  color: AppColors.specularAt(0.06),
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: PlayerAnimatedFavoriteButton(
                    isFavorite: song?.isFavorite == true,
                    semanticLabel: song?.isFavorite == true
                        ? context.l10n.unlike
                        : context.l10n.like,
                    favoriteColor: p.favorite,
                    inactiveColor: resolvedSubtitle,
                    iconSize: isTablet ? 24 : 22,
                    onTap: () {
                      if (song != null) {
                        props.cubit.toggleFavorite(song.id);
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
          if (showQualityBadge && qualityBadge != null) ...[
            SizedBox(height: badgeGap),
            Center(
              child: extraBadge == null
                  ? qualityBadge
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          qualityBadge,
                          const SizedBox(width: AppSpacing.xs),
                          extraBadge!,
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
  final bool classicSizing;
  final bool scaleMainButtonByHeight;
  final bool dense;
  final bool showAdvancedBar;
  final bool abLoopActive;
  final double heightRatio;

  const PlayerControlsColumn({
    super.key,
    required this.props,
    required this.isTablet,
    required this.isLandscape,
    this.isInSplitView = false,
    required this.dock,
    this.trackHeader,
    this.mainButtonSize,
    this.classicSizing = false,
    this.scaleMainButtonByHeight = false,
    this.dense = false,
    this.showAdvancedBar = true,
    this.abLoopActive = false,
    this.heightRatio = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final state = props.state;
    final cubit = props.cubit;

    final double spacingTrackToSeek = (isTablet
            ? (classicSizing ? 16.0 : 10.0)
            : (isLandscape ? 4.0 : (classicSizing ? 10.0 : 6.0))) *
        heightRatio;
    final double spacingSeekToControls = (isTablet
            ? (classicSizing ? 18.0 : 12.0)
            : (isLandscape ? 6.0 : (classicSizing ? 12.0 : 8.0))) *
        heightRatio;
    final double spacingControlsToDock = (isTablet
            ? (classicSizing ? 18.0 : 12.0)
            : (isLandscape ? 6.0 : (classicSizing ? 12.0 : 8.0))) *
        heightRatio;
    final double spacingBelowDock = (isTablet
            ? (classicSizing ? 14.0 : 8.0)
            : (isLandscape ? 6.0 : (classicSizing ? 8.0 : 4.0))) *
        heightRatio;

    final double resolvedMainButtonSize = mainButtonSize ??
        (isTablet
                ? (classicSizing ? 74.0 : 72.0)
                : (isLandscape
                    ? (classicSizing ? 58.0 : 56.0)
                    : (classicSizing ? 66.0 : 64.0))) *
            (scaleMainButtonByHeight ? heightRatio.clamp(0.85, 1.10) : 1.0);

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
          showUpNext: !isInSplitView,
          onSeek: (pos) => cubit.seek(pos),
        ),
        SizedBox(height: spacingSeekToControls),
        if (showAdvancedBar) const AdvancedPlaybackBar(),
        PlayerControls(
          isPlaying: state.isPlaying,
          isShuffle: state.isShuffle,
          repeatMode: state.repeatMode,
          hasPrevious: state.hasPreviousNeighbour,
          hasNext: state.hasNextNeighbour,
          abLoopActive: abLoopActive,
          primaryColor: props.activeColor,
          mainButtonSize: resolvedMainButtonSize,
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
