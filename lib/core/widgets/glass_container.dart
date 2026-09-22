// lib/core/widgets/glass_container.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import '../constants/app_radii.dart';
import '../performance/gpu_budget.dart';
import '../theme/aura_theme.dart';

class GlassContainer extends StatelessWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final BorderRadius? borderRadius;
  final ShapeBorder? shape;
  final Border? border;
  final EdgeInsetsGeometry? padding;
  final Color? color;

  /// When false, no [BackdropFilter] is used — the container renders a
  /// tinted translucent surface, avoiding a GPU-expensive blur pass on
  /// low-end devices.
  final bool enableBlur;

  final List<BoxShadow>? boxShadow;

  /// Whether to render a specular directional highlight along the top edge,
  /// simulating light refraction through continuous curved liquid glass.
  final bool specularHighlight;

  /// Optional tint factor (0.0 = ultra clear, 1.0 = deeply tinted).
  final double? tintFactor;

  /// Whether this is configured with iOS 26/27 liquid glass defaults.
  final bool isLiquid;

  const GlassContainer({
    super.key,
    required this.child,
    this.blur = 12.0,
    this.opacity = 0.78,
    this.borderRadius,
    this.shape,
    this.border,
    this.padding,
    this.color,
    this.boxShadow,
    this.enableBlur = true,
    this.specularHighlight = false,
    this.tintFactor,
  }) : isLiquid = false;

  /// Factory constructor configured for iOS 26/27 refractive Liquid Glass.
  /// Uses a higher blur sigma (24.0), specular top hairline, and squircle curvature.
  const GlassContainer.liquid({
    super.key,
    required this.child,
    this.blur = 24.0,
    this.opacity = 0.72,
    this.borderRadius,
    this.shape,
    this.border,
    this.padding,
    this.color,
    this.boxShadow,
    this.enableBlur = true,
    this.specularHighlight = true,
    this.tintFactor,
  }) : isLiquid = true;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final effectiveRadius = borderRadius ?? (shape == null ? AppRadii.cardRadius : null);
    final effectiveAlpha = tintFactor != null
        ? (0.20 + (tintFactor!.clamp(0.0, 1.0) * 0.70))
        : opacity;

    final baseSurface = color ?? (p.isDark ? p.surface : p.surfaceContainer);
    final baseColor = baseSurface.withValues(alpha: effectiveAlpha);

    // Layered border: subtle outer contour
    final effectiveBorder = border ??
        Border.all(
          color: (p.isDark ? Colors.white : Colors.black)
              .withValues(alpha: p.isDark ? (isLiquid ? 0.14 : 0.10) : (isLiquid ? 0.10 : 0.06)),
          width: isLiquid ? 1.2 : 1.0,
        );

    // Default liquid shadow adds ambient soft depth
    final effectiveShadow = boxShadow ??
        (isLiquid
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: p.isDark ? 0.35 : 0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: p.accent.withValues(alpha: p.isDark ? 0.05 : 0.02),
                  blurRadius: 12,
                  offset: const Offset(0, 1),
                ),
              ]
            : null);

    final decoration = shape != null
        ? ShapeDecoration(
            color: baseColor,
            shape: shape!,
            shadows: effectiveShadow,
          )
        : BoxDecoration(
            color: baseColor,
            borderRadius: effectiveRadius,
            border: effectiveBorder,
            boxShadow: effectiveShadow,
          );

    final Widget decoratedContent = Container(
      decoration: decoration,
      child: Stack(
        children: [
          // Specular refraction highlight along the top hairline
          if (specularHighlight)
            PositionedDirectional(
              top: 0,
              start: 8,
              end: 8,
              height: 1.2,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.0),
                      Colors.white.withValues(alpha: p.isDark ? 0.45 : 0.75),
                      Colors.white.withValues(alpha: 0.0),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),
          Padding(
            padding: padding ?? EdgeInsets.zero,
            child: child,
          ),
        ],
      ),
    );

    Widget clipped;
    if (shape != null) {
      clipped = ClipPath(
        clipper: ShapeBorderClipper(shape: shape!),
        child: decoratedContent,
      );
    } else {
      clipped = ClipRRect(
        borderRadius: effectiveRadius ?? BorderRadius.zero,
        child: decoratedContent,
      );
    }

    if (!enableBlur || GpuBudget.isEnabled) {
      return clipped;
    }

    Widget blurred;
    if (shape != null) {
      blurred = ClipPath(
        clipper: ShapeBorderClipper(shape: shape!),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: decoratedContent,
        ),
      );
    } else {
      blurred = ClipRRect(
        borderRadius: effectiveRadius ?? BorderRadius.zero,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: decoratedContent,
        ),
      );
    }

    return RepaintBoundary(child: blurred);
  }
}
