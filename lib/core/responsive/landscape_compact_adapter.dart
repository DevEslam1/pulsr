// lib/core/responsive/landscape_compact_adapter.dart
import 'package:flutter/material.dart';
import 'pulsr_responsive_tokens.dart';

/// Mixin for stateful widgets that adapt layout for landscape phone mode (height < 500dp).
mixin LandscapeCompactAdapter<T extends StatefulWidget> on State<T> {
  /// Whether the screen is currently in landscape phone mode (short height < 500dp).
  bool get isLandscapeCompact => PulsrViewport.of(context).isShortHeight;

  /// Adaptive page or gutter horizontal padding.
  double get adaptivePadding => isLandscapeCompact ? 12.0 : 20.0;

  /// Adaptive hero or header height.
  double get adaptiveHeroHeight => isLandscapeCompact ? 100.0 : 220.0;

  /// Adaptive list row height.
  double get adaptiveRowHeight => isLandscapeCompact ? 48.0 : 56.0;

  /// Adaptive grid item height reduction multiplier.
  double get adaptiveGridHeightRatio => isLandscapeCompact ? 0.85 : 1.0;
}

/// Standalone stateless helper for accessing landscape compact metrics.
abstract class LandscapeCompactMetrics {
  static bool isLandscapeCompact(BuildContext context) =>
      PulsrViewport.of(context).isShortHeight;

  static double adaptivePadding(BuildContext context) =>
      isLandscapeCompact(context) ? 12.0 : 20.0;

  static double adaptiveHeroHeight(BuildContext context) =>
      isLandscapeCompact(context) ? 100.0 : 220.0;

  static double adaptiveRowHeight(BuildContext context) =>
      isLandscapeCompact(context) ? 48.0 : 56.0;
}
