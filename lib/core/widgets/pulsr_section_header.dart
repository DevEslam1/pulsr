// lib/core/widgets/pulsr_section_header.dart
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';
import '../constants/app_typography.dart';
import '../theme/aura_theme.dart';
import '../theme/pulsr_button_style.dart';
import '../utils/adaptive.dart';
import 'pulsr_pressable.dart';
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
    final isCapsule = context.isCapsuleButtons;
    final gutter = Adaptive.pagePadding(context);
    final isLargeHeader = overline != null;

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
            if (isLargeHeader)
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: p.accent.withValues(alpha: p.isDark ? 0.16 : 0.10),
                  border: Border.all(
                    color: p.accent.withValues(alpha: 0.35),
                    width: 1.0,
                  ),
                ),
                child: Icon(
                  icon,
                  size: 17.0,
                  color: p.accent,
                ),
              )
            else
              Icon(
                icon,
                size: 18.0,
                color: p.accent,
              ),
            const SizedBox(width: AppSpacing.xs + 2),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isLargeHeader) ...[
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
                        isLargeHeader ? title : title.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: isLargeHeader
                            ? TextStyle(
                                fontFamily: 'Manrope',
                                fontSize: AppFontSize.bodyLarge,
                                fontWeight: FontWeight.w800,
                                color: p.textPrimary,
                                letterSpacing: AppTracking.title,
                              )
                            : Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: p.textTertiary,
                                  letterSpacing: AppTracking.wide,
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                    ),
                    if (count != null) ...[
                      const SizedBox(width: AppSpacing.xs),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7.0,
                          vertical: 2.0,
                        ),
                        decoration: isCapsule
                            ? PulsrCapsuleStyle.decoration(p)
                            : BoxDecoration(
                                color: p.isDark
                                    ? AppColors.specularAt(0.08)
                                    : p.surfaceContainerHigh,
                                borderRadius: AppRadii.full,
                                border: Border.all(
                                  color: p.isDark
                                      ? AppColors.specularAt(0.14)
                                      : p.hairline,
                                  width: 0.8,
                                ),
                              ),
                        child: Text(
                          '$count',
                          style: TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: AppFontSize.tiny,
                            fontWeight: FontWeight.w800,
                            color: isCapsule
                                ? PulsrCapsuleStyle.secondaryForegroundColor(p)
                                : p.textSecondary,
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
              constraints: const BoxConstraints(
                maxWidth: 168,
                minHeight: 40,
              ),
              child: PulsrPressable(
                pressedScale: 0.95,
                focusBorderRadius:
                    isCapsule ? context.buttonRadius(rectRadius: 6.0) : AppRadii.full,
                onTap: onAction,
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  widthFactor: 1.0,
                  child: Container(
                    padding: const EdgeInsetsDirectional.only(
                      start: AppSpacing.s10,
                      end: AppSpacing.xs,
                      top: 6,
                      bottom: 6,
                    ),
                    decoration: isCapsule
                        ? PulsrCapsuleStyle.decoration(p,
                            borderRadius: context.buttonRadius(rectRadius: 6.0))
                        : BoxDecoration(
                            color: p.accent.withValues(alpha: p.isDark ? 0.14 : 0.09),
                            borderRadius: AppRadii.full,
                            border: Border.all(
                              color: p.accent.withValues(alpha: 0.30),
                              width: 0.8,
                            ),
                          ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            actionLabel!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Manrope',
                              color: isCapsule
                                  ? PulsrCapsuleStyle.foregroundColor(p)
                                  : p.accent,
                              fontWeight: FontWeight.w800,
                              fontSize: isCapsule ? 11.5 : AppFontSize.label,
                              letterSpacing: isCapsule ? 0.2 : AppTracking.label,
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: isCapsule
                              ? PulsrCapsuleStyle.secondaryForegroundColor(p)
                              : p.accent,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
