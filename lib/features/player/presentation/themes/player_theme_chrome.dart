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

import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../settings/cubit/settings_state.dart';
import '../../../sheets/add_to_playlist_sheet.dart';
import '../../../sheets/sleep_timer_sheet.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';
import '../widgets/audio_quality_sheet.dart';
import '../widgets/equalizer_sheet.dart';
import '../widgets/quran_mode_button.dart';
import '../widgets/speed_picker_sheet.dart';
import 'player_theme.dart';

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
    final semanticsLabel =
        (badgeCount != null && badgeCount! > 0) ? '$label ($badgeCount)' : label;
    return Semantics(
      button: true,
      label: semanticsLabel,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: context.motionMs(200),
            curve: context.motionCurve(Curves.easeOutCubic),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected
                  ? activeColor.withValues(alpha: 0.22)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
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
                  color: isSelected ? activeColor : Colors.white60,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: isTablet ? 13 : 11.5,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      color: isSelected ? Colors.white : Colors.white60,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                if (badgeCount != null && badgeCount! > 0) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? activeColor
                          : Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$badgeCount',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: isSelected ? Colors.black : Colors.white70,
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
            HapticFeedback.mediumImpact();
            onTap();
          },
          child: Center(
            child: AnimatedSwitcher(
              duration: context.motionMs(240),
              transitionBuilder: (child, anim) => ScaleTransition(
                scale: anim,
                child: child,
              ),
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
            Positioned(
              top: -2,
              right: style.badgeRight,
              child: Container(
                padding: EdgeInsets.symmetric(
                    horizontal: style.badgeHPadding, vertical: 1),
                decoration: BoxDecoration(
                  color: activeColor,
                  borderRadius: BorderRadius.circular(style.badgeRadius),
                  boxShadow: style.badgeShadow
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
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
          borderRadius: BorderRadius.circular(style.inkWellRadius),
          child: inner,
        ),
      );
    } else {
      body = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(style.inkWellRadius),
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
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
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
    final isLyrics = state.isLyricsVisible;
    final isQueue = state.isQueueVisible;
    final isTrack = !isLyrics && !isQueue;
    final l10n = context.l10n;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: barWidth,
          minWidth: barWidth,
          maxHeight: barHeight,
          minHeight: barHeight,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: const EdgeInsets.all(3.0),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: surfaceFillAlpha),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withValues(alpha: borderAlpha),
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.20),
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
                          if (isLyrics) cubit.toggleLyricsVisibility();
                          if (isQueue) cubit.toggleQueueVisibility();
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
  final SettingsState settingsState;
  final bool isTablet;
  final double barWidth;
  final double barHeight;
  final PlayerDockIconStyle dockIconStyle;

  const PlayerBottomActionDock({
    super.key,
    required this.props,
    required this.settingsState,
    required this.isTablet,
    required this.barWidth,
    required this.barHeight,
    this.dockIconStyle = PlayerDockIconStyle.common,
  });

  @override
  Widget build(BuildContext context) {
    final song = props.state.currentSong;
    final p = context.palette;
    final l10n = context.l10n;
    final isUsb = settingsState.currentOutputDevice?.isUsbDac == true;
    final outputDevice = settingsState.currentOutputDevice;
    final isEqActive = props.state.isEqEnabled;
    final speed = props.state.playbackSpeed;
    final hasTimer = props.state.sleepTimerRemaining != null;

    final IconData outputIcon = isUsb
        ? Icons.usb_rounded
        : (outputDevice?.deviceName.contains('Bluetooth') == true ||
                outputDevice?.deviceName.contains('A2DP') == true
            ? Icons.bluetooth_audio_rounded
            : (outputDevice?.deviceName.contains('Speaker') == true
                ? Icons.speaker_rounded
                : Icons.headphones_rounded));

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: barWidth,
          minWidth: barWidth,
          maxHeight: barHeight,
          minHeight: barHeight,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: const EdgeInsets.all(3.0),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.20),
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
                      tooltip: l10n.audioOutputAndDac,
                      isActive: isUsb,
                      activeColor: const Color(0xFFFFD700),
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
                      tooltip: l10n.sleepTimer,
                      badgeText: hasTimer
                          ? (props.cubit.sleepTimerRemainingTracks != null
                              ? '${props.cubit.sleepTimerRemainingTracks} tr'
                              : '${props.state.sleepTimerRemaining!.inMinutes}m')
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
            ),
          ),
        ),
      ),
    );
  }
}
