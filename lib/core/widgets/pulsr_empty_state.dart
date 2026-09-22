import 'package:flutter/material.dart';
import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';
import '../constants/app_typography.dart';
import '../theme/aura_theme.dart';

export 'empty_state_widget.dart';

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
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  const PulsrEmptyState({
    super.key,
    this.illustration,
    this.icon,
    required this.title,
    required this.subtitle,
    this.primaryActionLabel,
    this.primaryActionIcon,
    this.onPrimaryAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
  }) : assert(illustration != null || icon != null, 'Must provide either illustration or icon');

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (illustration != null)
              illustration!
            else if (icon != null)
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: p.accent.withValues(alpha: 0.12),
                  border: Border.all(color: p.accent.withValues(alpha: 0.25)),
                ),
                child: Center(
                  child: Icon(icon, size: 44, color: p.accent),
                ),
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
            if (primaryActionLabel != null && onPrimaryAction != null) ...[
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: onPrimaryAction,
                style: FilledButton.styleFrom(
                  backgroundColor: p.accent,
                  foregroundColor: p.onAccent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.sm,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.button),
                  ),
                ),
                icon: primaryActionIcon != null ? Icon(primaryActionIcon, size: 18) : const SizedBox.shrink(),
                label: Text(primaryActionLabel!),
              ),
            ],
            if (secondaryActionLabel != null && onSecondaryAction != null) ...[
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: onSecondaryAction,
                child: Text(
                  secondaryActionLabel!,
                  style: TextStyle(color: p.textTertiary, fontSize: AppFontSize.label),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
