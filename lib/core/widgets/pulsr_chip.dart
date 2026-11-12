// lib/core/widgets/pulsr_chip.dart
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';
import '../constants/app_typography.dart';
import '../motion/pulsr_motion.dart';
import '../theme/aura_theme.dart';
import '../theme/pulsr_button_style.dart';
import 'pulsr_pressable.dart';

import '../utils/pulsr_haptics.dart';
/// {@category DesignSystem}
enum PulsrChipVariant {
  /// Filter toggle chips (shows check/dot when selected).
  filter,

  /// Action trigger chips (tappable shortcut).
  action,

  /// Suggestion / discovery pills (e.g. search suggestions, genres).
  suggestion,
}

/// Unified chip and tag component for Pulsr.
class PulsrChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;
  final PulsrChipVariant variant;
  final VoidCallback? onDeleted;
  final Color? activeColor;

  const PulsrChip({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.selected = false,
    this.variant = PulsrChipVariant.filter,
    this.onDeleted,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isCapsule = context.isCapsuleButtons;
    final effectiveAccent = activeColor ?? p.accent;
    final isActionSelected = selected && variant == PulsrChipVariant.action;

    final Color bgColor = selected
        ? (isActionSelected
            ? effectiveAccent
            : (isCapsule
                ? effectiveAccent.withValues(alpha: p.isDark ? 0.32 : 0.22)
                : p.accentSoft))
        : (isCapsule
            ? PulsrCapsuleStyle.backgroundColor(p)
            : p.surfaceContainer);

    final Color borderColor = selected
        ? (isActionSelected
            ? effectiveAccent
            : effectiveAccent.withValues(alpha: 0.55))
        : (isCapsule
            ? (p.isDark
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.black.withValues(alpha: 0.08))
            : (p.isDark ? AppColors.specularAt(0.12) : p.borderSubtle));

    final Color textColor = selected
        ? (isActionSelected
            ? p.textOnAccent
            : (isCapsule
                ? (p.isDark ? Colors.white : effectiveAccent)
                : effectiveAccent))
        : (isCapsule ? PulsrCapsuleStyle.foregroundColor(p) : p.textSecondary);

    final Color iconColor = textColor;
    final bool showLeadingIcon =
        icon != null || (selected && variant == PulsrChipVariant.filter);
    final Widget leadingSlot = showLeadingIcon
        ? Padding(
            padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
            child: Icon(
              icon ?? Icons.check_rounded,
              size: icon != null ? 16.0 : 15.0,
              color: iconColor,
            ),
          )
        : const SizedBox.shrink();

    final chipRadius = isCapsule
        ? context.buttonRadius(rectRadius: 6.0)
        : AppRadii.full;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: PulsrPressable(
        onTap: onTap,
        hapticStyle: PulsrHapticStyle.selection,
        focusBorderRadius: chipRadius,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppSpacing.minTouchTarget,
          ),
          child: Center(
            widthFactor: 1.0,
            child: AnimatedContainer(
              duration: context.motion(PulsrDurations.tap),
              curve: context.motionCurve(PulsrMotion.enter),
              constraints: const BoxConstraints(minWidth: 44, minHeight: 36),
              padding: EdgeInsetsDirectional.only(
                start: AppSpacing.sm,
                end: onDeleted != null ? AppSpacing.xs : AppSpacing.sm,
                top: AppSpacing.xs,
                bottom: AppSpacing.xs,
              ),
              decoration: isCapsule && !selected
                  ? PulsrCapsuleStyle.decoration(
                      p,
                      customBg: bgColor,
                      borderRadius: chipRadius,
                      customBorder: Border.all(color: borderColor, width: 0.8),
                    )
                  : BoxDecoration(
                      color: selected ? null : bgColor,
                      gradient: selected
                          ? LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: isActionSelected
                                  ? [
                                      Color.lerp(
                                            effectiveAccent,
                                            Colors.white,
                                            0.12,
                                          ) ??
                                          effectiveAccent,
                                      effectiveAccent,
                                    ]
                                  : [
                                      effectiveAccent.withValues(
                                        alpha: p.isDark
                                            ? (isCapsule ? 0.35 : 0.24)
                                            : (isCapsule ? 0.25 : 0.16),
                                      ),
                                      effectiveAccent.withValues(
                                        alpha: p.isDark
                                            ? (isCapsule ? 0.20 : 0.12)
                                            : (isCapsule ? 0.14 : 0.08),
                                      ),
                                    ],
                            )
                          : null,
                      borderRadius: chipRadius,
                      border: Border.all(
                        color: borderColor,
                        width: selected ? 1.3 : 1.0,
                      ),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color: effectiveAccent.withValues(
                                  alpha: isActionSelected ? 0.28 : 0.16,
                                ),
                                blurRadius: 12,
                                spreadRadius: -2,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // AnimatedSize with a collapsed (reduced-motion) duration
                  // re-dirties itself inside its own layout pass and trips the
                  // framework's mutation assertion, so animate only when motion
                  // is actually available.
                  if (context.motionEnabled)
                    AnimatedSize(
                      duration: context.motionMs(180),
                      curve: Curves.easeOutCubic,
                      child: leadingSlot,
                    )
                  else
                    leadingSlot,
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: AppFontSize.label,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w600,
                        letterSpacing: AppTracking.label,
                        color: textColor,
                        height: 1.1,
                      ),
                    ),
                  ),
                  if (onDeleted != null) ...[
                    const SizedBox(width: AppSpacing.xs),
                    Semantics(
                      button: true,
                      label:
                          MaterialLocalizations.of(context).deleteButtonTooltip,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          PulsrHaptics.selectionClick();
                          onDeleted!();
                        },
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: textColor.withValues(alpha: 0.12),
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            size: 13.5,
                            color: textColor.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
