import 'package:flutter/material.dart';
import '../motion/pulsr_motion.dart';
import 'breakpoints.dart';

/// Responsive motion configuration scaling animation durations and spatial
/// distances according to screen size and physical travel distances.
class PulsrResponsiveMotion {
  final BuildContext context;
  final PulsrBreakpoint breakpoint;

  const PulsrResponsiveMotion(this.context, this.breakpoint);

  /// Scaling multiplier for animation durations based on screen size.
  double get durationScale => switch (breakpoint) {
        PulsrBreakpoint.compact => 1.0,
        PulsrBreakpoint.medium => 1.05,
        PulsrBreakpoint.expanded => 1.10,
        PulsrBreakpoint.large => 1.15,
      };

  /// Scaling multiplier for spatial slide and travel distances.
  double get distanceScale => switch (breakpoint) {
        PulsrBreakpoint.compact => 1.0,
        PulsrBreakpoint.medium => 1.25,
        PulsrBreakpoint.expanded => 1.5,
        PulsrBreakpoint.large => 1.75,
      };

  /// Resolves an animation duration considering both reduced-motion preferences
  /// and responsive screen size scaling.
  Duration duration(Duration base) {
    if (!PulsrMotion.isEnabled(context)) return Duration.zero;
    final ms = (base.inMilliseconds * durationScale).round();
    return Duration(milliseconds: ms);
  }

  /// Convenience wrapper for millisecond durations.
  Duration ms(int milliseconds) =>
      duration(Duration(milliseconds: milliseconds));

  /// Scales a spatial distance (e.g. slide transition offset) responsively.
  double distance(double baseDistance) => baseDistance * distanceScale;
}

/// BuildContext extension for responsive motion.
extension ResponsiveMotionExtension on BuildContext {
  PulsrResponsiveMotion get responsiveMotion =>
      PulsrResponsiveMotion(this, breakpoint);
}
