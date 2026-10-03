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

  const HeroMixCard({
    super.key,
    required this.overline,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.icon = Icons.graphic_eq_rounded,
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
            height: 116,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  p.accent.withValues(alpha: 0.34),
                  p.accent.withValues(alpha: 0.08),
                  p.surfaceContainer,
                ],
                stops: const [0, 0.55, 1],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: AppRadii.r24All,
              border: Border.all(color: p.accent.withValues(alpha: 0.35)),
            ),
            child: Stack(
              children: [
                // Decorative waveform glyph, bleeds off the trailing edge.
                PositionedDirectional(
                  end: -18,
                  top: -14,
                  child: ExcludeSemantics(
                    child: Icon(icon,
                        size: 130, color: p.accent.withValues(alpha: 0.10)),
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
                            Text(
                              overline.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: p.accent,
                                fontSize: AppFontSize.tiny,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
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
                            boxShadow: [
                              BoxShadow(
                                  color: p.glow,
                                  blurRadius: 20,
                                  spreadRadius: 1),
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
