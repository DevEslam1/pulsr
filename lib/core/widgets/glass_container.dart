// lib/core/widgets/glass_container.dart
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import '../constants/app_radii.dart';
import '../performance/gpu_budget.dart';
import '../theme/aura_theme.dart';

/// {@category DesignSystem}
enum GlassTier {
  standard,
  liquid,
  solid,
}

/// Standardized BackdropFilter sigma and opacity pairs for design-system glass surfaces.
enum GlassPreset {
  dock(blur: 24.0, opacity: 0.72),
  sheet(blur: 20.0, opacity: 0.82),
  dialog(blur: 16.0, opacity: 0.88),
  chip(blur: 8.0, opacity: 0.60);

  final double blur;
  final double opacity;
  const GlassPreset({required this.blur, required this.opacity});
}

class GlassContainer extends StatelessWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final BorderRadius? borderRadius;
  final ShapeBorder? shape;
  final Border? border;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final GlassTier tier;
  final bool enableBlur;
  final List<BoxShadow>? boxShadow;
  final bool specularHighlight;
  final double? tintFactor;
  final bool isLiquid;

  const GlassContainer({
    super.key,
    required this.child,
    this.tier = GlassTier.standard,
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
  })  : assert(border == null || shape == null,
            'Provide either border or shape, not both'),
        isLiquid = tier == GlassTier.liquid;

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
  })  : assert(border == null || shape == null,
            'Provide either border or shape, not both'),
        tier = GlassTier.liquid,
        isLiquid = true;

  const GlassContainer.solid({
    super.key,
    required this.child,
    this.opacity = 1.0,
    this.borderRadius,
    this.shape,
    this.border,
    this.padding,
    this.color,
    this.boxShadow,
    this.tintFactor,
  })  : assert(border == null || shape == null,
            'Provide either border or shape, not both'),
        tier = GlassTier.solid,
        blur = 0.0,
        enableBlur = false,
        specularHighlight = false,
        isLiquid = false;

  GlassContainer.fromPreset({
    super.key,
    required this.child,
    required GlassPreset preset,
    this.borderRadius,
    this.shape,
    this.border,
    this.padding,
    this.color,
    this.boxShadow,
    this.enableBlur = true,
    this.specularHighlight = false,
    this.tintFactor,
  })  : assert(border == null || shape == null,
            'Provide either border or shape, not both'),
        tier = GlassTier.standard,
        blur = preset.blur,
        opacity = preset.opacity,
        isLiquid = preset == GlassPreset.dock;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final effectiveRadius =
        borderRadius ?? (shape == null ? AppRadii.cardRadius : null);

    final baseColor = color ?? (p.isDark ? p.surfaceContainer : p.surface);

    final effectiveBorder = border ??
        Border.all(
          color: p.hairline,
          width: 1.0,
        );

    final effectiveShadow = boxShadow;

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

    final Widget paddedChild =
        padding != null ? Padding(padding: padding!, child: child) : child;

    final Widget decoratedContent = Container(
      decoration: decoration,
      child: paddedChild,
    );

    if (!enableBlur || GpuBudget.isGpuSaverActive || blur <= 0) {
      if (shape != null) {
        return ClipPath(
          clipper: ShapeBorderClipper(shape: shape!),
          child: decoratedContent,
        );
      }
      return ClipRRect(
        borderRadius: effectiveRadius ?? BorderRadius.zero,
        child: decoratedContent,
      );
    }

    final effectiveSigma = math.min(blur, 18.0);

    Widget blurred;
    if (shape != null) {
      blurred = ClipPath(
        clipper: ShapeBorderClipper(shape: shape!),
        child: BackdropFilter(
          filter:
              ImageFilter.blur(sigmaX: effectiveSigma, sigmaY: effectiveSigma),
          child: decoratedContent,
        ),
      );
    } else {
      blurred = ClipRRect(
        borderRadius: effectiveRadius ?? BorderRadius.zero,
        child: BackdropFilter(
          filter:
              ImageFilter.blur(sigmaX: effectiveSigma, sigmaY: effectiveSigma),
          child: decoratedContent,
        ),
      );
    }

    return RepaintBoundary(child: blurred);
  }
}
