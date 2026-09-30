// lib/core/responsive/pulsr_layout_metrics.dart
import 'package:flutter/material.dart';
import '../utils/adaptive.dart';
import '../widgets/pulsr_dock_tracker.dart';
import 'breakpoints.dart';

/// Archetypes for canonical Pulsr screen layouts.
enum PulsrLayoutArchetype {
  /// Song list, downloads, queue (1-col phone -> 2/3-col grid on wide).
  list,

  /// Album, artist, genre, year, playlist (hero + tracklist / 2-pane).
  detail,

  /// Home, Library, Search (sections, carousels, rails).
  browse,

  /// Player, Karaoke (immersive, responsive split).
  immersive,
}

/// Unified source of truth for responsive layout metrics, spacing,
/// constraints, hero scaling, field sizing, and dock dimensions.
class PulsrLayoutMetrics {
  // ── Canonical Content Max-Widths (G1 single source of truth) ─────────────
  static double contentMaxWidth(BuildContext context) =>
      switch (PulsrBreakpoint.of(context)) {
        PulsrBreakpoint.compact => 640.0,
        PulsrBreakpoint.medium => 720.0,
        PulsrBreakpoint.expanded => 860.0,
        PulsrBreakpoint.large => 1000.0,
      };

  static BoxConstraints contentConstraints(BuildContext context) =>
      BoxConstraints(maxWidth: contentMaxWidth(context));

  // ── Hero Heights as Viewport Percentage (Fixes G2) ─────────────────────────
  static double heroHeight(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    if (PulsrBreakpoint.isLandscape(context)) {
      return (h * 0.42).clamp(180.0, 300.0);
    }
    return (h * 0.36).clamp(220.0, 380.0);
  }

  // ── Standard Input / Field Heights (Fixes G3, G6) ──────────────────────────
  static double fieldHeight(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.25);
    return 44.0 * scale;
  }

  // ── Dock Metrics & Math (Fixes G9) ─────────────────────────────────────────
  static const double miniPlayerHeight = 84.0;
  static const double dockPillGap = 8.0;
  static const double peekOffset = 14.0;

  static double navBarHeight(BuildContext context) =>
      Adaptive.isTablet(context) ? 68.0 : 64.0;

  static double navBarPaddingVertical(BuildContext context) =>
      Adaptive.isTablet(context) ? 14.0 : 10.0;

  static double navBarTotalHeight(BuildContext context) =>
      navBarHeight(context) + navBarPaddingVertical(context);

  /// Safe bottom padding for scrollables (Fixes Phase 1.2)
  static double scrollBottom(BuildContext context, {double extra = 24.0}) {
    final dockH = PulsrDockTracker.dockHeight.value;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final effectiveDock =
        dockH > 0 ? dockH : (navBarTotalHeight(context) + miniPlayerHeight);
    return effectiveDock + safeBottom + extra;
  }

  // ── Player Responsive Split Threshold (Fixes G7, Phase 2.3) ───────────────
  /// Returns whether player themes should render in 2-pane horizontal split mode.
  /// Landscape phone always splits. Wide tablet splits.
  /// Wide phone in portrait (< 720dp or portrait) does NOT split.
  static bool isPlayerSplitMode(
    BuildContext context, [
    BoxConstraints? constraints,
  ]) {
    final width = constraints?.maxWidth ?? MediaQuery.sizeOf(context).width;
    final height = constraints?.maxHeight ?? MediaQuery.sizeOf(context).height;
    // Panes narrower than 620dp cannot comfortably accommodate a horizontal 2-pane split
    // (e.g. tablet player left pane or narrow window). They must remain a single column.
    if (width < 620) return false;

    // If the available area is taller than wide (portrait or near-square, e.g. tablet player left pane
    // in ResponsivePlayerLayout), a horizontal 2-pane split would severely crush both artwork and controls.
    if (width <= height * 1.15) return false;

    // Landscape phone or wide view: split into hero artwork + controls/lyrics/queue
    if (PulsrBreakpoint.isLandscape(context)) return true;

    // In portrait/square, only split if it is a wide tablet (>= 720) and aspect ratio allows
    return Adaptive.isTablet(context) && width >= 720 && width > height * 0.85;
  }

  // ── Sheet / Dialog Adaptive Decisions (Fixes G6, Phase 2.4) ────────────────
  static bool shouldUseDialogForSheet(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isLandscapePhone =
        PulsrBreakpoint.isLandscape(context) && size.height < 480;
    return !context.isCompact || isLandscapePhone;
  }
}

/// Extension on BuildContext for quick access to PulsrLayoutMetrics.
extension PulsrLayoutMetricsContextX on BuildContext {
  double get contentMaxWidth => PulsrLayoutMetrics.contentMaxWidth(this);
  BoxConstraints get contentConstraints =>
      PulsrLayoutMetrics.contentConstraints(this);
  double get heroHeight => PulsrLayoutMetrics.heroHeight(this);
  double get fieldHeight => PulsrLayoutMetrics.fieldHeight(this);
  double get scrollBottomPadding => PulsrLayoutMetrics.scrollBottom(this);
  bool isPlayerSplit([BoxConstraints? constraints]) =>
      PulsrLayoutMetrics.isPlayerSplitMode(this, constraints);
}
