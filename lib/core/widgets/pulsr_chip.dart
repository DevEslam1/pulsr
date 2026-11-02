// lib/core/widgets/pulsr_chip.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_colors.dart';
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
    final effectiveAccent = activeColor ?? p.accent;
    final isActionSelected = selected && variant == PulsrChipVariant.action;

    final Color bgColor = selected
        ? (isActionSelected ? effectiveAccent : p.accentSoft)
        : p.surfaceContainer;

    final Color borderColor = selected
        ? (isActionSelected
            ? effectiveAccent
            : effectiveAccent.withValues(alpha: 0.55))
        : (p.isDark ? AppColors.specularAt(0.12) : p.borderSubtle);

    final Color textColor = selected
        ? (isActionSelected ? p.textOnAccent : effectiveAccent)
        : p.textSecondary;

    final Color iconColor = textColor;
    final bool showLeadingIcon =
        icon != null || (selected && variant == PulsrChipVariant.filter);

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: PulsrPressable(
        onTap: onTap,
        hapticStyle: PulsrHapticStyle.selection,
        focusBorderRadius: AppRadii.full,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppSpacing.minTouchTarget,
          ),
          child: Center(
            widthFactor: 1.0,
            child: AnimatedContainer(
              duration: context.motion(PulsrDurations.tap),
              curve: Curves.easeOutCubic,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 36),
              padding: EdgeInsetsDirectional.only(
                start: AppSpacing.sm,
                end: onDeleted != null ? AppSpacing.xs : AppSpacing.sm,
                top: AppSpacing.xs,
                bottom: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
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
                                  alpha: p.isDark ? 0.24 : 0.16,
                                ),
                                effectiveAccent.withValues(
                                  alpha: p.isDark ? 0.12 : 0.08,
                                ),
                              ],
                      )
                    : null,
                borderRadius: AppRadii.full,
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
                  AnimatedSize(
                    duration: context.motionMs(180),
                    curve: Curves.easeOutCubic,
                    child: showLeadingIcon
                        ? Padding(
                            padding: const EdgeInsetsDirectional.only(
                              end: AppSpacing.xs,
                            ),
                            child: Icon(
                              icon ?? Icons.check_rounded,
                              size: icon != null ? 16.0 : 15.0,
                              color: iconColor,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
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
                          HapticFeedback.selectionClick();
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
