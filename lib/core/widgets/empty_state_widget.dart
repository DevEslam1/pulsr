// lib/core/widgets/empty_state_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../constants/app_radii.dart';
import '../motion/pulsr_motion.dart';
import '../theme/aura_theme.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

class EmptyStateWidget extends StatelessWidget {
  final IconData icon;
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

  const EmptyStateWidget({
    super.key,
    required this.icon,
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
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final effectiveIconColor = iconColor ?? p.accent;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Animated emblem: two phase-shifted pulse rings around a glass core.
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 108,
                  height: 108,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: effectiveIconColor.withValues(alpha: 0.10),
                  ),
                )
                    .animate(onPlay: (controller) {
                      if (context.motionEnabled) controller.repeat(reverse: true);
                    })
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
                    .animate(onPlay: (controller) {
                      if (context.motionEnabled) controller.repeat(reverse: true);
                    })
                    .scaleXY(
                        begin: 0.80,
                        end: 1.24,
                        duration: context.motionMs(2600),
                        delay: context.motionMs(1300),
                        curve: context.motionCurve(Curves.easeInOut)),

                // Inner Glass Circle Container
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
                        color: effectiveIconColor.withValues(alpha: 0.22),
                        blurRadius: 26,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      icon,
                      size: 40,
                      color: effectiveIconColor,
                    ),
                  ),
                ).animate().scale(
                    duration: context.motionMs(500),
                    curve: context.motionCurve(Curves.easeOutBack)),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            // Title
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: AppTracking.title,
                    fontSize: AppFontSize.titleLarge,
                  ),
            ).animate().fadeIn(delay: context.motionMs(150)).slideY(begin: 0.15, end: 0),
            const SizedBox(height: AppSpacing.xs),

            // Subtitle
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: p.textSecondary,
                  fontSize: AppFontSize.body,
                  height: 1.45,
                ),
              ),
            ).animate().fadeIn(delay: context.motionMs(250)).slideY(begin: 0.15, end: 0),

            if (primaryActionLabel != null && onPrimaryAction != null) ...[
              const SizedBox(height: AppSpacing.s28),
              SizedBox(
                height: 48,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: effectiveIconColor == p.error ? p.error : p.accent,
                    foregroundColor: p.onAccent,
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                    shape: RoundedRectangleBorder(
                        borderRadius: AppRadii.cardRadius),
                  ),
                  onPressed: isPrimaryLoading ? null : onPrimaryAction,
                  child: isPrimaryLoading
                      ? SizedBox(height: AppSpacing.s20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: p.onAccent,
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (primaryActionIcon != null) ...[
                              Icon(primaryActionIcon, size: 20),
                              const SizedBox(width: AppSpacing.xs),
                            ],
                            Text(
                              primaryActionLabel!,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: AppFontSize.body),
                            ),
                          ],
                        ),
                ),
              ).animate().fadeIn(delay: context.motionMs(350)).slideY(begin: 0.2, end: 0),
            ],

            if (secondaryActionLabel != null && onSecondaryAction != null) ...[
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: p.textPrimary,
                  side: BorderSide(color: p.hairline),
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.s20, vertical: AppSpacing.s10),
                  shape:
                      RoundedRectangleBorder(borderRadius: AppRadii.cardRadius),
                ),
                onPressed: onSecondaryAction,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (secondaryActionIcon != null) ...[
                      Icon(secondaryActionIcon,
                          size: 18, color: p.textSecondary),
                      const SizedBox(width: AppSpacing.xs),
                    ],
                    Text(
                      secondaryActionLabel!,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: AppFontSize.bodySmall),
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: context.motionMs(450)),
            ],
          ],
        ),
      ),
    );
  }
}
