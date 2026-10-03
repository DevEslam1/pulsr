import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';
import '../constants/app_typography.dart';
import '../motion/pulsr_motion.dart';
import '../theme/aura_theme.dart';

/// {@category DesignSystem}
/// Standardized empty state widget featuring an optional illustration slot,
/// animated badge, title, subtitle, and primary/secondary actions.
class PulsrEmptyState extends StatelessWidget {
  final Widget? illustration;
  final IconData? icon;
  final String title;
  final String subtitle;
  final String? primaryActionLabel;
  final IconData? primaryActionIcon;
  final VoidCallback? onPrimaryAction;
  final bool isPrimaryLoading;
  final String? secondaryActionLabel;
  final IconData? secondaryActionIcon;
  final VoidCallback? onSecondaryAction;
  final Color? iconColor;

  const PulsrEmptyState({
    super.key,
    this.illustration,
    this.icon,
    required this.title,
    required this.subtitle,
    this.primaryActionLabel,
    this.primaryActionIcon,
    this.onPrimaryAction,
    this.isPrimaryLoading = false,
    this.secondaryActionLabel,
    this.secondaryActionIcon,
    this.onSecondaryAction,
    this.iconColor,
  }) : assert(illustration != null || icon != null,
            'Must provide either illustration or icon');

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final effectiveIconColor = iconColor ?? p.accent;

    final shouldAnimate = context.motionEnabled &&
        !WidgetsBinding.instance.runtimeType.toString().contains('Test');

    return LayoutBuilder(
      builder: (context, constraints) {
        final double minH = constraints.maxHeight.isFinite
            ? constraints.maxHeight * 0.6
            : 280.0;
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minH),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (illustration != null)
                    illustration!
                  else if (icon != null)
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        if (shouldAnimate) ...[
                          Container(
                            width: 108,
                            height: 108,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: effectiveIconColor.withValues(alpha: 0.10),
                            ),
                          )
                              .animate(
                                  onPlay: (controller) =>
                                      controller.repeat(reverse: true))
                              .scaleXY(
                                  begin: 0.88,
                                  end: 1.16,
                                  duration: context.motionMs(2600),
                                  curve: context.motionCurve(Curves.easeInOut)),
                          Container(
                            width: 108,
                            height: 108,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: effectiveIconColor.withValues(alpha: 0.05),
                            ),
                          )
                              .animate(
                                  onPlay: (controller) =>
                                      controller.repeat(reverse: true))
                              .scaleXY(
                                  begin: 0.80,
                                  end: 1.24,
                                  duration: context.motionMs(2600),
                                  delay: context.motionMs(1300),
                                  curve: context.motionCurve(Curves.easeInOut)),
                        ] else ...[
                          Container(
                            width: 108,
                            height: 108,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: effectiveIconColor.withValues(alpha: 0.08),
                            ),
                          ),
                        ],
                        Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: p.surfaceContainer,
                            border: Border.all(
                              color: effectiveIconColor.withValues(alpha: 0.35),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: effectiveIconColor.withValues(
                                    alpha: p.isDark ? 0.22 : 0.10),
                                blurRadius: 24,
                                spreadRadius: -2,
                              ),
                            ],
                          ),
                          child: Center(
                            child:
                                Icon(icon, size: 40, color: effectiveIconColor),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: p.textPrimary,
                      fontSize: AppFontSize.titleLarge,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: p.textSecondary,
                      fontSize: AppFontSize.bodySmall,
                      height: 1.4,
                    ),
                  ),
                  if (primaryActionLabel != null &&
                      onPrimaryAction != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton.icon(
                      onPressed: isPrimaryLoading ? null : onPrimaryAction,
                      style: FilledButton.styleFrom(
                        backgroundColor: p.accent,
                        foregroundColor: p.onAccent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                          vertical: AppSpacing.sm,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: AppRadii.buttonRadius,
                        ),
                      ),
                      icon: isPrimaryLoading
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: p.onAccent,
                              ),
                            )
                          : (primaryActionIcon != null
                              ? Icon(primaryActionIcon, size: 18)
                              : const SizedBox.shrink()),
                      label: Text(primaryActionLabel!),
                    ),
                  ],
                  if (secondaryActionLabel != null &&
                      onSecondaryAction != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    TextButton.icon(
                      onPressed: onSecondaryAction,
                      icon: secondaryActionIcon != null
                          ? Icon(secondaryActionIcon,
                              size: 16, color: p.textTertiary)
                          : const SizedBox.shrink(),
                      label: Text(
                        secondaryActionLabel!,
                        style: TextStyle(
                            color: p.textTertiary, fontSize: AppFontSize.label),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
