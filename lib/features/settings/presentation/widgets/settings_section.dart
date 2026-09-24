// lib/features/settings/presentation/widgets/settings_section.dart
import 'package:flutter/material.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/theme/aura_theme.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';

/// A titled, card-wrapped settings group.
///
/// Shared container used across settings screens and sections so all
/// groups are styled consistently with a polished accent header and
/// rounded squircle card body.
class SettingsSection extends StatelessWidget {
  final IconData? icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> children;
  final bool isProminent;

  const SettingsSection({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.children,
    this.isProminent = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.md, 0, AppSpacing.md, AppSpacing.xs),
            child: Row(
              children: [
                if (icon != null) ...[
                  Container(
                    width: 24,
                    height: 24,
                    margin: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
                    decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(AppRadii.r8),
                    ),
                    child: Icon(icon, size: 13, color: p.accent),
                  ),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isProminent ? p.accent : p.textSecondary,
                          fontSize: AppFontSize.label,
                          fontWeight: isProminent
                              ? FontWeight.w900
                              : FontWeight.w800,
                          letterSpacing: AppTracking.overline,
                        ),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.s2),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            color: p.textTertiary,
                            fontSize: AppFontSize.label,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          Material(
            color: isProminent
                ? p.accentContainer.withValues(alpha: p.isDark ? 0.35 : 0.6)
                : p.surfaceContainer,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.card),
              side: BorderSide(
                color: isProminent
                    ? p.accent.withValues(alpha: 0.45)
                    : p.hairline,
                width: isProminent ? 1.5 : 1.0,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}
