import 'package:flutter/material.dart';

import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/utils/l10n_extensions.dart';

class QuranErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const QuranErrorCard({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      liveRegion: true,
      label: message,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.s14),
        decoration: BoxDecoration(
          color: p.surfaceContainer,
          borderRadius: AppRadii.r14All,
          border: Border.all(color: p.hairline),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: p.textSecondary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(message,
                  style: TextStyle(
                      color: p.textPrimary, fontSize: AppFontSize.label)),
            ),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(context.l10n.retry),
            ),
          ],
        ),
      ),
    );
  }
}
