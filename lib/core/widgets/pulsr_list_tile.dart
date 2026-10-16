import 'package:flutter/material.dart';
import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';
import '../constants/app_typography.dart';
import '../theme/aura_theme.dart';
import 'pulsr_pressable.dart';

/// {@category DesignSystem}
enum PulsrListTileDensity {
  /// Dense rows for audio inspectors, telemetry, dense queues (48dp height).
  compact,

  /// Default list tile for tracks, playlists, settings (58dp height).
  normal,

  /// Spacious rows for hero cards, detailed profile/album listings (72dp height).
  relaxed,
}

/// Standardized list tile component for Pulsr.
///
/// Unifies leading artwork/icon, title, subtitle, and trailing controls
/// with consistent spacing, touch targets, and theme integration.
class PulsrListTile extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final PulsrListTileDensity density;
  final bool enabled;
  final EdgeInsetsGeometry? contentPadding;
  final BorderRadius? borderRadius;
  final Color? tileColor;

  const PulsrListTile({
    super.key,
    required this.title,
    this.leading,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.density = PulsrListTileDensity.normal,
    this.enabled = true,
    this.contentPadding,
    this.borderRadius,
    this.tileColor,
  });

  double get _minHeight {
    switch (density) {
      case PulsrListTileDensity.compact:
        return 48.0;
      case PulsrListTileDensity.normal:
        return 58.0;
      case PulsrListTileDensity.relaxed:
        return 72.0;
    }
  }

  EdgeInsetsGeometry _resolvePadding() {
    if (contentPadding != null) return contentPadding!;
    switch (density) {
      case PulsrListTileDensity.compact:
        return const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm, vertical: AppSpacing.xs);
      case PulsrListTileDensity.normal:
        return const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm);
      case PulsrListTileDensity.relaxed:
        return const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.md);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final radius = borderRadius ?? AppRadii.r14All;

    final titleStyle = TextStyle(
      fontFamily: 'Manrope',
      fontSize: density == PulsrListTileDensity.compact
          ? AppFontSize.body
          : AppFontSize.bodyLarge,
      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
      color: enabled ? (selected ? p.accent : p.textPrimary) : p.textTertiary,
      height: 1.25,
    );

    final subtitleStyle = TextStyle(
      fontFamily: 'Manrope',
      fontSize: AppFontSize.caption,
      fontWeight: FontWeight.w500,
      color: enabled ? p.textSecondary : p.textTertiary,
      height: 1.2,
    );

    Widget content = ConstrainedBox(
      constraints: BoxConstraints(minHeight: _minHeight),
      child: Padding(
        padding: _resolvePadding(),
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: AppSpacing.sm),
            ],
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: titleStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: AppSpacing.s2),
                    Text(
                      subtitle!,
                      style: subtitleStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: AppSpacing.sm),
              trailing!,
            ],
          ],
        ),
      ),
    );

    final effectiveBg =
        selected ? p.accentSoft : (tileColor ?? Colors.transparent);

    content = Container(
      decoration: BoxDecoration(
        color: effectiveBg,
        borderRadius: radius,
        border: selected ? Border.all(color: p.accent, width: 1.2) : null,
      ),
      child: content,
    );

    if (onTap != null || onLongPress != null) {
      content = PulsrPressable(
        onTap: enabled ? onTap : null,
        onLongPress: enabled ? onLongPress : null,
        child: content,
      );
    }

    return RepaintBoundary(
      child: Semantics(
        button: onTap != null,
        enabled: enabled,
        selected: selected,
        label: title,
        child: content,
      ),
    );
  }
}
