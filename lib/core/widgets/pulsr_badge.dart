import 'package:flutter/material.dart';
import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';
import '../constants/app_typography.dart';
import '../theme/aura_theme.dart';

/// {@category DesignSystem}
enum PulsrBadgeColor {
  accent,
  success,
  error,
  warning,
  neutral,
}

/// Unified badge and status indicator widget for Pulsr.
class PulsrBadge extends StatelessWidget {
  final String? label;
  final PulsrBadgeColor color;
  final bool dot;

  const PulsrBadge({
    super.key,
    this.label,
    this.color = PulsrBadgeColor.accent,
    this.dot = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    Color bg;
    Color fg;

    switch (color) {
      case PulsrBadgeColor.accent:
        bg = p.accentSoft;
        fg = p.accent;
        break;
      case PulsrBadgeColor.success:
        bg = p.successSoft;
        fg = p.success;
        break;
      case PulsrBadgeColor.error:
        bg = p.errorSoft;
        fg = p.error;
        break;
      case PulsrBadgeColor.warning:
        bg = p.warningSoft;
        fg = p.warning;
        break;
      case PulsrBadgeColor.neutral:
        bg = p.surfaceContainerHigh;
        fg = p.textSecondary;
        break;
    }

    if (dot) {
      return Container(
        width: 8.0,
        height: 8.0,
        decoration: BoxDecoration(
          color: fg,
          shape: BoxShape.circle,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s6,
        vertical: AppSpacing.s2,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadii.r4All,
        border: Border.all(
          color: fg.withValues(alpha: 0.25),
          width: 0.8,
        ),
      ),
      child: Text(
        label ?? '',
        style: TextStyle(
          fontFamily: 'Manrope',
          fontSize: AppFontSize.tiny,
          fontWeight: FontWeight.w800,
          letterSpacing: AppTracking.label,
          color: fg,
          height: 1.1,
        ),
      ),
    );
  }
}
