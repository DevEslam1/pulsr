import 'package:flutter/material.dart';

/// Raw brand values only. Screens must use `context.palette` (semantic tokens),
/// never these constants, so Light/Dark/AMOLED all resolve correctly.
abstract class AppColors {
  // Brand accents (Basbosa Neon Glow)
  static const Color primary = Color(0xFFFF2A85);
  static const Color secondary = Color(0xFFE01E6F);
  static const Color lightPrimary = Color(0xFFFF2A85);
  static const Color ctaLavender = Color(0xFFFF7BB0);

  // Status
  static const Color error = Color(0xFFFF5252);
  static const Color success = Color(0xFF4CAF50);
  static const Color favorite = Color(0xFFFF2A85);
  static const Color warning = Color(0xFFFFB300);
  static const Color info = Color(0xFF40A9FF);

  // Brand & feature accents. These are intentionally fixed (not theme-driven)
  // because they identify a source/tier rather than a UI surface.
  static const Color dacGold = Color(0xFFFFD700); // Hi-Res / USB DAC tier
  static const Color ytRed = Color(0xFFFF0000); // YouTube family
  static const Color ytRedDeep = Color(0xFF8B0000); // YouTube gradient end
  static const Color netflixRed = Color(0xFFE50914); // curated online red
  static const Color studioGreen = Color(0xFF10B981); // DSP attached / studio
  static const Color ldacViolet = Color(0xFF7C4DFF); // LDAC / correction violet
  static const Color accentCyan = Color(0xFF00E5FF); // cyan accent / calibration
  static const Color skyBlue = Color(0xFF40C4FF);
  static const Color emeraldDeep = Color(0xFF2BB673);
  static const Color roseDeep = Color(0xFFB0316B);
  static const Color amberDeep = Color(0xFFFFB800);
  static const Color slate = Color(0xFF64748B);
  static const Color darkSurface = Color(0xFF14172B);
  static const Color mint = Color(0xFF1DE9B6);
  static const Color azure = Color(0xFF00B0FF);

  // Dark surfaces (kept for legacy widgets)
  static const Color background = Color(0xFF0E0A12);
  static const Color surface = Color(0xFF16101D);
  static const Color card = Color(0xFF1E1627);
  static const Color surfaceLight = Color(0xFF261D32);
  static const Color outline = Color(0xFF322440);
  static const Color textPrimary = Color(0xFFFDF0F6);
  static const Color textSecondary = Color(0xFFA89CAE);
  static const Color onPrimary = Color(0xFF200010);
  static const Color accentGlow = Color(0x33FF2A85);
  static const Color divider = Color(0x1FFFFFFF);

  // Light surfaces (legacy)
  static const Color lightBackground = Color(0xFFFFF7FA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFFAEEF4);
  static const Color lightTextPrimary = Color(0xFF22121B);
  static const Color lightTextSecondary = Color(0xFF755D6C);
  static const Color lightOutline = Color(0xFFEED7E4);
  static const Color lightSecondary = Color(0xFFD61A6E);

  // AMOLED (legacy, deprecated): single source of truth is AuraTheme.amoledTheme
  // (defect 19-01). Kept only for tests referencing constants; do not use in UI.
  @Deprecated('Use context.palette / AuraTheme.amoledTheme instead')
  static const Color amoledBackground = Color(0xFF000000);
  @Deprecated('Use context.palette / AuraTheme.amoledTheme instead')
  static const Color amoledSurface = Color(0xFF0A0A0A);
  @Deprecated('Use context.palette / AuraTheme.amoledTheme instead')
  static const Color amoledCard = Color(0xFF141414);
  @Deprecated('Use context.palette / AuraTheme.amoledTheme instead')
  static const Color amoledTextPrimary = Color(0xFFFFFFFF);
  @Deprecated('Use context.palette / AuraTheme.amoledTheme instead')
  static const Color amoledTextSecondary = Color(0xFFA0A0A0);
  @Deprecated('Use context.palette / AuraTheme.amoledTheme instead')
  static const Color amoledOutline = Color(0xFF222222);

  static const List<Color> customAccents = [
    Color(0xFFFF2A85), // Basbosa Neon Pink
    Color(0xFFFF4081), // Rose Quartz
    Color(0xFFFF6EA7), // Bubblegum
    Color(0xFFD500F9), // Neon Violet
    Color(0xFF9B9EF5), // Lavender Dream
    Color(0xFF40C4FF), // Electric Blue
    Color(0xFF00E676), // Neon Mint
    Color(0xFFFF9100), // Sunset Orange
    Color(0xFFFFD600), // Sunshine Gold
  ];
}
