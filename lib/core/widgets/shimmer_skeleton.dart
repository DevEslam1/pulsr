// lib/core/widgets/shimmer_skeleton.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../motion/pulsr_motion.dart';
import '../theme/aura_theme.dart';
import 'package:pulsr/core/constants/app_spacing.dart';

/// Coordinates the shimmer sweep for every [SkeletonBox] beneath it.
///
/// A single [AnimationController] drives one full-screen highlight band through
/// a [ShaderMask], so a screen with dozens of placeholder blocks stays perfectly
/// in sync and only burns one ticker. When reduce-motion is on the mask is
/// skipped entirely and the blocks render static.
class SkeletonShimmer extends StatefulWidget {
  final Widget child;

  const SkeletonShimmer({super.key, required this.child});

  @override
  State<SkeletonShimmer> createState() => _SkeletonShimmerState();
}

class _SkeletonShimmerState extends State<SkeletonShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = context.motionMs(1400);
    if (context.motionEnabled) {
      if (!_controller.isAnimating) _controller.repeat();
    } else if (_controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = _SkeletonShimmerScope(present: true, child: widget.child);
    if (!context.motionEnabled) return scope;

    final isDark = context.palette.isDark;
    final highlight =
        (isDark ? Colors.white : Colors.black).withValues(alpha: 0.10);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment(-1.6 + 3.2 * t, 0),
              end: Alignment(-0.6 + 3.2 * t, 0),
              colors: [Colors.transparent, highlight, Colors.transparent],
              stops: const [0.15, 0.5, 0.85],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: scope,
    );
  }
}

class _SkeletonShimmerScope extends InheritedWidget {
  final bool present;

  const _SkeletonShimmerScope({required this.present, required super.child});

  @override
  bool updateShouldNotify(_SkeletonShimmerScope oldWidget) => false;
}

/// A placeholder block used by list/grid loading states.
///
/// When it lives under a [SkeletonShimmer] it renders a static surface and lets
/// the ancestor sweep the highlight (one ticker for the whole screen). Standalone
/// it falls back to its own shimmer. Honours the reduce-motion switch either way.
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
    _controller.duration = context.motionMs(1300);
    _syncAnimation();
  }

  void _syncAnimation() {
    // A parent shimmer owns the sweep; don't run a redundant ticker.
    if (_hasSharedShimmer) {
      if (_controller.isAnimating) _controller.stop();
      return;
    }
    if (context.motionEnabled) {
      if (!_controller.isAnimating) _controller.repeat();
    } else if (_controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  bool get _hasSharedShimmer =>
      context.dependOnInheritedWidgetOfExactType<_SkeletonShimmerScope>() !=
      null;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final base = p.surfaceContainerHigh;

    // Shared shimmer: flat surface, ancestor sweeps the highlight.
    if (_hasSharedShimmer) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            color: base,
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          return SizedBox(
            width: widget.width,
            height: widget.height,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(-2.0 + 4.0 * t, -0.4),
                  end: Alignment(-1.0 + 4.0 * t, 0.4),
                  colors: [base, p.surfaceContainer, base],
                  stops: const [0.30, 0.50, 0.70],
                ),
              ),
            ),
          );
        },
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
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      child: Row(
        children: [
          SkeletonBox(
            width: artworkSize,
            height: artworkSize,
            radius: radius,
          ),
          const SizedBox(width: AppSpacing.sm),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SkeletonLine(width: 180, height: 13),
                SizedBox(height: AppSpacing.xs),
                SkeletonLine(width: 110, height: 11),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Entrance cascade for a list of placeholder rows: each item fades + rises
/// with a small stagger. Collapses to instant under reduce-motion.
Widget _cascade(int index, Widget child, bool enabled) {
  if (!enabled) return child;
  return child
      .animate()
      .fadeIn(duration: 300.ms, delay: (index * 45).ms, curve: Curves.easeOut)
      .slideY(
        begin: 0.08,
        end: 0,
        duration: 300.ms,
        delay: (index * 45).ms,
        curve: Curves.easeOutCubic,
      );
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
    final enabled = context.motionEnabled;
    final list = ListView.builder(
      padding: padding,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: itemCount,
      itemBuilder: (context, i) =>
          _cascade(i, SkeletonSongRow(artworkSize: artworkSize), enabled),
    );
    return SkeletonShimmer(child: list);
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
    this.padding = const EdgeInsets.all(AppSpacing.md),
  });

  @override
  Widget build(BuildContext context) {
    final grid = GridView.builder(
      padding: padding,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: itemCount,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        childAspectRatio: aspectRatio,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemBuilder: (context, i) {
        return _cascade(
          i,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Expanded(
                child: SkeletonBox(
                  width: double.infinity,
                  height: double.infinity,
                  radius: 18,
                ),
              ),
              SizedBox(height: AppSpacing.xs),
              SkeletonLine(width: 120, height: 12),
              SizedBox(height: AppSpacing.s6),
              SkeletonLine(width: 70, height: 10),
            ],
          ),
          context.motionEnabled,
        );
      },
    );
    return SkeletonShimmer(child: grid);
  }
}
