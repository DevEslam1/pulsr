// lib/core/widgets/shimmer_skeleton.dart
import 'package:flutter/material.dart';
import '../motion/pulsr_motion.dart';
import '../theme/aura_theme.dart';

/// A shimmering placeholder block used by list/grid loading states.
///
/// Honours the platform reduce-motion switch: when animations are disabled the
/// block renders as a static, non-oscillating surface so nothing pulses.
class SkeletonBox extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;

  const SkeletonBox({
    super.key,
    this.width,
    this.height = 16,
    this.radius = 10,
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  void _syncAnimation() {
    if (context.motionEnabled) {
      if (!_controller.isAnimating) _controller.repeat();
    } else if (_controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final base = p.surfaceContainer;
    final highlight = p.surfaceContainerHigh;

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.radius),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            return DecoratedBox(
              decoration: BoxDecoration(
                color: base,
                gradient: LinearGradient(
                  begin: Alignment(-2.0 + 4.0 * t, -0.4),
                  end: Alignment(-1.0 + 4.0 * t, 0.4),
                  colors: [base, highlight, base],
                  stops: const [0.30, 0.50, 0.70],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A single shimmering text line.
class SkeletonLine extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;

  const SkeletonLine({
    super.key,
    this.width,
    this.height = 12,
    this.radius = 6,
  });

  @override
  Widget build(BuildContext context) =>
      SkeletonBox(width: width, height: height, radius: radius);
}

/// A horizontal row skeleton: artwork + two stacked lines, matching the
/// geometry of `SongTile` so lists don't jump when real data arrives.
class SkeletonSongRow extends StatelessWidget {
  final double artworkSize;
  final double radius;

  const SkeletonSongRow({
    super.key,
    this.artworkSize = 48,
    this.radius = 12,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          SkeletonBox(
            width: artworkSize,
            height: artworkSize,
            radius: radius,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SkeletonLine(width: 180, height: 13),
                SizedBox(height: 8),
                SkeletonLine(width: 110, height: 11),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A vertical list of [SkeletonSongRow]s for full-screen loading states.
class SkeletonList extends StatelessWidget {
  final int itemCount;
  final double artworkSize;
  final EdgeInsetsGeometry padding;

  const SkeletonList({
    super.key,
    this.itemCount = 8,
    this.artworkSize = 48,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: padding,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: itemCount,
      itemBuilder: (context, _) => SkeletonSongRow(artworkSize: artworkSize),
    );
  }
}

/// A grid of square art skeletons (albums/artists/playlists loading state).
class SkeletonGrid extends StatelessWidget {
  final int itemCount;
  final int columns;
  final double aspectRatio;
  final EdgeInsetsGeometry padding;

  const SkeletonGrid({
    super.key,
    this.itemCount = 6,
    this.columns = 2,
    this.aspectRatio = 0.78,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: padding,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: itemCount,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        childAspectRatio: aspectRatio,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemBuilder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(
              child: SkeletonBox(
                width: double.infinity,
                height: double.infinity,
                radius: 18,
              ),
            ),
            const SizedBox(height: 8),
            const SkeletonLine(width: 120, height: 12),
            const SizedBox(height: 6),
            SkeletonLine(width: 70, height: 10),
          ],
        );
      },
    );
  }
}
