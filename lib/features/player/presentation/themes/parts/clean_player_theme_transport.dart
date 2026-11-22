part of '../clean_player_theme.dart';

/// Clean borderless Apple Music-inspired transport controls.
///
/// Prominent Previous, Play/Pause, and Next focal controls flanked by subtle
/// borderless Shuffle and Repeat toggles — zero A/B loop clutter.
/// Every button enforces >= 48dp touch targets and localized button semantics.
class _CleanTransportControls extends StatelessWidget {
  final PlayerThemeProps props;
  final Color activeColor;
  final bool isCompact;
  final bool isPreview;

  const _CleanTransportControls({
    required this.props,
    required this.activeColor,
    this.isCompact = false,
    this.isPreview = false,
  });

  @override
  Widget build(BuildContext context) {
    final state = props.state;
    final cubit = props.cubit;
    final isPlaying = state.isPlaying;
    final isBuffering = state.isBuffering;
    final isShuffle = state.isShuffle;
    final repeatMode = state.repeatMode;
    final hasPrev = state.hasPreviousNeighbour;
    final hasNext = state.hasNextNeighbour;
    final l10n = context.l10n;
    final deck = _CleanDeckColors.of(context);

    final double mainIconSize = isCompact ? 46.0 : 56.0;
    final double sideIconSize = isCompact ? 34.0 : 42.0;
    final double auxIconSize = isCompact ? 22.0 : 24.0;
    final double buttonGap = isCompact ? 10.0 : 18.0;

    BoxConstraints touchTarget(double visualSize) => BoxConstraints(
          minWidth: math.max(visualSize + 8, AppSpacing.minTouchTarget),
          minHeight: math.max(visualSize + 8, AppSpacing.minTouchTarget),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 1. Shuffle (subtle borderless)
            Semantics(
              button: true,
              toggled: isShuffle,
              label: l10n.shuffle,
              excludeSemantics: true,
              child: IconButton(
                iconSize: auxIconSize,
                padding: EdgeInsets.zero,
                constraints: touchTarget(auxIconSize),
                tooltip: l10n.shuffle,
                icon: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      Icons.shuffle_rounded,
                      color: isShuffle ? activeColor : deck.secondary,
                    ),
                    if (isShuffle)
                      Positioned(
                        bottom: -6,
                        child: Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: activeColor,
                          ),
                        ),
                      ),
                  ],
                ),
                onPressed: () {
                  PulsrHaptics.selection();
                  cubit.toggleShuffle();
                },
              ),
            ),
            SizedBox(width: buttonGap),

            // 2. Previous
            Semantics(
              button: true,
              enabled: hasPrev,
              label: l10n.previous,
              excludeSemantics: true,
              child: IconButton(
                iconSize: sideIconSize,
                padding: EdgeInsets.zero,
                constraints: touchTarget(sideIconSize),
                icon: const Icon(Icons.fast_rewind_rounded),
                color: deck.primary,
                disabledColor: deck.tertiary,
                tooltip: l10n.previous,
                onPressed: hasPrev
                    ? () {
                        PulsrHaptics.selection();
                        cubit.previous();
                      }
                    : null,
              ),
            ),
            SizedBox(width: buttonGap),

            // 3. Play / Pause (focal borderless mark)
            Semantics(
              button: true,
              label: isPlaying ? l10n.pause : l10n.play,
              excludeSemantics: true,
              child: IconButton(
                iconSize: mainIconSize,
                padding: EdgeInsets.zero,
                constraints: touchTarget(mainIconSize),
                tooltip: isPlaying ? l10n.pause : l10n.play,
                icon: isBuffering && !isPreview
                    ? SizedBox(
                        width: isCompact ? 26 : 32,
                        height: isCompact ? 26 : 32,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: deck.primary,
                        ),
                      )
                    : AnimatedSwitcher(
                        duration: isPreview
                            ? Duration.zero
                            : context.motionMs(200),
                        transitionBuilder: (child, anim) => ScaleTransition(
                          scale: Tween<double>(begin: 0.82, end: 1.0)
                              .animate(anim),
                          child: FadeTransition(opacity: anim, child: child),
                        ),
                        child: Icon(
                          isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          key: ValueKey(isPlaying),
                          color: deck.primary,
                        ),
                      ),
                onPressed: () {
                  PulsrHaptics.light();
                  cubit.togglePlayPause();
                },
              ),
            ),
            SizedBox(width: buttonGap),

            // 4. Next
            Semantics(
              button: true,
              enabled: hasNext,
              label: l10n.next,
              excludeSemantics: true,
              child: IconButton(
                iconSize: sideIconSize,
                padding: EdgeInsets.zero,
                constraints: touchTarget(sideIconSize),
                icon: const Icon(Icons.fast_forward_rounded),
                color: deck.primary,
                disabledColor: deck.tertiary,
                tooltip: l10n.next,
                onPressed: hasNext
                    ? () {
                        PulsrHaptics.selection();
                        cubit.next();
                      }
                    : null,
              ),
            ),
            SizedBox(width: buttonGap),

            // 5. Repeat (subtle borderless)
            Semantics(
              button: true,
              toggled: repeatMode != PlayerRepeatMode.off,
              label: l10n.repeat,
              excludeSemantics: true,
              child: IconButton(
                iconSize: auxIconSize,
                padding: EdgeInsets.zero,
                constraints: touchTarget(auxIconSize),
                tooltip: l10n.repeat,
                icon: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      repeatMode == PlayerRepeatMode.one
                          ? Icons.repeat_one_rounded
                          : Icons.repeat_rounded,
                      color: repeatMode != PlayerRepeatMode.off
                          ? activeColor
                          : deck.secondary,
                    ),
                    if (repeatMode != PlayerRepeatMode.off)
                      Positioned(
                        bottom: -6,
                        child: Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: activeColor,
                          ),
                        ),
                      ),
                  ],
                ),
                onPressed: () {
                  PulsrHaptics.selection();
                  cubit.toggleRepeat();
                  final nextMode = switch (repeatMode) {
                    PlayerRepeatMode.off => PlayerRepeatMode.all,
                    PlayerRepeatMode.all => PlayerRepeatMode.one,
                    PlayerRepeatMode.one => PlayerRepeatMode.off,
                  };
                  final nextLabel = switch (nextMode) {
                    PlayerRepeatMode.one => l10n.repeatOne,
                    PlayerRepeatMode.all => l10n.repeatAll,
                    PlayerRepeatMode.off => l10n.repeatOff,
                  };
                  final nextIcon = switch (nextMode) {
                    PlayerRepeatMode.one => Icons.repeat_one_rounded,
                    PlayerRepeatMode.all => Icons.repeat_rounded,
                    PlayerRepeatMode.off => Icons.repeat_rounded,
                  };
                  PulsrToast.show(
                    context,
                    message: nextLabel,
                    icon: nextIcon,
                    duration: const Duration(milliseconds: 1200),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
