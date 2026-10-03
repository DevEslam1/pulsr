import 'package:flutter/material.dart';

import '../../../../core/theme/aura_theme.dart';
import 'package:pulsr/core/constants/app_radii.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

class QuickCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const QuickCard({
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
    final isCompact = MediaQuery.sizeOf(context).width < 380;

    return Material(
      color: Colors.transparent,
      borderRadius: AppRadii.r18All,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.r18All,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 10 : 12,
            vertical: isCompact ? 10 : 12,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                color.withValues(alpha: 0.16),
                color.withValues(alpha: 0.03)
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            color: p.surfaceContainer,
            borderRadius: AppRadii.r18All,
            border: Border.all(color: p.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.all(isCompact ? 6 : 7),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: isCompact ? 17 : 19),
              ),
              SizedBox(height: isCompact ? 8 : 10),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: p.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize:
                      isCompact ? AppFontSize.label : AppFontSize.bodySmall,
                ),
              ),
              const SizedBox(height: AppSpacing.s2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: p.textSecondary,
                  fontSize: isCompact ? AppFontSize.tiny : AppFontSize.caption,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
