import 'package:flutter/material.dart';

import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

class SectionError extends StatelessWidget {
  final VoidCallback onRetry;

  const SectionError({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.s14),
        decoration: BoxDecoration(
          color: p.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadii.r14),
          border: Border.all(color: p.error.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: p.error),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                context.l10n.libLoadFailed,
                style: TextStyle(
                    color: p.textSecondary, fontSize: AppFontSize.bodySmall),
              ),
            ),
            TextButton(
              onPressed: onRetry,
              child: Text(context.l10n.retry),
            ),
          ],
        ),
      ),
    );
  }
}
