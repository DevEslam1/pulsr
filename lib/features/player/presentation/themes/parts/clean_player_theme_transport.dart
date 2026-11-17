part of '../clean_player_theme.dart';

/// Bare Apple Music transport controls with Shuffle & Repeat affordances.
///
/// Every glyph comes from [_CleanDeckColors]: the play/pause mark used to be a
/// hardcoded white and disappeared into the light deck. Each button keeps its
/// visual size but is padded to at least [AppSpacing.minTouchTarget].
class _CleanTransportControls extends StatelessWidget {
  final PlayerThemeProps props;
  final Color activeColor;
  final bool isCompact;

  const _CleanTransportControls({
    required this.props,
    required this.activeColor,
    this.isCompact = false,
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

    final deck = _CleanDeckColors.of(context);

    final double mainIconSize = isCompact ? 44.0 : 54.0;
    final double sideIconSize = isCompact ? 32.0 : 40.0;
    final double auxIconSize = isCompact ? 22.0 : 25.0;
    final double buttonGap = isCompact ? 10.0 : 18.0;

    BoxConstraints touchTarget(double visualSize) => BoxConstraints(
          minWidth: math.max(visualSize + 8, AppSpacing.minTouchTarget),
          minHeight: math.max(visualSize + 8, AppSpacing.minTouchTarget),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 1. Shuffle Button
            IconButton(
              iconSize: auxIconSize,
              padding: EdgeInsets.zero,
              constraints: touchTarget(auxIconSize),
              icon: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.shuffle_rounded,
                    color: isShuffle ? activeColor : deck.secondary,
                  ),
                  if (isShuffle)
                    Positioned(
                      bottom: 0,
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
              tooltip: context.l10n.shuffle,
              onPressed: () {
                PulsrHaptics.selection();
                cubit.toggleShuffle();
              },
            ),
            SizedBox(width: buttonGap),

            // 2. Previous / Rewind Button
            IconButton(
              iconSize: sideIconSize,
              padding: EdgeInsets.zero,
              constraints: touchTarget(sideIconSize),
              icon: const Icon(Icons.fast_rewind_rounded),
              color: deck.primary,
              disabledColor: deck.tertiary,
              tooltip: context.l10n.previous,
              onPressed: hasPrev
                  ? () {
                      PulsrHaptics.selection();
                      cubit.previous();
                    }
                  : null,
            ),
            SizedBox(width: buttonGap),

            // 3. Play / Pause Button
            IconButton(
              iconSize: mainIconSize,
              padding: EdgeInsets.zero,
              constraints: touchTarget(mainIconSize),
              icon: isBuffering
                  ? SizedBox(
                      width: isCompact ? 24 : 32,
                      height: isCompact ? 24 : 32,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: deck.primary,
                      ),
                    )
                  : Icon(
                      isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: deck.primary,
                    ),
              tooltip: isPlaying ? context.l10n.pause : context.l10n.play,
              onPressed: () {
                PulsrHaptics.light();
                cubit.togglePlayPause();
              },
            ),
            SizedBox(width: buttonGap),

            // 4. Next / Fast-Forward Button
            IconButton(
              iconSize: sideIconSize,
              padding: EdgeInsets.zero,
              constraints: touchTarget(sideIconSize),
              icon: const Icon(Icons.fast_forward_rounded),
              color: deck.primary,
              disabledColor: deck.tertiary,
              tooltip: context.l10n.next,
              onPressed: hasNext
                  ? () {
                      PulsrHaptics.selection();
                      cubit.next();
                    }
                  : null,
            ),
            SizedBox(width: buttonGap),

            // 5. Repeat Button
            IconButton(
              iconSize: auxIconSize,
              padding: EdgeInsets.zero,
              constraints: touchTarget(auxIconSize),
              icon: Stack(
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
                      bottom: 0,
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
              tooltip: context.l10n.repeat,
              onPressed: () {
                PulsrHaptics.selection();
                cubit.toggleRepeat();
                final nextMode = switch (repeatMode) {
                  PlayerRepeatMode.off => PlayerRepeatMode.all,
                  PlayerRepeatMode.all => PlayerRepeatMode.one,
                  PlayerRepeatMode.one => PlayerRepeatMode.off,
                };
                final nextLabel = switch (nextMode) {
                  PlayerRepeatMode.one => context.l10n.repeatOne,
                  PlayerRepeatMode.all => context.l10n.repeatAll,
                  PlayerRepeatMode.off => context.l10n.repeatOff,
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
          ],
        ),
      ),
    );
  }
}
