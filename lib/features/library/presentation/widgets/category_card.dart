// lib/features/library/presentation/widgets/category_card.dart
import 'package:material_ui/material_ui.dart';
import '../../../../core/theme/aura_theme.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/motion/pulsr_motion.dart';

/// A tappable card that presents a library category.
///
/// Shows [icon] inside a tinted rounded container, followed by a [title] and
/// [subtitle], with a trailing chevron. Tapping invokes [onTap].
class CategoryCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool isSelected;

  const CategoryCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isHighContrast = MediaQuery.maybeHighContrastOf(context) ?? false;
    return Semantics(
      button: true,
      label: '$title, $subtitle',
      selected: isSelected,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.r18All,
        child: AnimatedContainer(
          duration: context.motionMs(200),
          curve: context.motionCurve(PulsrMotion.enter),
          constraints: const BoxConstraints(
            minHeight: AppSpacing.minTouchTarget,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s14,
            vertical: AppSpacing.s8,
          ),
          decoration: BoxDecoration(
            color:
                isSelected ? color.withValues(alpha: 0.12) : p.surfaceContainer,
            borderRadius: AppRadii.r18All,
            border: Border.all(
              color: isSelected
                  ? (isHighContrast ? color : color.withValues(alpha: 0.6))
                  : (isHighContrast ? p.borderStrong : p.hairline),
              width: isSelected || isHighContrast ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: isSelected ? 0.25 : 0.15),
                    borderRadius: AppRadii.r12All),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: isSelected ? color : p.textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: AppFontSize.body)),
                    const SizedBox(height: AppSpacing.s2),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: p.textSecondary,
                            fontSize: AppFontSize.label)),
                  ],
                ),
              ),
              Icon(
                isSelected
                    ? Icons.check_circle_rounded
                    : Icons.chevron_right_rounded,
                color: isSelected ? color : p.textTertiary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
