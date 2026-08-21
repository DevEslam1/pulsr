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

  // AMOLED (legacy)
  static const Color amoledBackground = Color(0xFF000000);
  static const Color amoledSurface = Color(0xFF0A0A0A);
  static const Color amoledCard = Color(0xFF141414);
  static const Color amoledTextPrimary = Color(0xFFFFFFFF);
  static const Color amoledTextSecondary = Color(0xFFA0A0A0);
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
