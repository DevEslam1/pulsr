// lib/core/theme/scrim_tokens.dart
import 'package:flutter/material.dart';

/// Semantic scrim colors for modal barriers, now-playing sheets, and bottom docks.
abstract class ScrimTokens {
  /// Scrim behind dialogs and modal bottom sheets.
  static Color barrierScrim(bool isDark) =>
      Colors.black.withValues(alpha: isDark ? 0.65 : 0.45);

  /// Deep scrim behind the expanded now-playing screen.
  static Color playerScrim(bool isDark) =>
      Colors.black.withValues(alpha: isDark ? 0.75 : 0.50);

  /// Gradient scrim falloff above bottom floating docks to guarantee legibility.
  static List<Color> dockScrim(Color surfaceColor) => [
        surfaceColor.withValues(alpha: 0.0),
        surfaceColor.withValues(alpha: 0.60),
        surfaceColor.withValues(alpha: 0.95),
      ];
}
