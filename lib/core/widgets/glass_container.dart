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

  const GlassContainer({
    super.key,
    required this.child,
    this.blur = 20.0,
    this.opacity = 0.85,
    this.borderRadius,
    this.border,
    this.padding,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final effectiveRadius = borderRadius ?? AppRadii.cardRadius;
    final baseColor = color ?? p.surface;

    return ClipRRect(
      borderRadius: effectiveRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: color ?? baseColor.withValues(alpha: opacity),
            borderRadius: effectiveRadius,
            border: border ?? Border.all(
              color: p.hairline.withValues(alpha: 0.5),
              width: 1.0,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
