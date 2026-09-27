import 'package:flutter/material.dart';
import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';
import '../constants/app_typography.dart';
import 'breakpoints.dart';

/// Resolves values dynamically based on current [PulsrBreakpoint] tier.
class ResponsiveValues<T> {
  final T compact;
  final T? medium;
  final T? expanded;
  final T? large;

  const ResponsiveValues({
    required this.compact,
    this.medium,
    this.expanded,
    this.large,
  });

  /// Resolves the value according to the specified [tier].
  T resolve(PulsrBreakpoint tier) {
    switch (tier) {
      case PulsrBreakpoint.large:
        return large ?? expanded ?? medium ?? compact;
      case PulsrBreakpoint.expanded:
        return expanded ?? medium ?? compact;
      case PulsrBreakpoint.medium:
        return medium ?? compact;
      case PulsrBreakpoint.compact:
        return compact;
    }
  }

  /// Resolves the value directly using the [BuildContext].
  T of(BuildContext context) => resolve(PulsrBreakpoint.of(context));
}

/// Spacing tokens scaled responsively according to breakpoint tiers.
abstract class ResponsiveSpacing {
  static double padding(BuildContext context) {
    return const ResponsiveValues<double>(
      compact: AppSpacing.md, // 16.0
      medium: AppSpacing.s20, // 20.0
      expanded: AppSpacing.lg, // 24.0
      large: AppSpacing.xl, // 32.0
    ).of(context);
  }

  static double gap(BuildContext context) {
    return const ResponsiveValues<double>(
      compact: AppSpacing.xs, // 8.0
      medium: AppSpacing.sm, // 12.0
      expanded: AppSpacing.md, // 16.0
      large: AppSpacing.s20, // 20.0
    ).of(context);
  }

  static double cardMargin(BuildContext context) {
    return const ResponsiveValues<double>(
      compact: AppSpacing.sm,
      medium: AppSpacing.md,
      expanded: AppSpacing.lg,
      large: AppSpacing.xl,
    ).of(context);
  }
}

/// Font sizes scaled responsively according to breakpoint tiers.
abstract class ResponsiveFontSize {
  static double scaleFactor(BuildContext context) {
    return const ResponsiveValues<double>(
      compact: 1.0,
      medium: 1.05,
      expanded: 1.10,
      large: 1.15,
    ).of(context);
  }

  static double scale(BuildContext context, double baseFontSize) {
    return baseFontSize * scaleFactor(context);
  }

  static double body(BuildContext context) =>
      scale(context, AppFontSize.body);

  static double bodySmall(BuildContext context) =>
      scale(context, AppFontSize.bodySmall);

  static double title(BuildContext context) =>
      scale(context, AppFontSize.title);

  static double titleLarge(BuildContext context) =>
      scale(context, AppFontSize.titleLarge);

  static double headline(BuildContext context) =>
      scale(context, AppFontSize.headline);
}

/// Border radii scaled responsively according to breakpoint tiers.
abstract class ResponsiveRadius {
  static double tile(BuildContext context) {
    return const ResponsiveValues<double>(
      compact: AppRadii.tile, // 14.0
      medium: AppRadii.r16,
      expanded: AppRadii.card, // 18.0
      large: AppRadii.r20,
    ).of(context);
  }

  static double card(BuildContext context) {
    return const ResponsiveValues<double>(
      compact: AppRadii.card, // 18.0
      medium: AppRadii.r20,
      expanded: AppRadii.r22,
      large: AppRadii.r24,
    ).of(context);
  }

  static double sheet(BuildContext context) {
    return const ResponsiveValues<double>(
      compact: AppRadii.bottomSheet, // 28.0
      medium: AppRadii.dialog, // 26.0
      expanded: AppRadii.dialog,
      large: AppRadii.bottomSheet,
    ).of(context);
  }
}

/// Icon sizes scaled responsively according to breakpoint tiers.
abstract class ResponsiveIconSize {
  static double sm(BuildContext context) {
    return const ResponsiveValues<double>(
      compact: 18.0,
      medium: 20.0,
      expanded: 22.0,
      large: 24.0,
    ).of(context);
  }

  static double md(BuildContext context) {
    return const ResponsiveValues<double>(
      compact: 24.0,
      medium: 26.0,
      expanded: 28.0,
      large: 30.0,
    ).of(context);
  }

  static double lg(BuildContext context) {
    return const ResponsiveValues<double>(
      compact: 32.0,
      medium: 36.0,
      expanded: 40.0,
      large: 44.0,
    ).of(context);
  }
}

/// Responsive design token accessor accessible via `context.responsive`.
class PulsrResponsiveTokens {
  final BuildContext context;
  const PulsrResponsiveTokens(this.context);

  double get padding => ResponsiveSpacing.padding(context);
  double get gap => ResponsiveSpacing.gap(context);
  double get cardMargin => ResponsiveSpacing.cardMargin(context);

  double get fontSize => ResponsiveFontSize.body(context);
  double get fontScale => ResponsiveFontSize.scaleFactor(context);

  double get radius => ResponsiveRadius.card(context);
  double get tileRadius => ResponsiveRadius.tile(context);
  double get sheetRadius => ResponsiveRadius.sheet(context);

  double get iconSize => ResponsiveIconSize.md(context);
  double get iconSizeSm => ResponsiveIconSize.sm(context);
  double get iconSizeLg => ResponsiveIconSize.lg(context);

  T value<T>({
    required T compact,
    T? medium,
    T? expanded,
    T? large,
  }) =>
      ResponsiveValues<T>(
        compact: compact,
        medium: medium,
        expanded: expanded,
        large: large,
      ).of(context);
}

/// Context extension for `context.responsive`.
extension PulsrResponsiveX on BuildContext {
  PulsrResponsiveTokens get responsive => PulsrResponsiveTokens(this);
}
