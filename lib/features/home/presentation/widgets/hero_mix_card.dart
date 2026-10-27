import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/aura_theme.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

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
    return Semantics(
      button: true,
      label: '$title, $subtitle',
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadii.r24All,
        child: InkWell(
          borderRadius: AppRadii.r24All,
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          child: Container(
            height: height,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  p.accent.withValues(alpha: 0.36),
                  p.accent.withValues(alpha: 0.12),
                  p.surfaceContainer,
                ],
                stops: const [0, 0.55, 1],
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
              ),
              borderRadius: AppRadii.r24All,
              border: Border.all(color: p.accent.withValues(alpha: 0.38)),
              boxShadow: PulsrElevation.level2(context),
            ),
            child: Stack(
              children: [
                // Top specular refraction edge
                PositionedDirectional(
                  top: 0,
                  start: 20,
                  end: 20,
                  child: IgnorePointer(
                    child: Container(
                      height: 1.0,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0.0),
                            Colors.white.withValues(alpha: 0.24),
                            Colors.white.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Decorative waveform glyph, bleeds off the trailing edge.
                PositionedDirectional(
                  end: -18,
                  top: -14,
                  child: ExcludeSemantics(
                    child: Icon(icon,
                        size: 132, color: p.accent.withValues(alpha: 0.11)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: p.accent.withValues(alpha: 0.16),
                                borderRadius: AppRadii.circular(999),
                                border: Border.all(
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
                                  fontSize: AppFontSize.tiny,
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
                                fontSize: 22,
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
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color.lerp(p.accent, Colors.white, 0.14)!,
                                p.accent,
                              ],
                            ),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.22),
                              width: 1.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: p.glow,
                                blurRadius: 18,
                                spreadRadius: 1,
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
      ),
    );
  }
}
