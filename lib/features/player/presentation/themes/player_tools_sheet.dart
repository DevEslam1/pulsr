// lib/features/player/presentation/themes/player_tools_sheet.dart
import 'dart:async' show FutureOr;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/services/ambient_sound_service.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/utils/pulsr_haptics.dart';
import '../../../../core/widgets/pulsr_bottom_sheet.dart';
import '../../../../core/widgets/pulsr_list_tile.dart';
import '../../../../data/party/listen_together_service.dart';
import '../../../../data/services/cast_service.dart';
import '../../../../domain/models/audio_output_info.dart';
import '../../../settings/cubit/settings_cubit.dart';
import '../../../settings/cubit/settings_state.dart';
import '../../../sheets/sleep_timer_sheet.dart';
import '../../cubit/player_cubit.dart';
import '../../cubit/player_state.dart';
import '../widgets/ambient_sound_sheet.dart';
import '../widgets/audio_quality_sheet.dart';
import '../widgets/equalizer_sheet.dart';
import '../widgets/player_more_sheet.dart';
import '../widgets/quran_mode_sheet.dart';
import '../widgets/speed_picker_sheet.dart';
import 'player_bottom_dock.dart' show formatSleepTimerRemaining;
import 'player_theme.dart';

Color _readableOnColor(Color background) => AppColors.textOnAccent(background);

/// Returns the number of currently active secondary player tools so compact
/// themes can display an indicator dot or badge count on their Tools button.
///
/// Counts:
/// - Equalizer / DSP active
/// - USB DAC or Cast session active
/// - Non-1.0x playback speed
/// - Quran Mode enabled
/// - Ambient soundscape active
/// - Sleep timer active
/// - A/B loop enabled or partially set
/// - Pulsr Party session active (when [ListenTogetherService] is registered)
int countActiveSecondaryTools(
  PlayerState state,
  SettingsState settings, {
  bool? isAmbientActive,
  bool? isCastConnected,
  bool? isPartyActive,
}) {
  var count = 0;

  if (state.isEqEnabled || state.dsp.isDspActive) count++;

  final castActive = isCastConnected ?? CastService().sessionStatus.connected;
  final usbDac = settings.currentOutputDevice?.isUsbDac == true;
  if (castActive || usbDac) count++;

  if ((state.playbackSpeed - 1.0).abs() > 0.01) count++;

  if (state.isQuranModeEnabled) count++;

  final ambientActive = isAmbientActive ?? AmbientSoundService().isEnabled;
  if (ambientActive) count++;

  final hasTimer = state.sleepTimerRemaining != null ||
      state.sleepTimerRemainingTracks != null ||
      state.isEndOfQueueSleepTimer;
  if (hasTimer) count++;

  if (state.abLoopEnabled || state.abPointA != null || state.abPointB != null) {
    count++;
  }

  var partyActive = isPartyActive ?? false;
  if (isPartyActive == null) {
    try {
      if (getIt.isRegistered<ListenTogetherService>()) {
        final conn = getIt<ListenTogetherService>().connectionState.value;
        partyActive = conn == PartyConnectionState.live ||
            conn == PartyConnectionState.connecting;
      }
    } catch (_) {
      partyActive = false;
    }
  }
  if (partyActive) count++;

  return count;
}

/// Expandable secondary tools sheet/dialog housing A/B Loop controls and all
/// 7 secondary dock actions (Equalizer/DSP, Audio Output/DAC/Cast, Playback
/// Speed, Quran Mode, Ambient Soundscape, Sleep Timer, More/Party/Playlist/
/// Canvas/Gestures).
///
/// Presents via [PulsrSheetHelper.showPulsrSheet], which automatically adapts
/// to a centered dialog on Tablet and Desktop screens.
enum _PlayerToolAction {
  equalizer,
  audioQuality,
  speedPicker,
  quranMode,
  ambientSound,
  sleepTimer,
  more,
}

