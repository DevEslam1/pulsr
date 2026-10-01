// lib/core/responsive/adaptive_grid.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'breakpoints.dart';
import 'pulsr_responsive_tokens.dart';

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
    final vp = PulsrViewport.of(context);
    final breakpoint = vp.sizeClass;
    final isLandscape = vp.isLandscape;
    final width = vp.width;

    switch (type) {
      case GridType.albums:
      case GridType.artists:
      case GridType.playlists:
        switch (breakpoint) {
          case PulsrBreakpoint.compact:
            return isLandscape ? 3 : 2;
          case PulsrBreakpoint.medium:
            return isLandscape ? 4 : 3;
          case PulsrBreakpoint.expanded:
            return isLandscape ? 5 : 4;
          case PulsrBreakpoint.large:
            final calculated =
                (width / (customMinItemWidth ?? minCardWidth)).floor();
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

  /// Target-item-width based dynamic column resolver.
  static int columnsFor(
    BuildContext context, {
    required double minItemWidth,
    required double spacing,
    double? maxColumns,
  }) {
    final vp = PulsrViewport.of(context);
    final availableWidth =
        math.min(vp.width, vp.contentMaxWidth) - (vp.pagePadding * 2);
    int cols = (availableWidth / (minItemWidth + spacing)).floor();
    if (maxColumns != null) cols = cols.clamp(1, maxColumns.toInt());
    return cols.clamp(1, 12);
  }

  // ── Presets ──────────────────────────────────────────────────────────────

  /// Album grid preset (min width 150, spacing 14).
  static int albumGrid(BuildContext context) =>
      columnsFor(context, minItemWidth: 150.0, spacing: 14.0);

  /// Artist circle grid preset (min width 130, spacing 14).
  static int artistGrid(BuildContext context) =>
      columnsFor(context, minItemWidth: 130.0, spacing: 14.0);

  /// Song list card grid preset (min width 280, spacing 4).
  static int songGrid(BuildContext context) =>
      columnsFor(context, minItemWidth: 280.0, spacing: 4.0);

  /// Category card grid preset (min width 160, spacing 12).
  static int categoryGrid(BuildContext context) =>
      columnsFor(context, minItemWidth: 160.0, spacing: 12.0);

  /// Playlist card grid preset (min width 170, spacing 14).
  static int playlistGrid(BuildContext context) =>
      columnsFor(context, minItemWidth: 170.0, spacing: 14.0);

  /// Calculates columns specifically for song lists.
  static int songColumns(BuildContext context) =>
      columns(context, type: GridType.songs);

  /// Computes dynamic columns given a minimum item width and constraints.
  static int dynamicColumns(
    BuildContext context, {
    required double minItemWidth,
    int minColumns = 1,
    int maxColumns = 8,
    double? horizontalPadding,
  }) {
    final vp = PulsrViewport.of(context);
    final pad = horizontalPadding ?? (vp.pagePadding * 2);
    final width = math.min(vp.width, vp.contentMaxWidth);
    final usableWidth = math.max(0.0, width - pad);
    final count = (usableWidth / minItemWidth).floor();
    return count.clamp(minColumns, maxColumns);
  }
}

/// A container that constrains content to a readable maximum width
/// and centers it on large displays.
class PulsrContentConstraint extends StatelessWidget {
  final Widget child;
  final double? maxWidth;
  final AlignmentGeometry alignment;

  const PulsrContentConstraint({
    super.key,
    required this.child,
    this.maxWidth,
    this.alignment = Alignment.topCenter,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveMaxWidth =
        maxWidth ?? PulsrViewport.of(context).contentMaxWidth;
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: effectiveMaxWidth),
        child: child,
      ),
    );
  }
}
