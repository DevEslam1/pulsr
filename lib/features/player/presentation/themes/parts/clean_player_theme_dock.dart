part of '../clean_player_theme.dart';

/// Minimal Apple Music-inspired bottom action row:
/// **Lyrics**, **Output / DSP** (reactive to Cast/USB DAC), **Queue**, and
/// [PlayerToolsTriggerButton] (housing A/B loop & secondary tools).
class _CleanDownBar extends StatelessWidget {
  final PlayerThemeProps props;
  final Color activeColor;
  final double horizontalPadding;
  final bool isPreview;

  const _CleanDownBar({
    required this.props,
    required this.activeColor,
    this.horizontalPadding = 24.0,
    this.isPreview = false,
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
    final deck = _CleanDeckColors.of(context);

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

    Widget buildRow(BuildContext context) {
      final bool isLyricsActive = !isPreview &&
          (isInSplit ? (splitTabCtrl?.index == 0) : state.isLyricsVisible);
      final bool isQueueActive = !isPreview &&
          (isInSplit ? (splitTabCtrl?.index == 1) : state.isQueueVisible);

      return Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // 1. Lyrics
                _CleanBottomActionItem(
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

                // 2. Output / DSP (reactive to Cast & USB DAC)
                ValueListenableBuilder<CastSessionStatus>(
                  valueListenable: CastService().sessionStatusListenable,
                  builder: (context, castStatus, _) {
                    final isCast = castStatus.connected;
                    return _CleanBottomActionItem(
                      icon: isCast
                          ? Icons.cast_connected_rounded
                          : deviceOutputIcon,
                      isActive: isCast || isUsb,
                      badgeText: isCast ? 'CAST' : (isUsb ? 'DAC' : null),
                      activeColor: isCast
                          ? context.palette.info
                          : (isUsb ? context.palette.goldAccent : activeColor),
                      tooltip: isCast
                          ? context.l10n.googleCast
                          : context.l10n.audioOutputAndDac,
                      onTap: () {
                        PulsrHaptics.lightImpact();
                        if (state.currentSong != null) {
                          AudioQualitySheet.show(
                            context,
                            state.currentSong!,
                            activeColor,
                          );
                        } else {
                          EqualizerSheet.show(context);
                        }
                      },
                    );
                  },
                ),

                // 3. Queue
                _CleanBottomActionItem(
                  icon: Icons.format_list_bulleted_rounded,
                  isActive: isQueueActive,
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

                // 4. Secondary Tools (A/B loop + EQ/Speed/Quran/Ambient/Timer/More)
                PlayerToolsTriggerButton(
                  props: props,
                  icon: Icons.tune_rounded,
                  iconColor: deck.secondary,
                  iconSize: 22,
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (isInSplit && splitTabCtrl != null) {
      return AnimatedBuilder(
        animation: splitTabCtrl.animation ?? splitTabCtrl,
        builder: (context, _) => buildRow(context),
      );
    }
    return buildRow(context);
  }
}

/// Accessible >= 48dp bottom action item with soft active pill tint and
/// optional status badge (`CAST` / `DAC`).
class _CleanBottomActionItem extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final Color activeColor;
  final String? badgeText;
  final String tooltip;
  final VoidCallback onTap;

  const _CleanBottomActionItem({
    required this.icon,
    required this.isActive,
    required this.activeColor,
    this.badgeText,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final deck = _CleanDeckColors.of(context);
    return Semantics(
      button: true,
      toggled: isActive,
      label: tooltip,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: Tooltip(
          message: tooltip,
          child: InkWell(
            onTap: onTap,
            borderRadius: AppRadii.r14All,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: AppSpacing.minTouchTarget,
                minHeight: AppSpacing.minTouchTarget,
              ),
              child: Center(
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    AnimatedContainer(
                      duration: context.motionMs(200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s12,
                        vertical: AppSpacing.s8,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: AppRadii.r14All,
                        color: isActive
                            ? activeColor.withValues(alpha: 0.20)
                            : Colors.transparent,
                        border: isActive
                            ? Border.all(
                                color: activeColor.withValues(alpha: 0.36),
                                width: 1.0,
                              )
                            : null,
                      ),
                      child: Icon(
                        icon,
                        size: 22,
                        color: isActive ? activeColor : deck.secondary,
                      ),
                    ),
                    if (badgeText != null && badgeText!.isNotEmpty)
                      PositionedDirectional(
                        top: -2,
                        end: -4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.s4,
                            vertical: 1.0,
                          ),
                          decoration: BoxDecoration(
                            color: activeColor,
                            borderRadius: AppRadii.r6All,
                          ),
                          child: Text(
                            badgeText!,
                            style: TextStyle(
                              fontSize: AppFontSize.caption,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textOnAccent(activeColor),
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
      ),
    );
  }
}
