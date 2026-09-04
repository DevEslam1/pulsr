import 'package:flutter/material.dart';

enum WindowClass { compact, medium, expanded }

/// Adaptive layout engine: phone → bottom nav, tablet → side rail + grids.
abstract class Adaptive {
  static const double compactBreakpoint = 600;
  static const double tabletBreakpoint = 700;
  static const double railExtendedBreakpoint = 1000;
  static const double maxContentWidth = 1160;
  static const double maxSheetWidth = 620;

  static double widthOf(BuildContext context) =>
      MediaQuery.sizeOf(context).width;
  static double heightOf(BuildContext context) =>
      MediaQuery.sizeOf(context).height;

  static WindowClass windowOf(BuildContext context) {
    final w = widthOf(context);
    if (w >= 1200) return WindowClass.expanded;
    if (w >= tabletBreakpoint) return WindowClass.medium;
    return WindowClass.compact;
  }

  static bool isTablet(BuildContext context) =>
      windowOf(context) != WindowClass.compact;

  static bool isLandscape(BuildContext context) =>
      MediaQuery.orientationOf(context) == Orientation.landscape;

  /// Returns true when screen width/orientation is ideal for a 2-pane master-detail arrangement.
  static bool isTwoPane(BuildContext context) {
    final w = widthOf(context);
    final h = heightOf(context);
    return isLandscape(context) || (w >= tabletBreakpoint && w > h);
  }

  static bool isTabletPortrait(BuildContext context) =>
      isTablet(context) && !isLandscape(context);

  static bool isTabletLandscape(BuildContext context) =>
      isTablet(context) && isLandscape(context);

  static bool isLargeTablet(BuildContext context) =>
      widthOf(context) >= 900;

  /// Optimal column count for song/track tile lists across phone, tablet portrait, and tablet landscape
  static int trackGridColumns(BuildContext context) {
    final w = widthOf(context);
    if (w >= 1200) return 3;
    if (w >= tabletBreakpoint || (isLandscape(context) && w >= 600)) return 2;
    return 1;
  }

  /// Responsive column count for grids dynamically computed from available width.
  static int gridColumns(
    BuildContext context, {
    required double minItemWidth,
    int phoneColumns = 2,
    int maxColumns = 8,
  }) {
    final w = widthOf(context);
    final isTab = isTablet(context);
    final railWidth =
        isTab ? (w >= railExtendedBreakpoint ? 232.0 : 92.0) : 0.0;
    final available = (w - railWidth).clamp(0.0, maxContentWidth);
    final usable = available - pagePadding(context) * 2;
    final calculated = (usable / minItemWidth).floor();
    return calculated.clamp(phoneColumns, maxColumns);
  }

  static double pagePadding(BuildContext context) {
    final w = widthOf(context);
    if (w >= 1200) return 32;
    if (w >= tabletBreakpoint) return 24;
    if (w < 360) return 12;
    return 16;
  }

  /// Center-rail constraint for readable ultra-wide layouts.
  static BoxConstraints contentConstraints(BuildContext context) =>
      const BoxConstraints(maxWidth: maxContentWidth);

  /// Max-width constraint for bottom sheets / dialogs on tablets & desktops.
  static BoxConstraints sheetConstraints(BuildContext context) =>
      const BoxConstraints(maxWidth: maxSheetWidth);
}

extension AdaptiveContextX on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;
  double get screenHeight => MediaQuery.sizeOf(this).height;
  bool get isLandscape =>
      MediaQuery.orientationOf(this) == Orientation.landscape;
  bool get isTablet => Adaptive.isTablet(this);
  bool get isTabletPortrait => Adaptive.isTabletPortrait(this);
  bool get isTabletLandscape => Adaptive.isTabletLandscape(this);
  bool get isLargeTablet => Adaptive.isLargeTablet(this);
  bool get isTwoPane => Adaptive.isTwoPane(this);
  int get trackGridColumns => Adaptive.trackGridColumns(this);
  double get pagePadding => Adaptive.pagePadding(this);
  WindowClass get windowClass => Adaptive.windowOf(this);

  T responsive<T>({
    required T phone,
    T? tablet,
    T? desktop,
  }) {
    final w = windowClass;
    if (w == WindowClass.expanded && desktop != null) return desktop;
    if ((w == WindowClass.medium || w == WindowClass.expanded) &&
        tablet != null) {
      return tablet;
    }
    return phone;
  }
}
