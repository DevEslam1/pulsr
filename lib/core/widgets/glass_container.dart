// lib/core/widgets/glass_container.dart
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import '../constants/app_radii.dart';
import '../performance/gpu_budget.dart';
import '../services/settings_cache.dart';
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

    // The user's Liquid Glass Tint (0 = ultra clear, 1 = tinted) and the
    // preset opacity were previously accepted but never applied, so every
    // "glass" surface rendered opaque and the slider did nothing.
    final tint = (tintFactor ??
            SettingsCache()
                .getDouble('setting_liquid_glass_tint', defaultValue: 0.8))
        .clamp(0.0, 1.0);
    final tintAlpha = (opacity * (0.35 + 0.65 * tint)).clamp(0.0, 1.0);
    final base = color ?? (p.isDark ? p.surfaceContainer : p.surface);
    final baseColor =
        color == null ? base.withValues(alpha: base.a * tintAlpha) : base;

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
