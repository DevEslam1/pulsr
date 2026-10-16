import 'package:flutter/material.dart';
import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';
import '../constants/app_typography.dart';
import '../motion/pulsr_motion.dart';
import '../theme/aura_theme.dart';
import 'pulsr_pressable.dart';

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
  final double height;

  const PulsrChip({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.selected = false,
    this.variant = PulsrChipVariant.filter,
    this.onDeleted,
    this.activeColor,
    this.height = 36.0,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final effectiveAccent = activeColor ?? p.accent;

    final bgColor = selected
        ? (variant == PulsrChipVariant.action ? effectiveAccent : p.accentSoft)
        : p.surfaceContainer;

    final borderColor = selected ? effectiveAccent : p.borderSubtle;

    final textColor = selected
        ? (variant == PulsrChipVariant.action
            ? p.textOnAccent
            : effectiveAccent)
        : p.textSecondary;

    final iconColor = textColor;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: PulsrPressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: context.motion(PulsrMotion.fast),
          curve: Curves.easeOutCubic,
          height: height,
          constraints: const BoxConstraints(minWidth: 44),
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: (height - 20) / 2,
          ),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: AppRadii.full,
            border: Border.all(
              color: borderColor,
              width: selected ? 1.4 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 16.0,
                  color: iconColor,
                ),
                const SizedBox(width: AppSpacing.xs),
              ] else if (selected && variant == PulsrChipVariant.filter) ...[
                Icon(
                  Icons.check_rounded,
                  size: 15.0,
                  color: iconColor,
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: AppFontSize.label,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  letterSpacing: AppTracking.label,
                  color: textColor,
                  height: 1.1,
                ),
              ),
              if (onDeleted != null) ...[
                const SizedBox(width: AppSpacing.xs),
                GestureDetector(
                  onTap: onDeleted,
                  child: Icon(
                    Icons.close_rounded,
                    size: 14.0,
                    color: textColor.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
