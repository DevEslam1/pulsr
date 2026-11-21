// lib/features/player/presentation/widgets/mini_player/mini_player_error_bar.dart
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

import '../../../../../core/motion/pulsr_motion.dart';
import '../../../../../core/theme/aura_theme.dart';
import '../../../../../core/utils/error_logger.dart';
import '../../../../../core/utils/l10n_extensions.dart';
import '../../../../../core/utils/pulsr_haptics.dart';
import '../../../../settings/cubit/settings_state.dart';
import '../../../cubit/player_cubit.dart';

/// Shared swipe-action icon & execution helper for [MiniPlayer].
abstract final class MiniPlayerSwipeActions {
  static const Duration latchTimeout = Duration(seconds: 10);

  static IconData? iconFor(
    MiniPlayerSwipeAction action, {
    required bool swipedLeft,
  }) {
    switch (action) {
      case MiniPlayerSwipeAction.next:
        return Icons.skip_next_rounded;
      case MiniPlayerSwipeAction.prev:
        return Icons.skip_previous_rounded;
      case MiniPlayerSwipeAction.volume:
        return swipedLeft ? Icons.volume_down_rounded : Icons.volume_up_rounded;
      case MiniPlayerSwipeAction.none:
        return null;
    }
  }

  static Future<void> execute(
    MiniPlayerSwipeAction action,
    PlayerCubit cubit, {
    required bool swipedLeft,
  }) async {
    try {
      switch (action) {
        case MiniPlayerSwipeAction.next:
          PulsrHaptics.selectionClick();
          await cubit.next().timeout(latchTimeout);
          break;
        case MiniPlayerSwipeAction.prev:
          PulsrHaptics.selectionClick();
          await cubit.previous().timeout(latchTimeout);
          break;
        case MiniPlayerSwipeAction.volume:
          PulsrHaptics.selectionClick();
          await cubit
              .adjustVolume(swipedLeft ? -0.05 : 0.05)
              .timeout(latchTimeout);
          break;
        case MiniPlayerSwipeAction.none:
          break;
      }
    } on TimeoutException catch (e, st) {
      ErrorLogger.log('MiniPlayer swipe action timed out',
          error: e, stackTrace: st, category: 'MiniPlayer');
    } catch (e, st) {
      ErrorLogger.log('MiniPlayer swipe action failed',
          error: e, stackTrace: st, category: 'MiniPlayer');
    }
  }
}

/// Visual directional badge shown during mini-player horizontal swipe gestures.
class MiniPlayerSwipeActionBadge extends StatelessWidget {
  final IconData icon;
  final double progress;
  final bool thresholdCrossed;
  final Color accentColor;

  const MiniPlayerSwipeActionBadge({
    super.key,
    required this.icon,
    required this.progress,
    required this.thresholdCrossed,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final motion = PulsrMotion.shouldAnimate(context);
    final badge = ExcludeSemantics(
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: thresholdCrossed
              ? accentColor.withValues(alpha: 0.18)
              : p.surfaceContainerHigh.withValues(alpha: 0.85),
          border: Border.all(
            color: thresholdCrossed
                ? accentColor.withValues(alpha: 0.45)
                : p.hairline,
          ),
        ),
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 17,
          color: thresholdCrossed ? accentColor : p.textSecondary,
        ),
      ),
    );

    if (!motion) {
      return Opacity(
        opacity: progress > 0 ? 1.0 : 0.0,
        child: badge,
      );
    }

    return Opacity(
      opacity: progress,
      child: Transform.scale(
        scale: thresholdCrossed ? 1.12 : 0.92,
        child: badge,
      ),
    );
  }
}

/// Full-width error state for the mini player. Replaces the track row so retry
/// and dismiss both have 48dp touch targets and announce via a live region.
class MiniPlayerErrorBar extends StatelessWidget {
  final String message;
  final Color accentColor;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  const MiniPlayerErrorBar({
    super.key,
    required this.message,
    required this.accentColor,
    required this.onRetry,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      container: true,
      liveRegion: true,
      label: message,
      child: Material(
        color: Color.alphaBlend(
          p.error.withValues(alpha: p.isDark ? 0.12 : 0.08),
          p.surfaceContainerHigh,
        ),
        borderRadius: AppRadii.r18All,
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Container(
            padding: const EdgeInsetsDirectional.only(
              start: AppSpacing.s10,
              end: AppSpacing.xxs,
              top: AppSpacing.xxs,
              bottom: AppSpacing.xxs,
            ),
            decoration: BoxDecoration(
              borderRadius: AppRadii.r18All,
              border: Border.all(color: p.error.withValues(alpha: 0.45)),
            ),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: p.error.withValues(alpha: 0.16),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.error_outline_rounded,
                      size: 17,
                      color: p.error,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: p.textPrimary,
                      fontSize: AppFontSize.label,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: context.l10n.retry,
                  onPressed: onRetry,
                  constraints: const BoxConstraints(
                    minWidth: AppSpacing.minTouchTarget,
                    minHeight: AppSpacing.minTouchTarget,
                  ),
                  iconSize: 19,
                  color: accentColor,
                  icon: const Icon(Icons.refresh_rounded),
                ),
                IconButton(
                  tooltip: context.l10n.close,
                  onPressed: onDismiss,
                  constraints: const BoxConstraints(
                    minWidth: AppSpacing.minTouchTarget,
                    minHeight: AppSpacing.minTouchTarget,
                  ),
                  iconSize: 19,
                  color: p.textSecondary,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
