import 'package:flutter/material.dart';
import '../constants/app_spacing.dart';
import '../theme/aura_theme.dart';
import '../utils/adaptive.dart';
import 'package:pulsr/core/constants/app_typography.dart';

/// Uppercase micro-label section header with optional action — the signature
/// premium typography pattern used across Home/Library/Playlists/Settings.
///
/// When [padding] is not supplied the header aligns to the screen's content
/// gutter ([Adaptive.pagePadding]) so titles and actions share the same leading
/// and trailing edge as the content below them (Apple HIG alignment).
class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry? padding;

  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final gutter = Adaptive.pagePadding(context);
    return Padding(
      padding: padding ??
          EdgeInsetsDirectional.fromSTEB(
              gutter, AppSpacing.xs, gutter, AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: p.textTertiary),
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s10),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(actionLabel!,
                  style: TextStyle(
                      color: p.accent,
                      fontWeight: FontWeight.w800,
                      fontSize: AppFontSize.label)),
            ),
        ],
      ),
    );
  }
}
