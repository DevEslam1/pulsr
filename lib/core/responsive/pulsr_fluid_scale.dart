// lib/core/responsive/pulsr_fluid_scale.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'breakpoints.dart';
import 'pulsr_responsive_tokens.dart';

/// Fluid scaling engine that adapts dimensional tokens across screen sizes and postures.
class PulsrFluidScale {
  final double scale;
  final PulsrViewport viewport;

  const PulsrFluidScale({
    required this.scale,
    required this.viewport,
  });

  /// Base scale factor derived from viewport tier and vertical space.
  static double factor(BuildContext context) {
    final vp = PulsrViewport.of(context);
    return switch (vp.sizeClass) {
      PulsrBreakpoint.compact => vp.isShortHeight ? 0.85 : 1.0,
      PulsrBreakpoint.medium => 1.0,
      PulsrBreakpoint.expanded => 1.1,
      PulsrBreakpoint.large => 1.2,
    };
  }

  /// Retrieves the active [PulsrFluidScale] from [context].
  static PulsrFluidScale of(BuildContext context) {
    final vp = PulsrViewport.of(context);
    return PulsrFluidScale(scale: factor(context), viewport: vp);
  }

  // ── Semantic Sizing Tokens ───────────────────────────────────────────────

  /// Settings and navigation icon containers (40 * scale).
  double get iconBox => (40.0 * scale).clamp(32.0, 56.0);

  /// List row artwork thumbnails (44 * scale).
  double get artworkSm => (44.0 * scale).clamp(38.0, 60.0);

  /// Carousel and horizontal cards (120 * scale).
  double get artworkMd => (120.0 * scale).clamp(100.0, 160.0);

  /// Hero banners, detail artwork (160 * scale).
  double get artworkLg => (160.0 * scale).clamp(130.0, 240.0);

  /// Transport & playback control buttons (Guaranteed >= 48dp touch target).
  double get controlBtn => math.max(minTouchTarget, 48.0 * scale);

  /// Standard list tile row height (56 * scale).
  double get rowHeight => (56.0 * scale).clamp(48.0, 72.0);

  /// Standard interior card padding (16 * scale).
  double get cardPadding => (16.0 * scale).clamp(12.0, 24.0);

  /// Vertical gap between sections (24 * scale).
  double get sectionGap => (24.0 * scale).clamp(16.0, 36.0);

  /// WCAG & Material minimum touch target.
  static const double minTouchTarget = 48.0;
}

/// Extension on [BuildContext] for ergonomic fluid token resolution.
extension PulsrFluidScaleContextX on BuildContext {
  PulsrFluidScale get fluid => PulsrFluidScale.of(this);
}