class PlayerToolsSheet extends StatelessWidget {
  final PlayerThemeProps props;
  final bool popWithResult;

  const PlayerToolsSheet({
    super.key,
    required this.props,
    this.popWithResult = false,
  });

  static Future<void> show(
    BuildContext context, {
    required PlayerThemeProps props,
  }) async {
    final playerCubit = context.read<PlayerCubit>();
    final settingsCubit = context.read<SettingsCubit>();
    final action = await PulsrSheetHelper.showPulsrSheet<_PlayerToolAction>(
      context: context,
      wrapWithContainer: true,
      builder: (_) => MultiBlocProvider(
        providers: [
          BlocProvider<PlayerCubit>.value(value: playerCubit),
          BlocProvider<SettingsCubit>.value(value: settingsCubit),
        ],
        child: PlayerToolsSheet(props: props, popWithResult: true),
      ),
    );
    if (action == null || !context.mounted) return;
    final currentSong =
        playerCubit.state.currentSong ?? props.state.currentSong;
    switch (action) {
      case _PlayerToolAction.equalizer:
        await EqualizerSheet.show(context);
      case _PlayerToolAction.audioQuality:
        if (currentSong != null) {
          AudioQualitySheet.show(context, currentSong, props.activeColor);
        }
      case _PlayerToolAction.speedPicker:
        await SpeedPickerSheet.show(context);
      case _PlayerToolAction.quranMode:
        await QuranModeSheet.show(context);
      case _PlayerToolAction.ambientSound:
        await AmbientSoundSheet.show(context);
      case _PlayerToolAction.sleepTimer:
        await SleepTimerSheet.show(context);
      case _PlayerToolAction.more:
        await PlayerMoreSheet.show(
          context,
          song: currentSong,
          activeColor: props.activeColor,
        );
    }
  }

