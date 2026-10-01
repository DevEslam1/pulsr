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

  /// Dark ink placed on a bright accent/artwork fill to guarantee contrast.
  /// Single source for the ubiquitous `Color(0xFF101223)` "on-bright" text.
  static const Color onBright = Color(0xFF101223);

  // Brand & feature accents. These are intentionally fixed (not theme-driven)
  // because they identify a source/tier rather than a UI surface.
  static const Color dacGold = Color(0xFFFFD700); // Hi-Res / USB DAC tier
  static const Color ytRed = Color(0xFFFF0000); // YouTube family
  static const Color ytRedDeep = Color(0xFF8B0000); // YouTube gradient end
  static const Color netflixRed = Color(0xFFE50914); // curated online red
  static const Color studioGreen = Color(0xFF10B981); // DSP attached / studio
  static const Color ldacViolet = Color(0xFF7C4DFF); // LDAC / correction violet
  static const Color accentCyan =
      Color(0xFF00E5FF); // cyan accent / calibration
  static const Color skyBlue = Color(0xFF40C4FF);
  static const Color emeraldDeep = Color(0xFF2BB673);
  static const Color roseDeep = Color(0xFFB0316B);
  static const Color amberDeep = Color(0xFFFFB800);
  static const Color slate = Color(0xFF64748B);
  static const Color darkSurface = Color(0xFF14172B);
  static const Color mint = Color(0xFF1DE9B6);
  static const Color azure = Color(0xFF00B0FF);

  // Library tab identity tints. Fixed (source-category identity), not surfaces.
  static const Color tabDownloaded = Color(0xFF26A69A);
  static const Color tabAlbums = Color(0xFFFF9800);
  static const Color tabArtists = Color(0xFFAB47BC);
  static const Color tabFavorites = Color(0xFFEF5350);
  static const Color tabFolders = Color(0xFFFFB300);
  static const Color tabGenres = Color(0xFF29B6F6);
  static const Color tabYears = Color(0xFF5C6BC0);

  // Settings category tints. Fixed identity colours for the category tiles.
  static const Color catAudio = Color(0xFFFF9500);
  static const Color catPlayback = Color(0xFFAF52DE);
  static const Color catAppearance = Color(0xFFFF2D55);
  static const Color catGestures = Color(0xFF007AFF);
  static const Color catProfiles = Color(0xFF5856D6);
  static const Color catLibrary = Color(0xFF34C759);
  static const Color catOnline = Color(0xFF5AC8FA);
  static const Color catStorage = Color(0xFFFFCC00);
  static const Color catPrivacy = Color(0xFF30B0C7);
  static const Color catAbout = Color(0xFF8E8E93);

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

  // Audio-quality badge identity tones (fixed, source-identifying).
  static const Color qualityBadgeRose = Color(0xFFE11D48);
  static const Color qualityBadgeCyan = Color(0xFF00F2FF);
  static const Color qualityBadgeSky = Color(0xFF38BDF8);
  static const Color qualityBadgeBlue = Color(0xFF60A5FA);
  static const Color qualityBadgeSlate = Color(0xFF94A3B8);
  static const Color qualityBadgeAmber = Color(0xFFF59E0B);
  static const Color qualityBadgeIndigo = Color(0xFF818CF8);

  // Cache-category identity + service brand tones.
  static const Color cacheLyrics = Color(0xFF9C27B0);
  static const Color spotifyGreen = Color(0xFF1ED760);
  static const Color spotifyGreenDeep = Color(0xFF14833B);

  // Onboarding theme-preview swatch tones.
  static const Color swatchGreen = Color(0xFF00E676);
  static const Color swatchAmber = Color(0xFFFF9100);
  static const Color swatchPink = Color(0xFFFF4081);
  static const Color swatchPurple = Color(0xFFD500F9);

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

  // Physical-material greys for the skeuomorphic player themes (vinyl record,
  // turntable hardware, cassette shell). Exact Material palette values so the
  // analog render is unchanged; named by the material they represent.
  static const Color discSilver = Color(0xFFBDBDBD); // material grey 400
  static const Color discAluminum = Color(0xFF9E9E9E); // material grey 500
  static const Color discSteel = Color(0xFF757575); // material grey 600
  static const Color discGraphite = Color(0xFF616161); // material grey 700
  static const Color discShadow = Color(0xFF424242); // material grey 800
  static const Color surfaceGreyLight = Color(0xFFEEEEEE); // material grey 200
  static const Color surfaceGreyDark = Color(0xFF212121); // material grey 900

  // Pulsr logo neon vector tones (gradient backdrop).
  static const Color logoNavy = Color(0xFF002288);
  static const Color logoBlue = Color(0xFF0077FF);
  static const Color logoMidnight = Color(0xFF001550);
  static const Color logoInk = Color(0xFF0A0C12);

  // Spinning mini vinyl-disc material tones.
  static const Color vinylDiscBase = Color(0xFF0D0E12);
  static const Color vinylDiscRim = Color(0xFF1E2028);
  static const Color vinylSpindle = Color(0xFF090A0D);

  // Room-correction multi-point legend swatches and their matching paint
  // strokes (coupled so the legend and chart stay in sync).
  static const Color roomPointCenter = Color(0xFF4FC3F7);
  static const Color roomPointLeft = Color(0xFF81C784);
  static const Color roomPointRight = Color(0xFFFFB74D);
  static const Color roomPointCenterLine = Color(0xAA4FC3F7);
  static const Color roomPointLeftLine = Color(0xAA81C784);
  static const Color roomPointRightLine = Color(0xAAFFB74D);
}
