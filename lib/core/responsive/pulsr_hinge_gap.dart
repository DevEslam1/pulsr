// lib/core/responsive/pulsr_hinge_gap.dart
import 'package:material_ui/material_ui.dart';
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
      // Only reserve a horizontal gap when the physical hinge is vertical
      // (separating left/right panes in book posture). A tabletop horizontal
      // hinge spans the full display width and must not push content off-screen.
      final bounds = hinge.bounds;
      final isVerticalHinge = bounds.width > 0 &&
          bounds.height > bounds.width &&
          bounds.width < vp.width;
      return isVerticalHinge
          ? SizedBox(width: bounds.width)
          : const SizedBox.shrink();
    } else {
      // Only reserve a vertical gap when the physical hinge is horizontal
      // (separating top/bottom panes in tabletop posture).
      final bounds = hinge.bounds;
      final isHorizontalHinge = bounds.height > 0 &&
          bounds.width > bounds.height &&
          bounds.height < vp.height;
      return isHorizontalHinge
          ? SizedBox(height: bounds.height)
          : const SizedBox.shrink();
    }
  }
}
