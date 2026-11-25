// lib/core/widgets/pulsr_section_header.dart
import 'package:material_ui/material_ui.dart';
import '../constants/app_colors.dart';
import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';
import '../constants/app_typography.dart';
import '../motion/pulsr_motion.dart';
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
                                fontFamily: fontFamily,
                                fontFamilyFallback: fontFallbacks,
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
                                  color: p.isHighContrast
                                      ? p.borderStrong
                                      : (p.isDark
                                          ? AppColors.specularAt(0.14)
                                          : p.hairline),
                                  width: p.isHighContrast ? 1.2 : 0.8,
                                ),
                              ),
                        child: Text(
                          '$count',
                          style: TextStyle(
                            fontFamily: fontFamily,
                            fontFamilyFallback: fontFallbacks,
                            fontSize: AppFontSize.caption,
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
            _SectionActionButton(
              label: actionLabel!,
              onTap: onAction!,
              isCapsule: isCapsule,
            ),
        ],
      ),
    );
  }
}

/// Lightweight editorial trailing action for [PulsrSectionHeader].
///
/// Renders clean accent-tinted text + chevron with subtle hover/press ink in
/// classic mode (eliminating heavy filled maroon pills), while honoring
/// [PulsrCapsuleStyle] when glass/capsule button style is active.
class _SectionActionButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final bool isCapsule;

  const _SectionActionButton({
    required this.label,
    required this.onTap,
    required this.isCapsule,
  });

  @override
  State<_SectionActionButton> createState() => _SectionActionButtonState();
}

class _SectionActionButtonState extends State<_SectionActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isCapsule = widget.isCapsule;
    final radius =
        isCapsule ? context.buttonRadius(rectRadius: 6.0) : AppRadii.full;
    final hoverFill = isCapsule
        ? null
        : (_hovered
            ? p.accent.withValues(alpha: p.isDark ? 0.11 : 0.08)
            : Colors.transparent);

    return MouseRegion(
      onEnter: (_) {
        if (!_hovered) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (_hovered) setState(() => _hovered = false);
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 168,
          minWidth: AppSpacing.minTouchTarget,
          minHeight: AppSpacing.minTouchTarget,
        ),
        child: PulsrPressable(
          pressedScale: 0.96,
          hapticStyle: PulsrHapticStyle.selection,
          focusBorderRadius: radius,
          onTap: widget.onTap,
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            widthFactor: 1.0,
            child: AnimatedContainer(
              duration: context.motion(PulsrDurations.tap),
              curve: context.motionCurve(Curves.easeOutCubic),
              padding: isCapsule
                  ? const EdgeInsetsDirectional.only(
                      start: AppSpacing.s10,
                      end: AppSpacing.xs,
                      top: AppSpacing.s6,
                      bottom: AppSpacing.s6,
                    )
                  : const EdgeInsetsDirectional.only(
                      start: AppSpacing.xs,
                      end: AppSpacing.xxs,
                      top: AppSpacing.s6,
                      bottom: AppSpacing.s6,
                    ),
              decoration: isCapsule
                  ? PulsrCapsuleStyle.decoration(
                      p,
                      borderRadius: radius,
                    )
                  : BoxDecoration(
                      color: hoverFill,
                      borderRadius: radius,
                    ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: fontFamily,
                        fontFamilyFallback: fontFallbacks,
                        color: isCapsule
                            ? PulsrCapsuleStyle.foregroundColor(p)
                            : p.accent,
                        fontWeight: FontWeight.w700,
                        fontSize:
                            isCapsule ? AppFontSize.caption : AppFontSize.label,
                        letterSpacing: AppTracking.label,
                      ),
                    ),
                  ),
                  AnimatedPadding(
                    duration: context.motion(PulsrDurations.tap),
                    curve: context.motionCurve(Curves.easeOutCubic),
                    padding: EdgeInsetsDirectional.only(
                      start: _hovered ? AppSpacing.s4 : AppSpacing.s2,
                    ),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: isCapsule
                          ? PulsrCapsuleStyle.secondaryForegroundColor(p)
                          : p.accent.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
