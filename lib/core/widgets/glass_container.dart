// lib/core/widgets/glass_container.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import '../constants/app_radii.dart';
import '../theme/aura_theme.dart';

class GlassContainer extends StatelessWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final BorderRadius? borderRadius;
  final Border? border;
  final EdgeInsetsGeometry? padding;
  final Color? color;

  /// When false, no [BackdropFilter] is used — the container renders a
  /// tinted translucent surface, avoiding a GPU-expensive blur pass on
  /// low-end devices.
  final bool enableBlur;

  final List<BoxShadow>? boxShadow;

  const GlassContainer({
    super.key,
    required this.child,
    this.blur = 12.0,
    this.opacity = 0.78,
    this.borderRadius,
    this.border,
    this.padding,
    this.color,
    this.boxShadow,
    this.enableBlur = true,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final effectiveRadius = borderRadius ?? AppRadii.cardRadius;
    final baseColor = (color ?? p.surface).withValues(alpha: opacity);

    final effectiveBorder = border ??
        Border.all(
          color: (p.isDark ? Colors.white : Colors.black)
              .withValues(alpha: p.isDark ? 0.10 : 0.06),
          width: 1.0,
        );

    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: baseColor,
        borderRadius: effectiveRadius,
        border: effectiveBorder,
        boxShadow: boxShadow,
      ),
      child: child,
    );

    if (!enableBlur) {
      return ClipRRect(borderRadius: effectiveRadius, child: content);
    }

    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: effectiveRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: content,
        ),
      ),
    );
  }
}
