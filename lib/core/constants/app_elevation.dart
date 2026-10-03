// lib/core/constants/app_elevation.dart
import 'package:flutter/material.dart';

/// {@category DesignSystem}
/// Standardized elevation scale (e0..e3) mapping to consistent design shadows
/// and surface elevations across light and dark themes.
abstract class AppElevation {
  /// Flat surface with zero elevation or shadow (flush).
  static const List<BoxShadow> e0 = [];

  /// Low elevation (cards, subtle tiles): 2dp offset, 8dp blur.
  static List<BoxShadow> e1(Color ambientColor) => [
        BoxShadow(
          color: ambientColor.withValues(alpha: 0.12),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  /// Medium elevation (modals, sheets, floating controls): 4dp offset, 16dp blur.
  static List<BoxShadow> e2(Color ambientColor, {Color? glowColor}) => [
        BoxShadow(
          color: ambientColor.withValues(alpha: 0.20),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
        if (glowColor != null)
          BoxShadow(
            color: glowColor.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 1),
          ),
      ];

  /// High elevation (dialogs, popovers, detached floating docks): 8dp offset, 24dp blur.
  static List<BoxShadow> e3(Color ambientColor, {Color? glowColor}) => [
        BoxShadow(
          color: ambientColor.withValues(alpha: 0.28),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
        if (glowColor != null)
          BoxShadow(
            color: glowColor.withValues(alpha: 0.16),
            blurRadius: 20,
            offset: const Offset(0, 2),
          ),
      ];
}
