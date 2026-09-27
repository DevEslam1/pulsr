import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'breakpoints.dart';

/// Semantic types of content grids in Pulsr.
enum GridType {
  /// Albums & collections cards (artwork + title + subtitle).
  albums,

  /// Artist circular avatar cards.
  artists,

  /// Playlists cover cards.
  playlists,

  /// Song/track rows and tiles.
  songs,
}

/// Adaptive grid calculation and container for Pulsr content screens.
class PulsrAdaptiveGrid {
  static const double minCardWidth = 160.0;
  static const double minSongTileWidth = 300.0;
  static const double maxContentWidth = 1200.0;

  /// Calculates the optimal column count for a grid type based on screen tier and posture.
  static int columns(
    BuildContext context, {
    GridType type = GridType.albums,
    int? customMinItemWidth,
  }) {
    final breakpoint = PulsrBreakpoint.of(context);
    final isLandscape = PulsrBreakpoint.isLandscape(context);
    final width = MediaQuery.sizeOf(context).width;

    switch (type) {
      case GridType.albums:
      case GridType.artists:
      case GridType.playlists:
        switch (breakpoint) {
          case PulsrBreakpoint.compact:
            return isLandscape ? 3 : 2;
          case PulsrBreakpoint.medium:
            // Medium width (600 - 839)
            return isLandscape ? 4 : 3;
          case PulsrBreakpoint.expanded:
            // Expanded width (840 - 1199)
            return isLandscape ? 5 : 4;
          case PulsrBreakpoint.large:
            // Large width (1200+)
            final calculated = (width / (customMinItemWidth ?? minCardWidth)).floor();
            return calculated.clamp(6, 8);
        }

      case GridType.songs:
        switch (breakpoint) {
          case PulsrBreakpoint.compact:
            return isLandscape ? 2 : 1;
          case PulsrBreakpoint.medium:
            return 2;
          case PulsrBreakpoint.expanded:
            return 2;
          case PulsrBreakpoint.large:
            return 3;
        }
    }
  }

  /// Calculates columns specifically for song lists.
  static int songColumns(BuildContext context) =>
      columns(context, type: GridType.songs);

  /// Computes dynamic columns given a minimum item width and constraints.
  static int dynamicColumns(
    BuildContext context, {
    required double minItemWidth,
    int minColumns = 1,
    int maxColumns = 8,
    double horizontalPadding = 32.0,
  }) {
    final width = math.min(
      MediaQuery.sizeOf(context).width,
      maxContentWidth,
    );
    final usableWidth = math.max(0.0, width - horizontalPadding);
    final count = (usableWidth / minItemWidth).floor();
    return count.clamp(minColumns, maxColumns);
  }
}

/// A container that constrains content to a readable maximum width (1200dp)
/// and centers it on large displays.
class PulsrContentConstraint extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final AlignmentGeometry alignment;

  const PulsrContentConstraint({
    super.key,
    required this.child,
    this.maxWidth = PulsrAdaptiveGrid.maxContentWidth,
    this.alignment = Alignment.topCenter,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
