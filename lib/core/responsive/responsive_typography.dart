import 'package:flutter/material.dart';
import '../constants/app_typography.dart';
import 'breakpoints.dart';

/// Responsive typography extension and text-scaling enforcement.
class PulsrResponsiveTypography {
  final PulsrBreakpoint breakpoint;

  const PulsrResponsiveTypography(this.breakpoint);

  /// 32 compact -> 36 medium -> 40 expanded/large
  double get displayLarge => switch (breakpoint) {
        PulsrBreakpoint.compact => AppFontSize.displayLarge,
        PulsrBreakpoint.medium => 36.0,
        PulsrBreakpoint.expanded || PulsrBreakpoint.large => 40.0,
      };

  /// 28 compact -> 32 medium -> 34 expanded/large
  double get display => switch (breakpoint) {
        PulsrBreakpoint.compact => AppFontSize.display,
        PulsrBreakpoint.medium => 32.0,
        PulsrBreakpoint.expanded || PulsrBreakpoint.large => 34.0,
      };

  /// 24 compact -> 26 medium -> 28 expanded/large
  double get headline => switch (breakpoint) {
        PulsrBreakpoint.compact => AppFontSize.headline,
        PulsrBreakpoint.medium => 26.0,
        PulsrBreakpoint.expanded || PulsrBreakpoint.large => 28.0,
      };

  /// 20 compact -> 22 medium -> 24 expanded/large
  double get titleLarge => switch (breakpoint) {
        PulsrBreakpoint.compact => AppFontSize.titleLarge,
        PulsrBreakpoint.medium => 22.0,
        PulsrBreakpoint.expanded || PulsrBreakpoint.large => 24.0,
      };

  /// 18 compact -> 19 medium -> 20 expanded/large
  double get title => switch (breakpoint) {
        PulsrBreakpoint.compact => AppFontSize.title,
        PulsrBreakpoint.medium => 19.0,
        PulsrBreakpoint.expanded || PulsrBreakpoint.large => 20.0,
      };

  /// 16 compact -> 17 medium -> 18 expanded/large
  double get bodyLarge => switch (breakpoint) {
        PulsrBreakpoint.compact => AppFontSize.bodyLarge,
        PulsrBreakpoint.medium => 17.0,
        PulsrBreakpoint.expanded || PulsrBreakpoint.large => 18.0,
      };

  /// 14 compact -> 14.5 medium -> 15 expanded/large
  double get body => switch (breakpoint) {
        PulsrBreakpoint.compact => AppFontSize.body,
        PulsrBreakpoint.medium => 14.5,
        PulsrBreakpoint.expanded || PulsrBreakpoint.large => 15.0,
      };

  /// 13 compact -> 13.5 medium -> 14 expanded/large
  double get bodySmall => switch (breakpoint) {
        PulsrBreakpoint.compact => AppFontSize.bodySmall,
        PulsrBreakpoint.medium => 13.5,
        PulsrBreakpoint.expanded || PulsrBreakpoint.large => 14.0,
      };

  /// 12 compact -> 12.5 medium -> 13 expanded/large
  double get label => switch (breakpoint) {
        PulsrBreakpoint.compact => AppFontSize.label,
        PulsrBreakpoint.medium => 12.5,
        PulsrBreakpoint.expanded || PulsrBreakpoint.large => 13.0,
      };

  /// 11 compact -> 11.5 medium -> 12 expanded/large
  double get caption => switch (breakpoint) {
        PulsrBreakpoint.compact => AppFontSize.caption,
        PulsrBreakpoint.medium => 11.5,
        PulsrBreakpoint.expanded || PulsrBreakpoint.large => 12.0,
      };

  /// Clamps the ambient [TextScaler] between [minScale] and [maxScale].
  static TextScaler clampedTextScaler(
    BuildContext context, {
    double minScale = 0.85,
    double maxScale = 1.5,
  }) {
    final scaler = MediaQuery.textScalerOf(context);
    return scaler.clamp(minScaleFactor: minScale, maxScaleFactor: maxScale);
  }
}

/// A scope widget that clamps the ambient MediaQuery's text scaler
/// between 0.85x and 1.5x so accessibility scales cleanly without breaking UI.
class PulsrTextScaleScope extends StatelessWidget {
  final Widget child;
  final double minScale;
  final double maxScale;

  const PulsrTextScaleScope({
    super.key,
    required this.child,
    this.minScale = 0.85,
    this.maxScale = 1.5,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = PulsrResponsiveTypography.clampedTextScaler(
      context,
      minScale: minScale,
      maxScale: maxScale,
    );
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: clamped),
      child: child,
    );
  }
}

/// BuildContext extension for responsive typography.
extension ResponsiveTypographyExtension on BuildContext {
  PulsrResponsiveTypography get typography =>
      PulsrResponsiveTypography(breakpoint);
}
