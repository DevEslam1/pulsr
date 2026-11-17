part of '../clean_player_theme.dart';

/// Down bar matching the reference photo, loaded with all dock features:
/// Lyrics, Equalizer, Speed, Output / Cast, Quran, Ambient, Timer, Queue.
class _CleanDownBar extends StatelessWidget {
  final PlayerThemeProps props;
  final Color activeColor;
  final double horizontalPadding;

  const _CleanDownBar({
    required this.props,
    required this.activeColor,
    this.horizontalPadding = 24.0,
  });

  @override
  Widget build(BuildContext context) {
    final state = props.state;
    final cubit = props.cubit;
    final outputDevice = context.select<SettingsCubit, AudioOutputInfo?>(
      (c) => c.state.currentOutputDevice,
    );
    final isInSplit = PlayerSplitViewScope.of(context);
    final splitTabCtrl = PlayerSplitViewScope.tabControllerOf(context);

    final isUsb = outputDevice?.isUsb == true;
    final IconData deviceOutputIcon = outputDevice == null
        ? Icons.airplay_rounded
        : (outputDevice.isUsb
            ? Icons.usb_rounded
            : (outputDevice.isBt
                ? Icons.bluetooth_audio_rounded
                : (outputDevice.isSpeaker
                    ? Icons.speaker_rounded
                    : (outputDevice.isHeadphones
                        ? Icons.headphones_rounded
                        : Icons.airplay_rounded))));

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
    final isEqActive = state.isEqEnabled;
    final speed = state.playbackSpeed;

    Widget buildBar(BuildContext context) {
      final bool isLyricsActive =
          isInSplit ? (splitTabCtrl?.index == 0) : state.isLyricsVisible;
      final bool isQueueActive =
          isInSplit ? (splitTabCtrl?.index == 1) : state.isQueueVisible;

      return Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 1. Lyrics Button (Left)
                    _DownBarItem(
                      icon: isLyricsActive
                          ? Icons.chat_bubble_rounded
                          : Icons.chat_bubble_outline_rounded,
                      isActive: isLyricsActive,
                      activeColor: activeColor,
                      tooltip: context.l10n.lyrics,
                      onTap: () {
                        PulsrHaptics.selection();
                        if (isInSplit && splitTabCtrl != null) {
                          splitTabCtrl.animateTo(0);
                        } else {
                          cubit.toggleLyricsVisibility();
                        }
                      },
                    ),
                    const SizedBox(width: 4),

                    // 2. Equalizer & DSP Button
                    _DownBarItem(
                      icon: Icons.tune_rounded,
                      isActive: isEqActive,
                      activeColor: activeColor,
                      tooltip: context.l10n.equalizer,
                      onTap: () {
                        PulsrHaptics.lightImpact();
                        EqualizerSheet.show(context);
                      },
                    ),
                    const SizedBox(width: 4),

                    // 3. Playback Speed Button
                    _DownBarItem(
                      icon: Icons.speed_rounded,
                      isActive: speed != 1.0,
                      badgeText:
                          speed != 1.0 ? '${speed.toStringAsFixed(1)}x' : null,
                      activeColor: activeColor,
                      tooltip: context.l10n.playbackSpeed,
                      onTap: () {
                        PulsrHaptics.lightImpact();
                        SpeedPickerSheet.show(context);
                      },
                    ),
                    const SizedBox(width: 4),

                    // 4. Audio Output / Cast / AirPlay Button
                    // AUDIT-FIX (P3-24): Listen reactively to CastService so
                    // CAST badge and icon update immediately on session changes.
                    ValueListenableBuilder<CastSessionStatus>(
                      valueListenable: CastService().sessionStatusListenable,
                      builder: (context, castStatus, _) {
                        final isCast = castStatus.connected;
                        return _DownBarItem(
                          icon: isCast
                              ? Icons.cast_connected_rounded
                              : deviceOutputIcon,
                          isActive: isCast || isUsb,
                          badgeText: isCast ? 'CAST' : (isUsb ? 'DAC' : null),
                          activeColor: isCast
                              ? AppColors.accentCyan
                              : (isUsb ? AppColors.dacGold : activeColor),
                          tooltip: isCast
                              ? context.l10n.googleCast
                              : context.l10n.audioOutputAndDac,
                          onTap: () {
                            PulsrHaptics.lightImpact();
                            if (state.currentSong != null) {
                              AudioQualitySheet.show(
                                  context, state.currentSong!, activeColor);
                            }
                          },
                        );
                      },
                    ),
                    const SizedBox(width: 4),

                    // 5. Quran Mode Button
                    _DownBarItem(
                      icon: Icons.auto_stories_rounded,
                      isActive: state.isQuranModeEnabled,
                      activeColor: AppColors.quranEmerald,
                      tooltip: context.l10n.quranMode,
                      onTap: () {
                        PulsrHaptics.lightImpact();
                        QuranModeSheet.show(context);
                      },
                    ),
                    const SizedBox(width: 4),

                    // 6. Ambient Sounds Button
                    AnimatedBuilder(
                      animation: AmbientSoundService(),
                      builder: (context, _) {
                        final isAmbientActive = AmbientSoundService().isEnabled;
                        return _DownBarItem(
                          icon: Icons.water_drop_rounded,
                          isActive: isAmbientActive,
                          activeColor: activeColor,
                          tooltip: context.l10n.ambientSounds,
                          onTap: () {
                            PulsrHaptics.lightImpact();
                            AmbientSoundSheet.show(context);
                          },
                        );
                      },
                    ),
                    const SizedBox(width: 4),

                    // 7. Sleep Timer Button
                    _DownBarItem(
                      icon: Icons.timer_outlined,
                      isActive: hasTimer,
                      badgeText: hasTimer
                          ? (remainingTracks != null
                              ? '$remainingTracks tr'
                              : (isEndQ
                                  ? 'End'
                                  : (state.sleepTimerRemaining != null
                                      ? formatSleepTimerRemaining(
                                          state.sleepTimerRemaining!)
                                      : '')))
                          : null,
                      activeColor: activeColor,
                      tooltip: isEndQ
                          ? 'Sleep Timer: End of Queue'
                          : (remainingTracks != null
                              ? 'Sleep Timer: $remainingTracks tracks remaining'
                              : (state.sleepTimerRemaining != null
                                  ? 'Sleep Timer: ${formatSleepTimerRemaining(state.sleepTimerRemaining!)} remaining'
                                  : context.l10n.sleepTimer)),
                      onTap: () {
                        PulsrHaptics.lightImpact();
                        SleepTimerSheet.show(context);
                      },
                    ),
                    const SizedBox(width: 4),

                    // 8. Queue / Playlist Button (Right)
                    _DownBarItem(
                      icon: Icons.format_list_bulleted_rounded,
                      isActive: isQueueActive,
                      badgeText: state.queue.isNotEmpty
                          ? '${state.queue.length}'
                          : null,
                      activeColor: activeColor,
                      tooltip: context.l10n.queue,
                      onTap: () {
                        PulsrHaptics.selection();
                        if (isInSplit && splitTabCtrl != null) {
                          splitTabCtrl.animateTo(1);
                        } else {
                          cubit.toggleQueueVisibility();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (isInSplit && splitTabCtrl != null) {
      return AnimatedBuilder(
        animation: splitTabCtrl.animation ?? splitTabCtrl,
        builder: (context, _) => buildBar(context),
      );
    }
    return buildBar(context);
  }
}

/// A single dock affordance: frosted active pill, palette-driven idle glyph.
///
/// The chip stays compact, but the row reserves [AppSpacing.minTouchTarget] of
/// height for the tap area so the dock meets the 48 dp minimum without
/// inflating eight visible pills.
class _DownBarItem extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final Color? activeColor;
  final String? badgeText;
  final String tooltip;
  final VoidCallback onTap;

  const _DownBarItem({
    required this.icon,
    required this.isActive,
    this.activeColor,
    this.badgeText,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final deck = _CleanDeckColors.of(context);
    final resolvedColor = activeColor ?? deck.primary;
    return Material(
      color: Colors.transparent,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppSpacing.minTouchTarget,
            ),
            child: Center(
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  AnimatedContainer(
                    duration: context.motionMs(200),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: isActive
                          ? resolvedColor.withValues(alpha: 0.22)
                          : Colors.transparent,
                      border: isActive
                          ? Border.all(
                              color: resolvedColor.withValues(alpha: 0.40),
                              width: 1.0,
                            )
                          : null,
                    ),
                    child: Icon(
                      icon,
                      size: 20,
                      color: isActive ? resolvedColor : deck.secondary,
                    ),
                  ),
                  if (badgeText != null && badgeText!.isNotEmpty)
                    PositionedDirectional(
                      top: -2,
                      end: -2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4.0,
                          vertical: 1.0,
                        ),
                        decoration: BoxDecoration(
                          color: resolvedColor,
                          borderRadius: BorderRadius.circular(6.0),
                        ),
                        child: Text(
                          badgeText!,
                          style: TextStyle(
                            fontSize: AppFontSize.caption,
                            fontWeight: FontWeight.w800,
                            color: resolvedColor.computeLuminance() > 0.4
                                ? Colors.black
                                : Colors.white,
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
