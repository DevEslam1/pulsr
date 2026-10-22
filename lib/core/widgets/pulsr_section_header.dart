import 'package:flutter/material.dart';
import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';
import '../constants/app_typography.dart';
import '../theme/aura_theme.dart';
import '../utils/adaptive.dart';
import 'pulsr_text.dart';

/// {@category DesignSystem}
/// Standardized section header with typography hierarchy, count badge, icon,
/// and trailing action button.
class PulsrSectionHeader extends StatelessWidget {
  final String title;
  final String? overline;
  final IconData? icon;
  final int? count;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  const PulsrSectionHeader({
    super.key,
    required this.title,
    this.overline,
    this.icon,
    this.count,
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
            gutter,
            AppSpacing.sm,
            gutter,
            AppSpacing.xs,
          ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 20.0,
              color: p.accent,
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (overline != null) ...[
                  Text(
                    overline!.toUpperCase(),
                    style: PulsrText.overline(context: context),
                  ),
                  const SizedBox(height: AppSpacing.s2),
                ],
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        overline != null ? title : title.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: overline != null
                            ? TextStyle(
                                fontFamily: 'Manrope',
                                fontSize: AppFontSize.bodyLarge,
                                fontWeight: FontWeight.w800,
                                color: p.textPrimary,
                              )
                            : Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: p.textTertiary,
                                  letterSpacing: AppTracking.wide,
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                    ),
                    if (count != null) ...[
                      const SizedBox(width: AppSpacing.xs),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s6,
                          vertical: AppSpacing.s2,
                        ),
                        decoration: BoxDecoration(
                          color: p.surfaceContainerHigh,
                          borderRadius: AppRadii.full,
                        ),
                        child: Text(
                          '$count',
                          style: TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: AppFontSize.tiny,
                            fontWeight: FontWeight.w700,
                            color: p.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (trailing != null)
            trailing!
          else if (actionLabel != null && onAction != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: TextButton(
                onPressed: onAction,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s10),
                minimumSize: const Size(44, 44),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
                child: Text(
                  actionLabel!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    color: p.accent,
                    fontWeight: FontWeight.w700,
                    fontSize: AppFontSize.label,
                    letterSpacing: AppTracking.label,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
