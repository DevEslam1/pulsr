import 'package:flutter/material.dart';
import '../constants/app_spacing.dart';
import '../constants/app_typography.dart';
import '../theme/aura_theme.dart';
import '../utils/adaptive.dart';

export 'section_header.dart';

/// Standardized section header with typography hierarchy and optional trailing action.
class PulsrSectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  const PulsrSectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.trailing,
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
                  ?.copyWith(color: p.textTertiary, letterSpacing: AppTracking.wide),
            ),
          ),
          if (trailing != null)
            trailing!
          else if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s10),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                actionLabel!,
                style: TextStyle(
                  color: p.accent,
                  fontWeight: FontWeight.w800,
                  fontSize: AppFontSize.label,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
