// lib/core/responsive/pulsr_responsive_tokens.dart
import 'dart:math' as math;
import 'dart:ui' show DisplayFeature;
import 'package:flutter/material.dart';
import 'breakpoints.dart';

/// Physical and interaction classification of the current device.
enum PulsrDeviceClass {
  phone,
  tablet,
  foldable,
  desktop,
}

/// Navigation presentation paradigm based on viewport real estate.
enum PulsrNavMode {
  bottomBar,
  sideRail,
  sideRailExtended,
}

/// Audio player presentation paradigm based on screen geometry and aspect ratio.
enum PulsrPlayerMode {
  fullScreen,
  splitPane,
  compactOverlay,
}

/// Unified, immutable snapshot of the active viewport and its computed layout tokens.
@immutable
class PulsrViewport {
  final PulsrDeviceClass deviceClass;
  final Orientation orientation;
  final PulsrBreakpoint sizeClass;
  final double width;
  final double height;
  final bool isShortHeight;
  final bool isUltraWide;
  final bool hasHinge;
  final DisplayFeature? hinge;
  final TextScaler textScale;

  const PulsrViewport({
    required this.deviceClass,
    required this.orientation,
    required this.sizeClass,
    required this.width,
    required this.height,
    required this.isShortHeight,
    required this.isUltraWide,
    required this.hasHinge,
    this.hinge,
    required this.textScale,
  });

  /// Factory resolving the viewport directly from the active [BuildContext].
  factory PulsrViewport.fromContext(BuildContext context,
      [BoxConstraints? constraints]) {
    final mq = MediaQuery.maybeOf(context);
    final width = mq?.size.width ??
        (constraints?.maxWidth.isFinite == true
            ? constraints!.maxWidth
            : 390.0);
    final height = mq?.size.height ??
        (constraints?.maxHeight.isFinite == true
            ? constraints!.maxHeight
            : 844.0);

    final orientation =
        width > height ? Orientation.landscape : Orientation.portrait;
    final sizeClass = PulsrBreakpoint.fromWidth(width);
    final isShortHeight =
        height < 500.0 && orientation == Orientation.landscape;
    final isUltraWide = width >= 1200.0;

    final hinge = PulsrBreakpoint.hinge(context);
    final hasHinge = hinge != null;

    final smallestDim = math.min(width, height);
    final PulsrDeviceClass deviceClass;
    if (hasHinge) {
      deviceClass = PulsrDeviceClass.foldable;
    } else if (width >= 1200.0) {
      deviceClass = PulsrDeviceClass.desktop;
    } else if (smallestDim >= 600.0) {
      deviceClass = PulsrDeviceClass.tablet;
    } else {
      deviceClass = PulsrDeviceClass.phone;
    }

    final textScale = mq?.textScaler ?? TextScaler.noScaling;

    return PulsrViewport(
      deviceClass: deviceClass,
      orientation: orientation,
      sizeClass: sizeClass,
      width: width,
      height: height,
      isShortHeight: isShortHeight,
      isUltraWide: isUltraWide,
      hasHinge: hasHinge,
      hinge: hinge,
      textScale: textScale,
    );
  }

  // ── Computed Layout Tokens ───────────────────────────────────────────────

  /// Horizontal page margins (16 phone, 24 tablet, 32 large desktop).
  double get pagePadding {
    if (isShortHeight) return 12.0;
    return switch (sizeClass) {
      PulsrBreakpoint.compact => 16.0,
      PulsrBreakpoint.medium => 24.0,
      PulsrBreakpoint.expanded => 24.0,
      PulsrBreakpoint.large => 32.0,
    };
  }

  /// Maximum content width constraint preventing sprawling lines on wide screens.
  double get contentMaxWidth {
    return switch (sizeClass) {
      PulsrBreakpoint.compact => 560.0,
      PulsrBreakpoint.medium => 780.0,
      PulsrBreakpoint.expanded => 960.0,
      PulsrBreakpoint.large => 1100.0,
    };
  }

  /// BoxConstraints applying [contentMaxWidth].
  BoxConstraints get contentConstraints =>
      BoxConstraints(maxWidth: contentMaxWidth);