  void _triggerSecondarySheet(
    BuildContext context,
    _PlayerToolAction action,
    FutureOr<void> Function(BuildContext callerContext) launchFromCaller,
  ) {
    PulsrHaptics.selection();
    if (popWithResult) {
      Navigator.of(context).pop(action);
      return;
    }
    final callerContext = Navigator.of(context).context;
    Navigator.of(context).pop();
    if (callerContext.mounted) {
      launchFromCaller(callerContext);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    final activeColor = props.activeColor;
    final song = context.select<PlayerCubit, dynamic>(
      (c) => c.state.currentSong,
    );
    final isEqActive = context.select<PlayerCubit, bool>(
      (c) => c.state.isEqEnabled || c.state.dsp.isDspActive,
    );
    final speed = context.select<PlayerCubit, double>(
      (c) => c.state.playbackSpeed,
    );
    final isQuranMode = context.select<PlayerCubit, bool>(
      (c) => c.state.isQuranModeEnabled,
    );
    final sleepState = context.select<
        PlayerCubit,
        ({
          Duration? remaining,
          int? remainingTracks,
          bool isEndOfQueue,
        })>((c) => (
          remaining: c.state.sleepTimerRemaining,
          remainingTracks: c.state.sleepTimerRemainingTracks,
          isEndOfQueue: c.state.isEndOfQueueSleepTimer,
        ));
    final outputDevice = context.select<SettingsCubit, AudioOutputInfo?>(
      (c) => c.state.currentOutputDevice,
    );

    final hasTimer = sleepState.remaining != null ||
        sleepState.remainingTracks != null ||
        sleepState.isEndOfQueue;
    final timerSubtitle = sleepState.isEndOfQueue
        ? l10n.sleepTimerEndOfQueue
        : (sleepState.remainingTracks != null
            ? l10n.sleepTimerTracksRemaining(sleepState.remainingTracks!)
            : (sleepState.remaining != null
                ? l10n.sleepTimerTimeRemaining(
                    formatSleepTimerRemaining(sleepState.remaining!),
                  )
                : l10n.sleepTimerSubtitle));

    final IconData deviceOutputIcon = outputDevice == null
        ? Icons.headphones_rounded
        : (outputDevice.isUsb
            ? Icons.usb_rounded
            : (outputDevice.isBt
                ? Icons.bluetooth_audio_rounded
                : (outputDevice.isSpeaker
                    ? Icons.speaker_rounded
                    : Icons.headphones_rounded)));

    return PulsrBottomSheetContainer(
      title: Text(l10n.moreOptions),
      subtitle: song == null
          ? null
          : Text(
              song.title as String,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Interactive A/B Loop Section
            _AbLoopSection(activeColor: activeColor),
            const SizedBox(height: AppSpacing.md),

            // 1. Equalizer & DSP
            _ToolActionTile(
              icon: Icons.tune_rounded,
              iconColor: activeColor,
              title: l10n.equalizer,
              subtitle: l10n.equalizerSubtitle,
              isActive: isEqActive,
              onTap: () => _triggerSecondarySheet(
                context,
                _PlayerToolAction.equalizer,
                EqualizerSheet.show,
              ),
            ),

            // 2. Audio Quality / Output / DAC / Cast
            ValueListenableBuilder<CastSessionStatus>(
              valueListenable: CastService().sessionStatusListenable,
              builder: (context, castStatus, _) {
                final isCast = castStatus.connected;
                final isUsb = outputDevice?.isUsbDac == true;
                final outputLabel = isCast
                    ? l10n.googleCast
                    : (outputDevice?.deviceName ?? l10n.audioQuality);
                return _ToolActionTile(
                  icon:
                      isCast ? Icons.cast_connected_rounded : deviceOutputIcon,
                  iconColor:
                      isCast ? p.info : (isUsb ? p.goldAccent : activeColor),
                  title: isCast ? l10n.googleCast : l10n.audioOutputAndDac,
                  subtitle: outputLabel,
                  badgeText: isCast ? 'CAST' : (isUsb ? 'DAC' : null),
                  isActive: isCast || isUsb,
                  onTap: () {
                    final currentSong = props.state.currentSong;
                    if (currentSong != null) {
                      _triggerSecondarySheet(
                        context,
                        _PlayerToolAction.audioQuality,
                        (callerContext) => AudioQualitySheet.show(
                          callerContext,
                          currentSong,
                          activeColor,
                        ),
                      );
                    }
                  },
                );
              },
            ),

            // 3. Playback Speed
            _ToolActionTile(
              icon: Icons.speed_rounded,
              iconColor: activeColor,
              title: l10n.playbackSpeed,
              subtitle: '${speed.toStringAsFixed(2)}x',
              badgeText: (speed - 1.0).abs() > 0.01
                  ? '${speed.toStringAsFixed(1)}x'
                  : null,
              isActive: (speed - 1.0).abs() > 0.01,
              onTap: () => _triggerSecondarySheet(
                context,
                _PlayerToolAction.speedPicker,
                SpeedPickerSheet.show,
              ),
            ),

            // 4. Quran Mode
            _ToolActionTile(
              icon: Icons.auto_stories_rounded,
              iconColor: p.isDark ? AppColors.quranEmerald : p.success,
              title: l10n.quranMode,
              subtitle:
                  isQuranMode ? l10n.dspQuranModeOn : l10n.dspQuranModeOff,
              isActive: isQuranMode,
              onTap: () => _triggerSecondarySheet(
                context,
                _PlayerToolAction.quranMode,
                QuranModeSheet.show,
              ),
            ),

            // 5. Ambient Soundscape
            AnimatedBuilder(
              animation: AmbientSoundService(),
              builder: (context, _) {
                final ambient = AmbientSoundService();
                final isAmbientActive = ambient.isEnabled;
                return _ToolActionTile(
                  icon: Icons.water_drop_rounded,
                  iconColor: activeColor,
                  title: l10n.ambientSounds,
                  subtitle: l10n.ambientSoundsDesc,
                  isActive: isAmbientActive,
                  onTap: () => _triggerSecondarySheet(
                    context,
                    _PlayerToolAction.ambientSound,
                    AmbientSoundSheet.show,
                  ),
                );
              },
            ),

            // 6. Sleep Timer
            _ToolActionTile(
              icon: Icons.timer_outlined,
              iconColor: activeColor,
              title: l10n.sleepTimer,
              subtitle: timerSubtitle,
              badgeText: hasTimer
                  ? (sleepState.remainingTracks != null
                      ? '${sleepState.remainingTracks} tr'
                      : (sleepState.isEndOfQueue
                          ? 'End'
                          : (sleepState.remaining != null
                              ? formatSleepTimerRemaining(sleepState.remaining!)
                              : null)))
                  : null,
              isActive: hasTimer,
              onTap: () => _triggerSecondarySheet(
                context,
                _PlayerToolAction.sleepTimer,
                SleepTimerSheet.show,
              ),
            ),

            // 7. More (Party, Playlist, Canvas, Gestures)
            _PartyAwareMoreTile(
              props: props,
              activeColor: activeColor,
              dividerColor: p.hairline,
              onTap: () => _triggerSecondarySheet(
                context,
                _PlayerToolAction.more,
                (callerContext) => PlayerMoreSheet.show(
                  callerContext,
                  song: props.state.currentSong,
                  activeColor: activeColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AbLoopSection extends StatelessWidget {
  final Color activeColor;

  const _AbLoopSection({required this.activeColor});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l10n = context.l10n;
    final cubit = context.read<PlayerCubit>();

    return BlocSelector<
        PlayerCubit,
        PlayerState,
        ({
          bool enabled,
          Duration? pointA,
          Duration? pointB,
        })>(
      selector: (s) => (
        enabled: s.abLoopEnabled,
        pointA: s.abPointA,
        pointB: s.abPointB,
      ),
      builder: (context, ab) {
        final hasAnyPoint = ab.pointA != null || ab.pointB != null;
        final canToggle = ab.pointA != null && ab.pointB != null;
        final labelA =
            ab.pointA != null ? Formatters.formatDuration(ab.pointA!) : '--:--';
        final labelB =
            ab.pointB != null ? Formatters.formatDuration(ab.pointB!) : '--:--';

        return Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: ab.enabled
                ? Color.alphaBlend(
                    activeColor.withValues(alpha: p.isDark ? 0.12 : 0.08),
                    p.surfaceContainer,
                  )
                : p.surfaceContainer.withValues(alpha: 0.72),
            borderRadius: AppRadii.r16All,
            border: Border.all(
              color: ab.enabled
                  ? activeColor.withValues(alpha: 0.45)
                  : (p.isHighContrast ? p.borderStrong : p.hairline),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.repeat_rounded,
                    size: 18,
                    color: ab.enabled ? activeColor : p.textSecondary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'A / B',
                    style: TextStyle(
                      fontSize: AppFontSize.bodySmall,
                      fontWeight: FontWeight.w800,
                      color: p.textPrimary,
                      letterSpacing: AppTracking.label,
                    ),
                  ),
                  const Spacer(),
                  _AbTimePill(
                    tag: 'A',
                    timeText: labelA,
                    isActive: ab.pointA != null,
                    activeColor: activeColor,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  _AbTimePill(
                    tag: 'B',
                    timeText: labelB,
                    isActive: ab.pointB != null,
                    activeColor: activeColor,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: _AbActionChip(
                      label: 'A',
                      semanticLabel: ab.pointA != null
                          ? l10n.abLoopPointA(labelA)
                          : l10n.abLoopSetA,
                      isActive: ab.pointA != null,
                      activeColor: activeColor,
                      onTap: () {
                        PulsrHaptics.selection();
                        cubit.setAbPointA();
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: _AbActionChip(
                      label: 'B',
                      semanticLabel: ab.pointB != null
                          ? l10n.abLoopPointB(labelB)
                          : l10n.abLoopSetB,
                      isActive: ab.pointB != null,
                      activeColor: activeColor,
                      onTap: () {
                        PulsrHaptics.selection();
                        cubit.setAbPointB();
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: _AbActionChip(
                      label: l10n.repeat,
                      semanticLabel: l10n.repeat,
                      isActive: ab.enabled,
                      enabled: canToggle,
                      activeColor: activeColor,
                      onTap: () {
                        PulsrHaptics.selection();
                        cubit.toggleAbLoop();
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Semantics(
                    button: true,
                    enabled: hasAnyPoint,
                    label: l10n.clearAbLoop,
                    excludeSemantics: true,
                    child: IconButton(
                      constraints: const BoxConstraints(
                        minWidth: AppSpacing.minTouchTarget,
                        minHeight: AppSpacing.minTouchTarget,
                      ),
                      tooltip: l10n.clearAbLoop,
                      icon: Icon(
                        Icons.close_rounded,
                        color: hasAnyPoint
                            ? p.textPrimary
                            : p.textSecondary.withValues(alpha: 0.4),
                      ),
                      onPressed: hasAnyPoint
                          ? () {
                              PulsrHaptics.selection();
                              cubit.clearAbLoop();
                            }
                          : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AbTimePill extends StatelessWidget {
  final String tag;
  final String timeText;
  final bool isActive;
  final Color activeColor;

  const _AbTimePill({
    required this.tag,
    required this.timeText,
    required this.isActive,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.s2,
      ),
      decoration: BoxDecoration(
        color: isActive
            ? activeColor.withValues(alpha: 0.16)
            : p.surfaceContainerHigh.withValues(alpha: 0.7),
        borderRadius: AppRadii.r8All,
        border: Border.all(
          color: isActive ? activeColor.withValues(alpha: 0.45) : p.hairline,
        ),
      ),
      child: Text(
        '$tag $timeText',
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: AppFontSize.caption,
          fontWeight: FontWeight.w700,
          color: isActive ? activeColor : p.textSecondary,
        ),
      ),
    );
  }
}

class _AbActionChip extends StatelessWidget {
  final String label;
  final String semanticLabel;
  final bool isActive;
  final bool enabled;
  final Color activeColor;
  final VoidCallback onTap;

  const _AbActionChip({
    required this.label,
    required this.semanticLabel,
    required this.isActive,
    required this.activeColor,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bg = isActive
        ? activeColor
        : p.surfaceContainerHigh.withValues(alpha: enabled ? 0.85 : 0.45);
    final fg = isActive
        ? _readableOnColor(activeColor)
        : (enabled ? p.textPrimary : p.textSecondary.withValues(alpha: 0.45));

    return Semantics(
      button: true,
      toggled: isActive,
      enabled: enabled,
      label: semanticLabel,
      excludeSemantics: true,
      child: Material(
        color: bg,
        borderRadius: AppRadii.r12All,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: AppSpacing.minTouchTarget,
              minHeight: AppSpacing.minTouchTarget,
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppFontSize.label,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PartyAwareMoreTile extends StatelessWidget {
  final PlayerThemeProps props;
  final Color activeColor;
  final Color dividerColor;
  final VoidCallback onTap;

  const _PartyAwareMoreTile({
    required this.props,
    required this.activeColor,
    required this.dividerColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    ListenTogetherService? partyService;
    try {
      if (getIt.isRegistered<ListenTogetherService>()) {
        partyService = getIt<ListenTogetherService>();
      }
    } catch (_) {
      partyService = null;
    }

    if (partyService == null) {
      return _ToolActionTile(
        icon: Icons.apps_rounded,
        iconColor: activeColor,
        title: l10n.moreOptions,
        subtitle: l10n.partyListenTogether,
        onTap: onTap,
      );
    }

    return ValueListenableBuilder<PartyConnectionState>(
      valueListenable: partyService.connectionState,
      builder: (context, connState, _) {
        final isLive = connState == PartyConnectionState.live;
        final isConnecting = connState == PartyConnectionState.connecting;
        return _ToolActionTile(
          icon: Icons.apps_rounded,
          iconColor: isLive ? context.palette.info : activeColor,
          title: l10n.moreOptions,
          subtitle: l10n.partyListenTogether,
          badgeText: isLive ? 'LIVE' : (isConnecting ? '...' : null),
          isActive: isLive || isConnecting,
          onTap: onTap,
        );
      },
    );
  }
}

class _ToolActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final String? badgeText;
  final bool isActive;
  final VoidCallback onTap;

  const _ToolActionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.badgeText,
    this.isActive = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: AppRadii.r16All,
          border: Border.all(
            color: isActive
                ? iconColor.withValues(alpha: 0.35)
                : (p.isHighContrast ? p.borderStrong : p.hairline),
          ),
        ),
        child: PulsrListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: isActive ? 0.22 : 0.12),
              borderRadius: AppRadii.r12All,
              border: Border.all(
                color: iconColor.withValues(alpha: isActive ? 0.45 : 0.22),
              ),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 20, color: iconColor),
          ),
          title: title,
          subtitle: subtitle,
          tileColor: isActive
              ? Color.alphaBlend(
                  iconColor.withValues(alpha: p.isDark ? 0.08 : 0.05),
                  p.surfaceContainer.withValues(alpha: 0.78),
                )
              : p.surfaceContainer.withValues(alpha: 0.55),
          onTap: onTap,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (badgeText != null && badgeText!.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.s2,
                  ),
                  decoration: BoxDecoration(
                    color: iconColor,
                    borderRadius: AppRadii.r8All,
                  ),
                  child: Text(
                    badgeText!,
                    style: TextStyle(
                      fontSize: AppFontSize.caption,
                      fontWeight: FontWeight.w800,
                      color: _readableOnColor(iconColor),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
              ] else if (isActive) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: iconColor,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: isActive ? iconColor : p.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact >= 48dp trigger button that opens [PlayerToolsSheet] and displays
/// an active indicator dot/count whenever any secondary tool is active.
class PlayerToolsTriggerButton extends StatelessWidget {
  final PlayerThemeProps props;
  final IconData icon;
  final Color? iconColor;
  final Color? backgroundColor;
  final Color? borderColor;
  final double iconSize;

  const PlayerToolsTriggerButton({
    super.key,
    required this.props,
    this.icon = Icons.tune_rounded,
    this.iconColor,
    this.backgroundColor,
    this.borderColor,
    this.iconSize = 22,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final settings = context.watch<SettingsCubit>().state;
    final activeCount = countActiveSecondaryTools(props.state, settings);
    final isActive = activeCount > 0;
    final fg = iconColor ?? (isActive ? props.activeColor : p.textPrimary);

    return Semantics(
      button: true,
      toggled: isActive,
      label: context.l10n.moreOptions,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: AppSpacing.minTouchTarget,
          minHeight: AppSpacing.minTouchTarget,
        ),
        child: Material(
          color: backgroundColor ?? Colors.transparent,
          shape: CircleBorder(
            side: borderColor != null
                ? BorderSide(color: borderColor!)
                : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              PulsrHaptics.lightImpact();
              PlayerToolsSheet.show(context, props: props);
            },
            child: Center(
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Icon(icon, size: iconSize, color: fg),
                  if (isActive)
                    PositionedDirectional(
                      top: -5,
                      end: -7,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: props.activeColor,
                          borderRadius: AppRadii.r8All,
                        ),
                        child: Text(
                          '$activeCount',
                          style: TextStyle(
                            fontSize: AppFontSize.caption,
                            fontWeight: FontWeight.w800,
                            color: _readableOnColor(props.activeColor),
                            height: 1.0,
                          ),
                        ),
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
