import 'package:flutter/material.dart';
import 'package:pulsr/core/constants/app_colors.dart';

/// Semantic scrims. Aurora adds eased multi-stop gradients so artwork dissolves
/// perceptually smoothly instead of banding at a single mid stop.
abstract class ScrimTokens {
  static Color barrierScrim(bool isDark) =>
      AppColors.scrimAt(isDark ? 0.65 : 0.45);

  static Color playerScrim(bool isDark) =>
      AppColors.scrimAt(isDark ? 0.75 : 0.50);

  static List<Color> dockScrim(Color surfaceColor) => [
        surfaceColor.withValues(alpha: 0.0),
        surfaceColor.withValues(alpha: 0.60),
        surfaceColor.withValues(alpha: 0.95),
      ];

  /// NEW: full-bleed artwork → deck dissolve (used by Clean 2.0).
  static LinearGradient artworkDissolve(Color base) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          Colors.transparent,
          base.withValues(alpha: 0.22),
          base.withValues(alpha: 0.66),
          base,
        ],
        stops: const [0.0, 0.42, 0.62, 0.82, 1.0],
      );

  /// NEW: top-edge legibility scrim for status bar / grab handle over artwork.
  static LinearGradient topLegibility(bool isDark) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppColors.scrimAt(isDark ? 0.35 : 0.12),
          Colors.transparent,
        ],
      );
}
