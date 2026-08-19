// lib/core/constants/app_colors.dart
import 'package:flutter/material.dart';

abstract class AppColors {
  // Brand & Background (Dark default)
  static const Color background = Color(0xFF0A0C12);
  static const Color surface = Color(0xFF12141D);
  static const Color card = Color(0xFF171B28);

  // Accents & Actions
  static const Color primary = Color(0xFF9B9EF5);
  static const Color secondary = Color(0xFF6C70DC);
  static const Color accent = Color(0xFF9B9EF5);
  static const Color onPrimary = Color(0xFF12143A);
  static const Color ctaLavender = Color(0xFFB6B8F8);

  // Typography & Borders
  static const Color textPrimary = Color(0xFFEDEFF7);
  static const Color textSecondary = Color(0xFF98A0B3);
  static const Color outline = Color(0xFF262B3D);

  // Functional / Gradients
  static const Color surfaceLight = Color(0xFF1E2235);
  static const Color accentGlow = Color(0x339B9EF5);
  static const Color divider = Color(0x1FFFFFFF);
  static const Color error = Color(0xFFFF5252);
  static const Color success = Color(0xFF4CAF50);
  static const Color favorite = Color(0xFFFF5C7A);

  // --- Light Scheme ---
  static const Color lightBackground = Color(0xFFF4F6FB);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFEBEFF6);
  static const Color lightTextPrimary = Color(0xFF141724);
  static const Color lightTextSecondary = Color(0xFF67728A);
  static const Color lightOutline = Color(0xFFD8DFEC);
  static const Color lightPrimary = Color(0xFF5E63E6);
  static const Color lightSecondary = Color(0xFF4B4FBE);

  // --- AMOLED Scheme ---
  static const Color amoledBackground = Color(0xFF000000);
  static const Color amoledSurface = Color(0xFF0A0A0A);
  static const Color amoledCard = Color(0xFF141414);
  static const Color amoledTextPrimary = Color(0xFFFFFFFF);
  static const Color amoledTextSecondary = Color(0xFFA0A0A0);
  static const Color amoledOutline = Color(0xFF222222);

  // Predefined Custom Accents for color swatches
  static const List<Color> customAccents = [
    Color(0xFF9B9EF5), // Lavender (Default)
    Color(0xFF40C4FF), // Neon Blue
    Color(0xFF00E676), // Emerald
    Color(0xFFFF9100), // Sunset Orange
    Color(0xFFFF4081), // Crimson Pink
    Color(0xFFD500F9), // Electric Purple
    Color(0xFFFFD600), // Amber Yellow
    Color(0xFF1DE9B6), // Mint Teal
  ];
}
