// lib/core/widgets/pulsr_progress_bar.dart
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_radii.dart';
import '../motion/pulsr_motion.dart';
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
        strokeCap: StrokeCap.round,
        valueColor: color != null ? AlwaysStoppedAnimation<Color>(color) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final activeColor = color ?? p.accent;
    final trackColor = backgroundColor ??
        (p.isDark ? AppColors.specularAt(0.08) : p.surfaceContainerHigh);
    final radius = borderRadius ?? AppRadii.full;

    // Indeterminate mode delegates to LinearProgressIndicator inside a recessed pill
    if (value == null) {
      return ClipRRect(
        borderRadius: radius,
        child: SizedBox(
          height: height,
          child: LinearProgressIndicator(
            value: null,
            valueColor: AlwaysStoppedAnimation<Color>(activeColor),
            backgroundColor: trackColor,
          ),
        ),
      );
    }

    final clamped = value!.clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: radius,
      child: Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          color: trackColor,
          borderRadius: radius,
        ),
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: clamped, end: clamped),
          duration: context.motionMs(180),
          curve: Curves.easeOutCubic,
          builder: (context, animatedValue, _) {
            if (animatedValue <= 0.0) {
              return const SizedBox.shrink();
            }
            return FractionallySizedBox(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: animatedValue.clamp(0.0, 1.0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  gradient: LinearGradient(
                    colors: [
                      activeColor.withValues(alpha: 0.78),
                      activeColor,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: activeColor.withValues(alpha: 0.35),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
