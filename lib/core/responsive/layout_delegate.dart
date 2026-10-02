import 'package:flutter/material.dart';
import 'breakpoints.dart';

/// Layout mode for the main application shell based on screen tier and posture.
enum ShellLayoutMode {
  /// Phone portrait, small foldables closed (mini-player stacked above bottom nav).
  bottomNav,

  /// Phone landscape / medium landscape with short vertical height (single 56dp horizontal dock).
  bottomNavWide,

  /// Medium portrait (small tablet, open foldable portrait) or compact landscape tablet.
  sideRailCollapsed,

  /// Expanded landscape (tablet landscape, wide foldables).
  sideRailExpanded,

  /// Desktop or ultra-wide tablets (1200dp+).
  sideRailFull,
}

/// Decides and provides layout geometry and configuration for the app shell.
class PulsrLayoutDelegate {
  final ShellLayoutMode layoutMode;
  final PulsrBreakpoint breakpoint;
  final Orientation orientation;
  final bool hasHinge;
  final double screenWidth;
  final double screenHeight;

  const PulsrLayoutDelegate({
    required this.layoutMode,
    required this.breakpoint,
    required this.orientation,
    required this.hasHinge,
    required this.screenWidth,
    required this.screenHeight,
  });

  /// Derives the layout delegate from the active [BuildContext].
  factory PulsrLayoutDelegate.of(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final orientation = MediaQuery.orientationOf(context);
    final breakpoint = PulsrBreakpoint.of(context);
    final hasHinge = PulsrBreakpoint.hasHinge(context);

    final mode = resolveMode(
      breakpoint: breakpoint,
      orientation: orientation,
      hasHinge: hasHinge,
      width: size.width,
      height: size.height,
    );

    return PulsrLayoutDelegate(
      layoutMode: mode,
      breakpoint: breakpoint,
      orientation: orientation,
      hasHinge: hasHinge,
      screenWidth: size.width,
      screenHeight: size.height,
    );
  }

  /// Pure resolver for testability and headless calculation.
  static ShellLayoutMode resolveMode({
    required PulsrBreakpoint breakpoint,
    required Orientation orientation,
    required bool hasHinge,
    required double width,
    required double height,
  }) {
    final isLandscape = orientation == Orientation.landscape;

    if (breakpoint == PulsrBreakpoint.large) {
      return ShellLayoutMode.sideRailFull;
    }

    if (breakpoint == PulsrBreakpoint.expanded) {
      return isLandscape
          ? ShellLayoutMode.sideRailExpanded
          : ShellLayoutMode.sideRailCollapsed;
    }

    if (breakpoint == PulsrBreakpoint.medium) {
      if (isLandscape) {
        // Landscape phone (e.g. 844x390) needs wide bottom nav, while a tablet
        // or foldable with adequate height (>= 600) can use the side rail.
        if (height < PulsrBreakpoint.shortHeightThreshold) {
          return ShellLayoutMode.bottomNavWide;
        } else {
          return ShellLayoutMode.sideRailCollapsed;
        }
      } else {
        // Medium portrait (small tablet or foldable unfolded)
        return ShellLayoutMode.sideRailCollapsed;
      }
    }

    // Compact (< 600dp width)
    if (isLandscape) {
      return ShellLayoutMode.bottomNavWide;
    }
    return ShellLayoutMode.bottomNav;
  }

  /// Whether the navigation sidebar / rail should be displayed.
  bool get showRail =>
      layoutMode == ShellLayoutMode.sideRailCollapsed ||
      layoutMode == ShellLayoutMode.sideRailExpanded ||
      layoutMode == ShellLayoutMode.sideRailFull;

  /// Whether the navigation rail should default to its expanded (labeled) state.
  bool get railExpanded =>
      layoutMode == ShellLayoutMode.sideRailExpanded ||
      layoutMode == ShellLayoutMode.sideRailFull;

  /// Width allocated for navigation (either rail width or double.infinity for bottom bars).
  double get navWidth {
    switch (layoutMode) {
      case ShellLayoutMode.bottomNav:
      case ShellLayoutMode.bottomNavWide:
        return double.infinity;
      case ShellLayoutMode.sideRailCollapsed:
        return 64.0;
      case ShellLayoutMode.sideRailExpanded:
        return 240.0;
      case ShellLayoutMode.sideRailFull:
        return 260.0;
    }
  }

  /// Maximum content width constraint to avoid unreadable line lengths on wide screens.
  ///
  /// Delegates to the canonical per-breakpoint value on [PulsrBreakpoint] so
  /// the shell and the content surfaces agree.
  double get contentMaxWidth => breakpoint.contentMaxWidth;

  /// Effective player bar height for the current layout mode.
  double get playerBarHeight {
    switch (layoutMode) {
      case ShellLayoutMode.bottomNav:
        return 148.0; // mini player + bottom nav stacked
      case ShellLayoutMode.bottomNavWide:
        return 56.0; // single horizontal row
      case ShellLayoutMode.sideRailCollapsed:
      case ShellLayoutMode.sideRailExpanded:
      case ShellLayoutMode.sideRailFull:
        return 90.0;
    }
  }

  /// Whether the secondary side inspector (queue / lyrics) can be shown.
  bool get showSideInspector =>
      showRail &&
      (layoutMode == ShellLayoutMode.sideRailExpanded ||
          layoutMode == ShellLayoutMode.sideRailFull ||
          orientation == Orientation.landscape) &&
      screenWidth >= 840;
}

extension PulsrLayoutDelegateContextX on BuildContext {
  PulsrLayoutDelegate get layoutDelegate => PulsrLayoutDelegate.of(this);
  bool get isSideInspectorAvailable => layoutDelegate.showSideInspector;
}
