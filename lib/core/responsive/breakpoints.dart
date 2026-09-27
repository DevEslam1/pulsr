import 'dart:ui' show DisplayFeature, DisplayFeatureType;
import 'package:flutter/material.dart';

/// Centralized breakpoint system for Pulsr.
///
/// Tiers:
/// - [compact] (0–599dp): Phone portrait, small foldables closed
/// - [medium] (600–839dp): Phone landscape, small tablets portrait, foldables open
/// - [expanded] (840–1199dp): Tablets landscape, large foldables
/// - [large] (1200dp+): Desktop / large tablets
enum PulsrBreakpoint implements Comparable<PulsrBreakpoint> {
  compact(0, 599),
  medium(600, 839),
  expanded(840, 1199),
  large(1200, double.infinity);

  final double minWidth;
  final double maxWidth;

  const PulsrBreakpoint(this.minWidth, this.maxWidth);

  @override
  int compareTo(PulsrBreakpoint other) => index.compareTo(other.index);

  bool operator >=(PulsrBreakpoint other) => index >= other.index;
  bool operator <=(PulsrBreakpoint other) => index <= other.index;
  bool operator >(PulsrBreakpoint other) => index > other.index;
  bool operator <(PulsrBreakpoint other) => index < other.index;

  bool get isCompact => this == PulsrBreakpoint.compact;
  bool get isMedium => this == PulsrBreakpoint.medium;
  bool get isExpanded => this == PulsrBreakpoint.expanded;
  bool get isLarge => this == PulsrBreakpoint.large;

  /// Returns the breakpoint tier for the current [context].
  static PulsrBreakpoint of(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return fromWidth(width);
  }

  /// Returns the breakpoint tier from a raw [width] in dp.
  static PulsrBreakpoint fromWidth(double width) {
    if (width >= 1200) return PulsrBreakpoint.large;
    if (width >= 840) return PulsrBreakpoint.expanded;
    if (width >= 600) return PulsrBreakpoint.medium;
    return PulsrBreakpoint.compact;
  }

  // ── Helper static methods ────────────────────────────────────────────────

  static bool isCompactScreen(BuildContext context) => of(context).isCompact;
  static bool isMediumScreen(BuildContext context) => of(context).isMedium;
  static bool isExpandedScreen(BuildContext context) => of(context).isExpanded;
  static bool isLargeScreen(BuildContext context) => of(context).isLarge;

  static bool isLandscape(BuildContext context) =>
      MediaQuery.orientationOf(context) == Orientation.landscape;

  static bool isPortrait(BuildContext context) =>
      MediaQuery.orientationOf(context) == Orientation.portrait;

  /// Returns the display feature corresponding to a foldable hinge or fold, if present.
  static DisplayFeature? hinge(BuildContext context) {
    final features = MediaQuery.maybeDisplayFeaturesOf(context);
    if (features == null) return null;
    for (final feature in features) {
      if (feature.type == DisplayFeatureType.hinge ||
          feature.type == DisplayFeatureType.fold) {
        return feature;
      }
    }
    return null;
  }

  static bool hasHinge(BuildContext context) => hinge(context) != null;
}

/// BuildContext extension for convenient breakpoint and screen checks.
extension PulsrBreakpointContextX on BuildContext {
  PulsrBreakpoint get breakpoint => PulsrBreakpoint.of(this);
  bool get isCompact => breakpoint.isCompact;
  bool get isMedium => breakpoint.isMedium;
  bool get isExpanded => breakpoint.isExpanded;
  bool get isLarge => breakpoint.isLarge;

  bool get hasFoldableHinge => PulsrBreakpoint.hasHinge(this);
  DisplayFeature? get foldableHinge => PulsrBreakpoint.hinge(this);
}
