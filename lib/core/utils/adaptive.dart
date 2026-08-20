import 'package:flutter/material.dart';

enum WindowClass { compact, medium, expanded }

/// Adaptive layout engine: phone → bottom nav, tablet → side rail + grids.
abstract class Adaptive {
  static const double compactBreakpoint = 600;
  static const double tabletBreakpoint = 700;
  static const double railExtendedBreakpoint = 1000;
  static const double maxContentWidth = 1160;
  static const double maxSheetWidth = 620;

  static double widthOf(BuildContext context) => MediaQuery.sizeOf(context).width;
  static double heightOf(BuildContext context) => MediaQuery.sizeOf(context).height;

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

  /// Responsive column count for grids dynamically computed from available width.
  static int gridColumns(
    BuildContext context, {
    required double minItemWidth,
    int phoneColumns = 2,
    int maxColumns = 8,
  }) {
    final usable = widthOf(context) - pagePadding(context) * 2;
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
  bool get isLandscape => MediaQuery.orientationOf(this) == Orientation.landscape;
  bool get isTablet => Adaptive.isTablet(this);
  WindowClass get windowClass => Adaptive.windowOf(this);

  T responsive<T>({
    required T phone,
    T? tablet,
    T? desktop,
  }) {
    final w = windowClass;
    if (w == WindowClass.expanded && desktop != null) return desktop;
    if ((w == WindowClass.medium || w == WindowClass.expanded) && tablet != null) return tablet;
    return phone;
  }
}