  /// Adaptive column count for media grids.
  int get gridColumns {
    if (isShortHeight) return 3;
    return switch (sizeClass) {
      PulsrBreakpoint.compact => 2,
      PulsrBreakpoint.medium => 3,
      PulsrBreakpoint.expanded => 4,
      PulsrBreakpoint.large => 5,
    };
  }

  /// Corner radius scale multiplier for fluid squircle rounding.
  double get cardRadiusScale {
    return switch (sizeClass) {
      PulsrBreakpoint.compact => 1.0,
      PulsrBreakpoint.medium => 1.08,
      PulsrBreakpoint.expanded => 1.15,
      PulsrBreakpoint.large => 1.25,
    };
  }

  /// Optimal navigation paradigm.
  PulsrNavMode get navMode {
    if (deviceClass == PulsrDeviceClass.desktop ||
        sizeClass == PulsrBreakpoint.large) {
      return PulsrNavMode.sideRailExtended;
    }
    if (deviceClass == PulsrDeviceClass.tablet ||
        sizeClass >= PulsrBreakpoint.expanded) {
      return orientation == Orientation.landscape
          ? PulsrNavMode.sideRailExtended
          : PulsrNavMode.sideRail;
    }
    if (sizeClass == PulsrBreakpoint.medium && !isShortHeight) {
      return PulsrNavMode.sideRail;
    }
    return PulsrNavMode.bottomBar;
  }

  /// Audio player layout mode.
  PulsrPlayerMode get playerMode {
    if (orientation == Orientation.landscape) return PulsrPlayerMode.splitPane;
    if (deviceClass == PulsrDeviceClass.tablet &&
        width >= 720.0 &&
        width > height * 0.85) {
      return PulsrPlayerMode.splitPane;
    }
    return PulsrPlayerMode.fullScreen;
  }

  bool get isTablet =>
      deviceClass == PulsrDeviceClass.tablet ||
      deviceClass == PulsrDeviceClass.desktop;
  bool get isPhone => deviceClass == PulsrDeviceClass.phone;
  bool get isPortrait => orientation == Orientation.portrait;
  bool get isLandscape => orientation == Orientation.landscape;

  /// Retrieves the cached [PulsrViewport] from [PulsrViewportScope], or falls back
  /// to creating one on-the-fly from the current [BuildContext].
  static PulsrViewport of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<PulsrViewportScope>();
    if (scope != null) return scope.viewport;
    return PulsrViewport.fromContext(context);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PulsrViewport &&
          runtimeType == other.runtimeType &&
          deviceClass == other.deviceClass &&
          orientation == other.orientation &&
          sizeClass == other.sizeClass &&
          width == other.width &&
          height == other.height &&
          isShortHeight == other.isShortHeight &&
          isUltraWide == other.isUltraWide &&
          hasHinge == other.hasHinge &&
          textScale == other.textScale;

  @override
  int get hashCode => Object.hash(
        deviceClass,
        orientation,
        sizeClass,
        width,
        height,
        isShortHeight,
        isUltraWide,
        hasHinge,
        textScale,
      );
}

/// InheritedWidget providing O(1) access to the active [PulsrViewport].
class PulsrViewportScope extends InheritedWidget {
  final PulsrViewport viewport;

  const PulsrViewportScope({
    super.key,
    required this.viewport,
    required super.child,
  });

  @override
  bool updateShouldNotify(PulsrViewportScope oldWidget) =>
      viewport != oldWidget.viewport;
}

/// Helper wrapper that wraps a subtree in a LayoutBuilder and provides [PulsrViewportScope].
class PulsrViewportScopeBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, PulsrViewport viewport) builder;

  const PulsrViewportScopeBuilder({
    super.key,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = PulsrViewport.fromContext(context, constraints);
        return PulsrViewportScope(
          viewport: viewport,
          child: Builder(
            builder: (ctx) => builder(ctx, viewport),
          ),
        );
      },
    );
  }
}

/// Convenient extension for accessing [PulsrViewport] anywhere from [BuildContext].
extension PulsrResponsiveX on BuildContext {
  PulsrViewport get viewport => PulsrViewport.of(this);
}
