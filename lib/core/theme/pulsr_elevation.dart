import 'package:flutter/material.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/theme/aura_theme.dart';

/// {@category DesignSystem}
/// Standardized elevation & shadow system across Pulsr.
///
/// Provides a consistent 5-level elevation hierarchy:
/// - [level0]: flat surfaces (no shadow)
/// - [level1]: cards & tiles at rest (blur 4, offset 0,1)
/// - [level2]: cards hovered / pressed / raised (blur 8, offset 0,2)
/// - [level3]: sheets, dialogs, popovers (blur 16, offset 0,4)
/// - [level4]: floating dock, now-playing card (blur 24, offset 0,8)
class PulsrElevation {
  const PulsrElevation._();

  /// Flat surface with zero shadow.
  static const List<BoxShadow> level0 = [];

  /// Cards & tiles at rest: 1dp offset, 4dp blur.
  static List<BoxShadow> level1([dynamic contextOrPalette]) {
    final isDark = _isDark(contextOrPalette);
    return [
      BoxShadow(
        color: AppColors.scrimAt(isDark ? 0.20 : 0.08),
        blurRadius: 4,
        offset: const Offset(0, 1),
      ),
    ];
  }

  /// Cards hover/press: 2dp offset, 8dp blur.
  static List<BoxShadow> level2([dynamic contextOrPalette]) {
    final isDark = _isDark(contextOrPalette);
    return [
      BoxShadow(
        color: AppColors.scrimAt(isDark ? 0.32 : 0.12),
        blurRadius: 8,
        offset: const Offset(0, 2),
      ),
    ];
  }

  /// Sheets & dialogs: 4dp offset, 16dp blur.
  static List<BoxShadow> level3([dynamic contextOrPalette]) {
    final isDark = _isDark(contextOrPalette);
    return [
      BoxShadow(
        color: AppColors.scrimAt(isDark ? 0.48 : 0.16),
        blurRadius: 16,
        offset: const Offset(0, 4),
      ),
    ];
  }

  /// Now-playing / floating hero surface: 8dp offset, 24dp blur.
  static List<BoxShadow> level4([dynamic contextOrPalette]) {
    final isDark = _isDark(contextOrPalette);
    return [
      BoxShadow(
        color: AppColors.scrimAt(isDark ? 0.65 : 0.24),
        blurRadius: 24,
        offset: const Offset(0, 8),
      ),
    ];
  }

  static bool _isDark(dynamic contextOrPalette) {
    if (contextOrPalette is BuildContext) {
      return contextOrPalette.palette.isDark;
    } else if (contextOrPalette is PulsrPalette) {
      return contextOrPalette.isDark;
    }
    return true;
  }
}
