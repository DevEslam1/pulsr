import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/performance/gpu_budget.dart';
import '../../../../core/theme/aura_theme.dart';
import '../../../../core/widgets/pulsr_pressable.dart';

/// Large "one tap and music is playing" card. Gives Home a clear primary
/// action instead of three equal-weight tiles.
class HeroMixCard extends StatelessWidget {
  final String overline;
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final double height;

  const HeroMixCard({
    super.key,
    required this.overline,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.icon = Icons.graphic_eq_rounded,
    this.height = 116,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isHighContrast =
        p.isHighContrast || (MediaQuery.maybeHighContrastOf(context) ?? false);
    final isCalm = p.isCalmDensity || GpuBudget.isEnabled || isHighContrast;
    final textScale =
        MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.8);
    final effectiveHeight = math.max(
      height,
      height + (textScale - 1.0) * 44.0,
    );

    return Semantics(
      button: true,
      label: '$title, $subtitle',
      child: PulsrPressable(
        onTap: onTap,
        pressedScale: 0.97,
        hapticStyle: PulsrHapticStyle.light,
        focusBorderRadius: AppRadii.r24All,
        child: Container(
          constraints: BoxConstraints(minHeight: effectiveHeight),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: p.surfaceContainer,
            borderRadius: AppRadii.r24All,
            border: Border.all(
              color: isHighContrast
                  ? p.borderStrong
                  : (isCalm ? p.borderSubtle : p.hairline),
              width: isHighContrast ? 1.25 : 1.0,
            ),
            boxShadow: isCalm ? null : PulsrElevation.level2(context),
          ),
          child: Stack(
            children: [
              // Decorative waveform glyph, bleeds off the trailing edge.
              PositionedDirectional(
                end: -18,
                top: -14,
                child: ExcludeSemantics(
                  child: Icon(
                    icon,
                    size: 132,
                    color: p.accent.withValues(alpha: isCalm ? 0.06 : 0.11),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: p.accent
                                  .withValues(alpha: isCalm ? 0.10 : 0.16),
                              borderRadius: AppRadii.circular(999),
                              border: isCalm
                                  ? null
                                  : Border.all(
                                      color: p.accent.withValues(alpha: 0.26),
                                      width: 0.8,
                                    ),
                            ),
                            child: Text(
                              overline.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: p.accent,
                                fontSize: AppFontSize.caption,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.1,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.s6),
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: p.textPrimary,
                              fontSize: AppFontSize.titleMedium,
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: p.textSecondary,
                              fontSize: AppFontSize.label,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    ExcludeSemantics(
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: p.accent,
                          shape: BoxShape.circle,
                          boxShadow: isCalm
                              ? null
                              : [
                                  ...PulsrElevation.level2(context),
                                  BoxShadow(
                                    color: p.accent.withValues(alpha: 0.35),
                                    blurRadius: 16,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                        ),
                        child: Icon(Icons.play_arrow_rounded,
                            color: p.onAccent, size: 30),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
