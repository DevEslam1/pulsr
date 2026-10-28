// lib/core/widgets/glass_container.dart
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
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
    final effectiveAlpha = tintFactor != null
        ? (0.20 + (tintFactor!.clamp(0.0, 1.0) * 0.70))
        : opacity;

    final baseSurface = color ?? (p.isDark ? p.surface : p.surfaceContainer);
    final baseColor = baseSurface.withValues(alpha: effectiveAlpha);

    final effectiveBorder = border ??
        Border.all(
          color: (p.isDark ? Colors.white : Colors.black).withValues(
            alpha:
                p.isDark ? (isLiquid ? 0.15 : 0.09) : (isLiquid ? 0.10 : 0.06),
          ),
          width: isLiquid ? 1.15 : 1.0,
        );

    final effectiveShadow = boxShadow ??
        (isLiquid
            ? [
                BoxShadow(
                  color: AppColors.scrimAt(p.isDark ? 0.38 : 0.09),
                  blurRadius: 20,
                  spreadRadius: -2,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: p.accent.withValues(alpha: p.isDark ? 0.06 : 0.025),
                  blurRadius: 14,
                  offset: const Offset(0, 2),
                ),
              ]
            : null);

    // Subtle directional surface sheen for liquid/standard glass tiers
    final Gradient? surfaceGradient = tier == GlassTier.solid
        ? null
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.alphaBlend(
                AppColors.specularAt(
                    p.isDark ? (isLiquid ? 0.05 : 0.025) : 0.18),
                baseColor,
              ),
              baseColor,
            ],
          );

    final decoration = shape != null
        ? ShapeDecoration(
            color: surfaceGradient == null ? baseColor : null,
            gradient: surfaceGradient,
            shape: shape!,
            shadows: effectiveShadow,
          )
        : BoxDecoration(
            color: surfaceGradient == null ? baseColor : null,
            gradient: surfaceGradient,
            borderRadius: effectiveRadius,
            border: effectiveBorder,
            boxShadow: effectiveShadow,
          );

    final Widget paddedChild =
        padding != null ? Padding(padding: padding!, child: child) : child;

    final showSpecular = specularHighlight || isLiquid;

    final Widget decoratedContent = Container(
      decoration: decoration,
      child: showSpecular
          ? Stack(
              children: [
                PositionedDirectional(
                  top: 0,
                  start: 12,
                  end: 12,
                  height: 1.2,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.specularAt(0.0),
                            AppColors.specularAt(p.isDark ? 0.48 : 0.78),
                            AppColors.specularAt(0.0),
                          ],
                          stops: const [0.0, 0.5, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
                paddedChild,
              ],
            )
          : paddedChild,
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
