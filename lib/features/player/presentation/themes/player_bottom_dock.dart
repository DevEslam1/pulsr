// lib/features/player/presentation/themes/player_bottom_dock.dart
import 'dart:math' as math;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/services/ambient_sound_service.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/utils/pulsr_haptics.dart';
import '../../../../data/db/app_database.dart';
import '../../../../data/party/listen_together_service.dart';
import '../../../../data/party/party_models.dart';
import '../../../../data/services/cast_service.dart';
import '../../../../domain/models/audio_output_info.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../../settings/cubit/settings_state.dart';
import '../../../sheets/sleep_timer_sheet.dart';
import '../../cubit/player_cubit.dart';
import '../widgets/ambient_sound_sheet.dart';
import '../widgets/audio_quality_sheet.dart';
import '../widgets/equalizer_sheet.dart';
import '../widgets/player_controls.dart';
import '../widgets/player_more_sheet.dart';
import '../widgets/player_seek_bar.dart';
import '../widgets/player_volume_bar.dart';
import '../widgets/quran_mode_sheet.dart';
import '../widgets/radio_now_playing_recommendations.dart';
import '../widgets/speed_picker_sheet.dart';
import 'player_theme.dart';
import 'player_theme_scaffold.dart'
    show PlayerThemeMetrics, PlayerThemePreviewScope;
import 'player_track_header.dart';

/// Readable foreground for a badge painted with an arbitrary (possibly
/// artwork-derived) accent, instead of assuming every accent is dark.
Color _readableOn(Color background) => AppColors.textOnAccent(background);

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

/// Visual tokens for the dock icon button.
///
/// The dock is shared chrome, not a per-theme surface: every theme draws the
/// same control, so it must look identical in all of them. `classic` used to
/// carry its own geometry (active border, larger phone icon, tooltip nested
/// inside the InkWell, different badge metrics) purely because it was built
/// first. That divergence read as an inconsistency when switching themes, so
/// every named style now resolves to [common]; the fields stay because the
/// button still reads them.
class PlayerDockIconStyle {
  final double inkWellRadius;

  /// true: `Tooltip` wraps the `InkWell`. false: `InkWell` wraps the
  /// `Tooltip`. All shipped styles use true; the variant is kept so the button
  /// has one code path rather than a special case for a single theme.
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
    badgeFontSize: 10,
  );

  static const PlayerDockIconStyle cd = common;
  static const PlayerDockIconStyle circle = common;
  static const PlayerDockIconStyle cassette = common;
  static const PlayerDockIconStyle lyricsFocus = common;
  static const PlayerDockIconStyle minimal = common;
  static const PlayerDockIconStyle vinyl = common;
  static const PlayerDockIconStyle waveform = common;

  // Kept as a name, not a variant: callers still pass it, but the dock must
  // not change shape when the user switches Now Playing theme.
  static const PlayerDockIconStyle classic = common;
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
    final allowMotion = PulsrMotion.shouldAnimate(context);

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
      scale: (_isPressed && allowMotion) ? 0.88 : 1.0,
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
      toggled: isActive,
      label: widget.tooltip,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: AppSpacing.minTouchTarget,
          minHeight: AppSpacing.minTouchTarget,
        ),
        child: body,
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

    final IconData deviceOutputIcon = outputDevice == null
        ? Icons.headphones_rounded
        : (outputDevice.isUsb
            ? Icons.usb_rounded
            : (outputDevice.isBt
                ? Icons.bluetooth_audio_rounded
                : (outputDevice.isSpeaker
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 4.0, vertical: 3.0),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.lerp(
                          p.surfaceContainer,
                          AppColors.specularAt(1.0),
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
                      : p.hairline,
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.scrimAt(p.isDark ? 0.28 : 0.06),
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
                        PulsrHaptics.lightImpact();
                        EqualizerSheet.show(context);
                      },
                    ),
                  ),

                  // 2. Audio Output & DAC
                  // AUDIT-FIX (P3-24): Listen reactively to CastService so
                  // CAST badge and icon update immediately on session changes.
                  Expanded(
                    child: ValueListenableBuilder<CastSessionStatus>(
                      valueListenable: CastService().sessionStatusListenable,
                      builder: (context, castStatus, _) {
                        final isCast = castStatus.connected;
                        return PlayerDockIconButton(
                          icon: isCast
                              ? Icons.cast_connected_rounded
                              : deviceOutputIcon,
                          tooltip:
                              isCast ? l10n.googleCast : l10n.audioOutputAndDac,
                          badgeText: isCast ? 'CAST' : (isUsb ? 'DAC' : null),
                          isActive: isCast || isUsb,
                          activeColor: isCast ? p.info : p.goldAccent,
                          inactiveColor: p.textSecondary,
                          isTablet: isTablet,
                          style: dockIconStyle,
                          onTap: () {
                            if (song != null) {
                              PulsrHaptics.lightImpact();
                              AudioQualitySheet.show(
                                  context, song, props.activeColor);
                            }
                          },
                        );
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
                        PulsrHaptics.lightImpact();
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
                      activeColor:
                          p.isDark ? AppColors.quranEmerald : p.success,
                      inactiveColor: p.textSecondary,
                      isTablet: isTablet,
                      style: dockIconStyle,
                      onTap: () {
                        PulsrHaptics.lightImpact();
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
                            PulsrHaptics.lightImpact();
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
                          ? l10n.sleepTimerEndOfQueue
                          : (remainingTracks != null
                              ? l10n.sleepTimerTracksRemaining(remainingTracks)
                              : (props.state.sleepTimerRemaining != null
                                  ? l10n.sleepTimerTimeRemaining(
                                      formatSleepTimerRemaining(
                                          props.state.sleepTimerRemaining!),
                                    )
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
                        PulsrHaptics.lightImpact();
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
    PulsrHaptics.lightImpact();
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
    final isPreview = PlayerThemePreviewScope.of(context);

    ExperienceMode mode = ExperienceMode.normal;
    try {
      mode = context
          .select<SettingsCubit, ExperienceMode>((c) => c.state.experienceMode);
    } catch (_) {
      mode = ExperienceMode.normal;
    }
    final showAbControls = !isPreview &&
        showAdvancedBar &&
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
        !isPreview && !isInSplitView && (metrics?.showUpNext ?? true);

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
          loopPointA: isPreview ? null : state.abPointA,
          loopPointB: isPreview ? null : state.abPointB,
          showUpNext: resolvedShowUpNext,
          waveformHeight: resolvedWaveformHeight,
          onSeek: (pos) => cubit.seek(pos),
        ),
        if (!isPreview && state.currentSong?.source == SongSource.radio) ...[
          const SizedBox(height: AppSpacing.xs),
          RadioNowPlayingRecommendations(
            props: props,
            cubit: cubit,
            metrics: metrics,
          ),
          const SizedBox(height: AppSpacing.xs),
        ] else if (!isPreview && state.bookmarkPosition != null) ...[
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
          abLoopActive: isPreview ? false : abLoopActive,
          showAbControls: showAbControls,
          abPointA: isPreview ? null : state.abPointA,
          abPointB: isPreview ? null : state.abPointB,
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
        if (!isPreview &&
            (isInSplitView || isTablet) &&
            !(metrics?.isVeryShortHeight ?? false)) ...[
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
