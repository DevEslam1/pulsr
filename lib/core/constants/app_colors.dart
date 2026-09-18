import 'package:flutter/material.dart';

/// Raw brand values only. Screens must use `context.palette` (semantic tokens),
/// never these constants, so Light/Dark/AMOLED all resolve correctly.
abstract class AppColors {
  // Brand accents
  static const Color primary = Color(0xFF9B9EF5);
  static const Color secondary = Color(0xFF6C70DC);
  static const Color lightPrimary = Color(0xFF5E63E6);
  static const Color ctaLavender = Color(0xFFB6B8F8);

  // Status
  static const Color error = Color(0xFFFF5252);
  static const Color success = Color(0xFF4CAF50);
  static const Color favorite = Color(0xFFFF5C7A);
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
  static const Color background = Color(0xFF0B0B0F);
  static const Color surface = Color(0xFF12141D);
  static const Color card = Color(0xFF171B28);
  static const Color surfaceLight = Color(0xFF1E2235);
  static const Color outline = Color(0xFF262B3D);
  static const Color textPrimary = Color(0xFFEDEFF7);
  static const Color textSecondary = Color(0xFF98A0B3);
  static const Color onPrimary = Color(0xFF12143A);
  static const Color accentGlow = Color(0x339B9EF5);
  static const Color divider = Color(0x1FFFFFFF);

  // Light surfaces (legacy)
  static const Color lightBackground = Color(0xFFF4F6FB);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFEBEFF6);
  static const Color lightTextPrimary = Color(0xFF141724);
  static const Color lightTextSecondary = Color(0xFF5F6A82);
  static const Color lightOutline = Color(0xFFD8DFEC);
  static const Color lightSecondary = Color(0xFF4B4FBE);

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
    Color(0xFF9B9EF5),
    Color(0xFF40C4FF),
    Color(0xFF00E676),
    Color(0xFFFF9100),
    Color(0xFFFF4081),
    Color(0xFFD500F9),
    Color(0xFFFFD600),
    Color(0xFF1DE9B6),
  ];
}
