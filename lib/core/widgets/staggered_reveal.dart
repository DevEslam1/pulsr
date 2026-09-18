// lib/core/widgets/staggered_reveal.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../motion/pulsr_motion.dart';

/// Reveals [child] with a short fade + rise, staggered by [index].
///
/// Include the current sort/group signature in [groupKey]: because the key
/// changes whenever the ordering changes, every row re-mounts and replays the
/// entrance — which turns an instant "jump" re-sort into a smooth re-flow.
///
/// Collapses to an unanimated child under reduce-motion.
class StaggeredReveal extends StatelessWidget {
  final int index;
  final Object? groupKey;
  final Widget child;
  final double beginOffset;
  final bool horizontal;

  const StaggeredReveal({
    super.key,
    required this.index,
    required this.child,
    this.groupKey,
    this.beginOffset = 0.06,
    this.horizontal = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!context.motionEnabled) return child;
    final delay = (index.clamp(0, 14) * 20).ms;
    final anim = child
        .animate(key: ValueKey('${groupKey ?? ''}#${horizontal ? 'h' : 'v'}$index'))
        .fadeIn(duration: 240.ms, delay: delay, curve: Curves.easeOut);
    if (horizontal) {
      return anim.slideX(
        begin: beginOffset,
        end: 0,
        duration: 240.ms,
        delay: delay,
        curve: Curves.easeOutCubic,
      );
    }
    return anim.slideY(
      begin: beginOffset,
      end: 0,
      duration: 240.ms,
      delay: delay,
      curve: Curves.easeOutCubic,
    );
  }
}
