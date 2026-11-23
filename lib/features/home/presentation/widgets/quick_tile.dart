import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/aura_theme.dart';
import '../../../../core/widgets/pulsr_pressable.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

/// Compact horizontal Bento shortcut tile (icon + two lines). Secondary to
/// [QuranRadioHeroCarousel]; sits two-up beneath it (or stacked beside it on
/// tablets and landscape phones).
class QuickTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final IconData trailingIcon;
  final double trailingIconSize;

  const QuickTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
    this.trailingIcon = Icons.chevron_right_rounded,
    this.trailingIconSize = 16,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isHighContrast =
        p.isHighContrast || (MediaQuery.maybeHighContrastOf(context) ?? false);
    final isCalm = p.isCalmDensity || isHighContrast;
    final washStart = Color.alphaBlend(
      color.withValues(
        alpha: p.isDark
            ? (isCalm ? 0.08 : 0.14)
            : (isCalm ? 0.05 : 0.09),
      ),
      p.surfaceContainer,
    );
    final washEnd = Color.alphaBlend(
      color.withValues(alpha: p.isDark ? 0.025 : 0.015),
      p.surfaceContainer,
    );
    final specularBorder = isHighContrast
        ? p.borderStrong
        : Color.alphaBlend(
            color.withValues(alpha: p.isDark ? 0.20 : 0.18),
            p.borderSubtle,
          );
    final isPlayableAction = trailingIcon == Icons.play_arrow_rounded;

    return Semantics(
      label: '$title, $subtitle',
      child: PulsrPressable(
        onTap: onTap,
        pressedScale: 0.97,
        hapticStyle: PulsrHapticStyle.selection,
        focusBorderRadius: AppRadii.r18All,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.s12,
            AppSpacing.s12,
            AppSpacing.s10,
            AppSpacing.s12,
          ),
          decoration: BoxDecoration(
            color: isHighContrast ? p.surfaceContainer : null,
            gradient: isHighContrast
                ? null
                : LinearGradient(
                    begin: AlignmentDirectional.topStart,
                    end: AlignmentDirectional.bottomEnd,
                    colors: [washStart, washEnd],
                  ),
            borderRadius: AppRadii.r18All,
            border: Border.all(
              color: specularBorder,
              width: isHighContrast ? 1.25 : 1.0,
            ),
            boxShadow: isCalm ? null : PulsrElevation.level1(p),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: AlignmentDirectional.topStart,
                    end: AlignmentDirectional.bottomEnd,
                    colors: [
                      color.withValues(alpha: p.isDark ? 0.24 : 0.17),
                      color.withValues(alpha: p.isDark ? 0.11 : 0.08),
                    ],
                  ),
                  borderRadius: AppRadii.r14All,
                  boxShadow: isCalm
                      ? null
                      : [
                          BoxShadow(
                            color: color.withValues(
                              alpha: p.isDark ? 0.22 : 0.12,
                            ),
                            blurRadius: 10,
                            spreadRadius: -2,
                          ),
                        ],
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: AppSpacing.s10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: AppFontSize.bodySmall,
                        letterSpacing: -0.15,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.textSecondary,
                        fontWeight: FontWeight.w500,
                        fontSize: AppFontSize.caption,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xxs),
              ExcludeSemantics(
                child: Icon(
                  trailingIcon,
                  size: trailingIconSize,
                  color: isPlayableAction
                      ? color.withValues(alpha: 0.88)
                      : p.textTertiary.withValues(alpha: 0.72),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
