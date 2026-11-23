// lib/features/queue/presentation/widgets/queue_slot_switcher.dart
import 'package:material_ui/material_ui.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

import '../../../../core/motion/pulsr_motion.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/theme/pulsr_button_style.dart';
import '../../../../core/utils/l10n_extensions.dart';
import '../../../../core/utils/pulsr_haptics.dart';

/// Shared Q1 / Q2 / Q3 multi-queue slot switcher rendered identically across
/// [QueueScreen], [NowPlayingQueueView], and the tablet side inspector.
class QueueSlotSwitcher extends StatelessWidget {
  final int activeSlot;
  final ValueChanged<int> onSlotSelected;
  final int slotCount;

  const QueueSlotSwitcher({
    super.key,
    required this.activeSlot,
    required this.onSlotSelected,
    this.slotCount = 3,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l10n = context.l10n;
    final isCapsule = context.isCapsuleButtons;
    final queueRadius =
        isCapsule ? context.buttonRadius(rectRadius: 6.0) : AppRadii.r10All;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(slotCount, (slotIndex) {
        final isSelected = activeSlot == slotIndex;
        final label = l10n.queueSlotShort(slotIndex + 1);
        final tooltip = l10n.queueSlotTooltip(slotIndex + 1);

        return Padding(
          padding: EdgeInsetsDirectional.only(
            start: slotIndex == 0 ? 0 : AppSpacing.xxs,
          ),
          child: Semantics(
            button: true,
            selected: isSelected,
            label: '$label, $tooltip',
            excludeSemantics: true,
            child: Tooltip(
              message: tooltip,
              excludeFromSemantics: true,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: AppSpacing.minTouchTarget,
                  minHeight: AppSpacing.minTouchTarget,
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: () {
                      PulsrHaptics.selectionClick();
                      onSlotSelected(slotIndex);
                    },
                    borderRadius: queueRadius,
                    child: Center(
                      child: AnimatedContainer(
                        duration: context.motionMs(200),
                        padding: EdgeInsets.symmetric(
                          horizontal: isCapsule ? 10.0 : AppSpacing.sm,
                          vertical: isCapsule ? 4.0 : AppSpacing.s6,
                        ),
                        decoration: isCapsule
                            ? (isSelected
                                ? BoxDecoration(
                                    color: p.accent,
                                    borderRadius: queueRadius,
                                    border: Border.all(
                                      color: p.onAccent.withValues(alpha: 0.35),
                                      width: 0.8,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: p.accent.withValues(alpha: 0.3),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  )
                                : PulsrCapsuleStyle.decoration(
                                    p,
                                    borderRadius: queueRadius,
                                  ))
                            : BoxDecoration(
                                color: isSelected
                                    ? p.accent
                                    : p.surfaceContainerHigh,
                                borderRadius: AppRadii.r10All,
                                border: Border.all(
                                  color: isSelected ? p.accent : p.hairline,
                                ),
                              ),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: AppFontSize.label,
                            fontWeight: FontWeight.w800,
                            color: isSelected
                                ? p.onAccent
                                : (isCapsule
                                    ? PulsrCapsuleStyle.foregroundColor(p)
                                    : p.textSecondary),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// Compact read-only slot pill (`Q1`/`Q2`/`Q3`) shown on constrained chrome such
/// as the mini-player carousel so every entry point reflects the active slot.
class QueueSlotBadge extends StatelessWidget {
  final int activeSlot;

  const QueueSlotBadge({
    super.key,
    required this.activeSlot,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final slotNumber = activeSlot + 1;
    final label = context.l10n.queueSlotShort(slotNumber);

    return Semantics(
      label: context.l10n.queueSlotTooltip(slotNumber),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s6,
          vertical: 1,
        ),
        decoration: BoxDecoration(
          color: p.accent.withValues(alpha: 0.16),
          borderRadius: AppRadii.r6All,
          border: Border.all(
            color: p.accent.withValues(alpha: 0.35),
            width: 0.8,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: AppFontSize.caption,
            fontWeight: FontWeight.w800,
            color: p.accent,
            letterSpacing: AppTracking.medium,
          ),
        ),
      ),
    );
  }
}
