// lib/core/widgets/pulsr_icon_button.dart
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';
import '../motion/pulsr_motion.dart';
import '../theme/aura_theme.dart';
import 'pulsr_pressable.dart';

/// {@category DesignSystem}
/// Circular icon button with a guaranteed 48dp minimum touch target,
/// hover highlight, background tint, and badge integration.
class PulsrIconButton extends StatefulWidget {
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
  State<PulsrIconButton> createState() => _PulsrIconButtonState();
}

class _PulsrIconButtonState extends State<PulsrIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = widget.onPressed != null;

    final effectiveIconColor = widget.iconColor ??
        (enabled
            ? (_hovered ? p.textPrimary : p.textSecondary)
            : p.textTertiary);

    final baseBg = widget.backgroundColor ?? Colors.transparent;
    final effectiveBg = _hovered && enabled && widget.backgroundColor == null
        ? (p.isDark ? AppColors.specularAt(0.08) : AppColors.scrimAt(0.06))
        : baseBg;

    Widget button = AnimatedContainer(
      duration: context.motionMs(140),
      curve: Curves.easeOutCubic,
      width: widget.size,
      height: widget.size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: effectiveBg,
        shape: BoxShape.circle,
        border: widget.border,
      ),
      child: Icon(
        widget.icon,
        size: widget.iconSize,
        color: effectiveIconColor,
      ),
    );

    if (widget.badge != null) {
      button = Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          button,
          PositionedDirectional(
            top: 2,
            end: 2,
            child: widget.badge!,
          ),
        ],
      );
    }

    button = MouseRegion(
      onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
      onExit: enabled ? (_) => setState(() => _hovered = false) : null,
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: PulsrPressable(
        onTap: widget.onPressed,
        focusBorderRadius: AppRadii.full,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: AppSpacing.minTouchTarget,
            minHeight: AppSpacing.minTouchTarget,
          ),
          child: Center(child: button),
        ),
      ),
    );

    if (widget.tooltip != null) {
      button = Tooltip(
        message: widget.tooltip!,
        child: button,
      );
    }

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel ?? widget.tooltip,
      child: button,
    );
  }
}
