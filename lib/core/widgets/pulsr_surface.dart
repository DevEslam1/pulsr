// lib/core/widgets/pulsr_surface.dart
import 'package:flutter/material.dart';
import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';
import 'glass_container.dart';
import 'pulsr_pressable.dart';

/// A unified interactive surface combining glass/solid materials, ink ripple,
/// and tactile scale micro-interactions.
///
/// Eliminates the need to nest [PulsrPressable] -> [GlassContainer] -> [InkWell]
/// manually. Provides full WCAG accessibility semantics and 48x48 touch targeting.
class PulsrSurface extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final GlassTier tier;
  final BorderRadius? borderRadius;
  final ShapeBorder? shape;
  final Border? border;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final List<BoxShadow>? boxShadow;
  final bool enableScale;
  final bool enableHaptics;
  final PulsrHapticStyle hapticStyle;
  final String? semanticLabel;
  final bool isButton;

  const PulsrSurface({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.tier = GlassTier.standard,
    this.borderRadius,
    this.shape,
    this.border,
    this.padding,
    this.color,
    this.boxShadow,
    this.enableScale = true,
    this.enableHaptics = true,
    this.hapticStyle = PulsrHapticStyle.light,
    this.semanticLabel,
    this.isButton = false,
  });

  const PulsrSurface.liquid({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius,
    this.shape,
    this.border,
    this.padding,
    this.color,
    this.boxShadow,
    this.enableScale = true,
    this.enableHaptics = true,
    this.hapticStyle = PulsrHapticStyle.light,
    this.semanticLabel,
    this.isButton = false,
  }) : tier = GlassTier.liquid;

  const PulsrSurface.solid({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius,
    this.shape,
    this.border,
    this.padding,
    this.color,
    this.boxShadow,
    this.enableScale = true,
    this.enableHaptics = true,
    this.hapticStyle = PulsrHapticStyle.light,
    this.semanticLabel,
    this.isButton = false,
  }) : tier = GlassTier.solid;

  @override
  Widget build(BuildContext context) {
    final effectiveRadius =
        borderRadius ?? (shape == null ? AppRadii.cardRadius : null);

    Widget content = GlassContainer(
      tier: tier,
      borderRadius: effectiveRadius,
      shape: shape,
      border: border,
      padding: padding,
      color: color,
      boxShadow: boxShadow,
      child: child,
    );

    final isInteractive = onTap != null || onLongPress != null;

    if (isInteractive) {
      if (enableScale) {
        content = PulsrPressable(
          onTap: onTap,
          onLongPress: onLongPress,
          enableHaptics: enableHaptics,
          hapticStyle: hapticStyle,
          child: content,
        );
      } else {
        content = Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: effectiveRadius,
            customBorder: shape,
            onTap: onTap,
            onLongPress: onLongPress,
            child: content,
          ),
        );
      }

      // Ensure minimum touch target dimension (WCAG 2.2 AA)
      content = ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: AppSpacing.minTouchTarget,
          minHeight: AppSpacing.minTouchTarget,
        ),
        child: content,
      );
    }

    if (semanticLabel != null || isButton || isInteractive) {
      content = Semantics(
        label: semanticLabel,
        button: isButton || isInteractive,
        enabled: isInteractive,
        child: content,
      );
    }

    return content;
  }
}
