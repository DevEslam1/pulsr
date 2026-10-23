import 'package:flutter/material.dart';
import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';
import '../theme/aura_theme.dart';
import 'pulsr_pressable.dart';

/// {@category DesignSystem}
/// Circular icon button with a guaranteed 48dp minimum touch target,
/// background tint, and badge integration.
class PulsrIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final String? semanticLabel;
  final Color? iconColor;
  final Color? backgroundColor;

  /// Visual diameter. The interactive target expands to at least 48dp.
  final double size;
  final double iconSize;
  final Widget? badge;
  final BoxBorder? border;

  const PulsrIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.semanticLabel,
    this.iconColor,
    this.backgroundColor,
    this.size = 44.0,
    this.iconSize = 20.0,
    this.badge,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = onPressed != null;

    final effectiveIconColor =
        iconColor ?? (enabled ? p.textSecondary : p.textTertiary);

    Widget button = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.transparent,
        shape: BoxShape.circle,
        border: border,
      ),
      child: Icon(
        icon,
        size: iconSize,
        color: effectiveIconColor,
      ),
    );

    if (badge != null) {
      button = Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          button,
          PositionedDirectional(
            top: 2,
            end: 2,
            child: badge!,
          ),
        ],
      );
    }

    button = PulsrPressable(
      onTap: onPressed,
      focusBorderRadius: AppRadii.full,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: AppSpacing.minTouchTarget,
          minHeight: AppSpacing.minTouchTarget,
        ),
        child: Center(child: button),
      ),
    );

    if (tooltip != null) {
      button = Tooltip(
        message: tooltip!,
        child: button,
      );
    }

    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel ?? tooltip,
      child: button,
    );
  }
}
