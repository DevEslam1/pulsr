import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/aura_theme.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

/// Compact horizontal shortcut tile (icon + two lines). Secondary to
/// [HeroMixCard]; sits two-up beneath it (or stacked beside it on tablets).
class QuickTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const QuickTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      label: '$title, $subtitle',
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadii.r18All,
        child: InkWell(
          borderRadius: AppRadii.r18All,
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Container(
            constraints: const BoxConstraints(minHeight: 60),
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s10, vertical: AppSpacing.s10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
                colors: [
                  Color.alphaBlend(
                      color.withValues(alpha: 0.08), p.surfaceContainer),
                  p.surfaceContainer,
                ],
              ),
              borderRadius: AppRadii.r18All,
              border: Border.all(
                color: Color.alphaBlend(
                    color.withValues(alpha: 0.22), p.hairline),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.16),
                    borderRadius: AppRadii.r14All,
                    border: Border.all(
                      color: color.withValues(alpha: 0.26),
                      width: 0.8,
                    ),
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
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: p.textSecondary,
                          fontSize: AppFontSize.caption,
                        ),
                      ),
                    ],
                  ),
                ),
                ExcludeSemantics(
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: p.textTertiary.withValues(alpha: 0.6),
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
