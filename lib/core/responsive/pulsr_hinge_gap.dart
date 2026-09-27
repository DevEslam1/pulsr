// lib/core/responsive/pulsr_hinge_gap.dart
import 'package:flutter/material.dart';
import 'pulsr_responsive_tokens.dart';

/// Renders a spacer matching the physical foldable hinge or seam on dual-screen / foldable devices.
/// Returns [SizedBox.shrink] on standard monolithic displays.
class PulsrHingeGap extends StatelessWidget {
  final Axis axis;

  const PulsrHingeGap({
    super.key,
    this.axis = Axis.horizontal,
  });

  const PulsrHingeGap.horizontal({super.key}) : axis = Axis.horizontal;
  const PulsrHingeGap.vertical({super.key}) : axis = Axis.vertical;

  @override
  Widget build(BuildContext context) {
    final vp = PulsrViewport.of(context);
    final hinge = vp.hinge;
    if (hinge == null) return const SizedBox.shrink();

    if (axis == Axis.horizontal) {
      final width = hinge.bounds.width;
      return width > 0 ? SizedBox(width: width) : const SizedBox.shrink();
    } else {
      final height = hinge.bounds.height;
      return height > 0 ? SizedBox(height: height) : const SizedBox.shrink();
    }
  }
}
