import 'package:flutter/material.dart';
import '../constants/app_radii.dart';
import '../theme/aura_theme.dart';

/// {@category DesignSystem}
/// Unified progress and loading indicator for Pulsr.
class PulsrProgressBar extends StatelessWidget {
  /// Progress value between 0.0 and 1.0. If null, displays indeterminate animation.
  final double? value;
  final Color? color;
  final Color? backgroundColor;
  final double height;
  final BorderRadius? borderRadius;

  const PulsrProgressBar({
    super.key,
    this.value,
    this.color,
    this.backgroundColor,
    this.height = 4.0,
    this.borderRadius,
  });

  /// Factory for linear determinate progress (e.g. scan, downloads).
  static Widget determinate({
    Key? key,
    required double value,
    double height = 4.0,
    Color? color,
    Color? backgroundColor,
    BorderRadius? borderRadius,
  }) {
    return PulsrProgressBar(
      key: key,
      value: value.clamp(0.0, 1.0),
      height: height,
      color: color,
      backgroundColor: backgroundColor,
      borderRadius: borderRadius,
    );
  }

  /// Factory for linear indeterminate progress bar.
  static Widget indeterminate({
    Key? key,
    double height = 4.0,
    Color? color,
    Color? backgroundColor,
    BorderRadius? borderRadius,
  }) {
    return PulsrProgressBar(
      key: key,
      value: null,
      height: height,
      color: color,
      backgroundColor: backgroundColor,
      borderRadius: borderRadius,
    );
  }

  /// Factory for small circular indicator (e.g. button loading state).
  static Widget circular({
    Key? key,
    double size = 18.0,
    double strokeWidth = 2.2,
    Color? color,
  }) {
    return SizedBox(
      key: key,
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth,
        valueColor: color != null ? AlwaysStoppedAnimation<Color>(color) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final activeColor = color ?? p.accent;
    final trackColor = backgroundColor ?? p.surfaceContainerHigh;
    final radius = borderRadius ?? AppRadii.full;

    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        height: height,
        child: LinearProgressIndicator(
          value: value?.clamp(0.0, 1.0),
          valueColor: AlwaysStoppedAnimation<Color>(activeColor),
          backgroundColor: trackColor,
        ),
      ),
    );
  }
}
