import 'package:material_ui/material_ui.dart';

/// {@category DesignSystem}
/// Raw brand values only. Screens must use `context.palette` (semantic tokens),
/// never these constants, so Light/Dark/AMOLED all resolve correctly.
abstract class AppColors {
  // Brand accents — Pulsr Crimson default brand palette (#E11D48 / #F43F5E)
  // with optional dynamic Aura tinting extracted from currently playing track artwork.
  static const Color crimson = Color(0xFFE11D48); // Deep Pulsr Crimson (matching app icon)
  static const Color crimsonLight = Color(0xFFF43F5E); // Vibrant Pulsr Crimson / Rose-500
  static const Color crimsonSoft = Color(0xFFFDA4AF); // Soft crimson tint for secondary pills/badges
  static const Color primary = crimson; // Color(0xFFE11D48)
  static const Color secondary = crimsonLight; // Color(0xFFF43F5E)
  static const Color lightPrimary = crimson;
  static const Color ctaLavender = crimsonSoft; // Harmonized soft crimson/rose CTA tone (formerly lavender)
  static const Color ctaCrimson = crimsonLight; // Primary Listen Now CTA tone (#F43F5E)
  static const Color listenNowCta = crimsonLight; // Harmonized Listen Now CTA tone
  static const Color focusFlow = Color(0xFFFB7185); // Harmonized Focus Flow sister rose tone

  // Status
  static const Color error = Color(0xFFFF5252);
  static const Color success = Color(0xFF4CAF50);
  static const Color favorite = Color(0xFFF43F5E); // Harmonized Pulsr Crimson / Rose
  static const Color warning = Color(0xFFFFB300);
  static const Color info = Color(0xFF40A9FF);

  /// Dark ink placed on a bright accent/artwork fill to guarantee contrast.
  /// Single source for the ubiquitous `Color(0xFF101223)` "on-bright" text.
  static const Color onBright = Color(0xFF101223);

  /// WCAG-contrast-safe foreground ink (`onBright` or white) for filled
  /// semantic/brand buttons whose background is [fill].
  static Color textOnAccent(Color fill) =>
      fill.computeLuminance() > 0.179 ? onBright : Colors.white;

  // Brand & feature accents. These are intentionally fixed (not theme-driven)
  // because they identify a source/tier rather than a UI surface.
  static const Color dacGold = Color(0xFFFFD700); // Hi-Res / USB DAC tier
  static const Color giltGold = Color(0xFFC9A24B); // Quran radio gilt accent
  static const Color onGiltLight = Color(0xFFFFF7E6); // Warm cream ink on gilt
  static const Color onGiltDark = Color(0xFF231A06); // Deep umber ink on gilt
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
  static const Color darkSurface = Color(0xFF13151C);
  static const Color mint = Color(0xFFFB7185);
  static const Color azure = Color(0xFF00B0FF);

  // Library tab identity tints. Fixed (source-category identity), not surfaces.
  static const Color tabDownloaded = Color(0xFF26A69A);
  static const Color tabAlbums = Color(0xFFFF9800);
  static const Color tabArtists = Color(0xFFAB47BC);
  static const Color tabFavorites = Color(0xFFF43F5E);
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

  // Tonal surface elevation hierarchy (#090A0E base -> #13151C surface -> #1C1F29 elevated)
  static const Color background = Color(0xFF090A0E); // Base elevation (#090A0E)
  static const Color surface = Color(0xFF13151C); // Surface elevation (#13151C)
  static const Color card = Color(0xFF1C1F29); // Elevated surface (#1C1F29)
  static const Color surfaceLight = Color(0xFF1C1F29); // Elevated surface (#1C1F29)
  static const Color surfaceElevated = Color(0xFF1C1F29); // Explicit elevated surface token (#1C1F29)
  static const Color outline = Color(0x0FFFFFFF); // Shifted from heavy grey to ultra-subtle hairline (0.06 white)
  static const Color hairlineBorder = Color(0x0FFFFFFF); // Colors.white.withValues(alpha: 0.06)
  static const Color hairline = Color(0x0FFFFFFF); // Colors.white.withValues(alpha: 0.06)
  static const Color textPrimary = Color(0xFFEDEFF7);
  static const Color textSecondary = Color(0xFF98A0B3);
  static const Color onPrimary = Color(0xFFFFFFFF); // Clean white text on Pulsr Crimson
  static const Color accentGlow = Color(0x33E11D48); // 20% alpha Pulsr Crimson glow
  static const Color divider = Color(0x0FFFFFFF); // Ultra-subtle hairline divider (0.06 white)

  // Light surfaces (legacy)
  static const Color lightBackground = Color(0xFFF4F6FB);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFEBEFF6);
  static const Color lightTextPrimary = Color(0xFF141724);
  static const Color lightTextSecondary = Color(0xFF5F6A82);
  static const Color lightOutline = Color(0xFFD8DFEC);
  static const Color lightSecondary = Color(0xFFBE123C); // Deep Pulsr Crimson for light mode

  // Audio-quality badge identity tones (harmonized cohesive palette).
  static const Color qualityBadgeRose = Color(0xFFE11D48); // DSD / Master / Pulsr Crimson
  static const Color qualityBadgeCyan = Color(0xFF38BDF8); // Lossless tier (refined ice blue)
  static const Color qualityBadgeSky = Color(0xFF38BDF8); // AAC / Radio tier
  static const Color qualityBadgeBlue = Color(0xFF818CF8); // High quality tier
  static const Color qualityBadgeSlate = Color(0xFF94A3B8); // Standard quality / neutral slate
  static const Color qualityBadgeAmber = Color(0xFFF59E0B); // MQA / Studio tier
  static const Color qualityBadgeIndigo = Color(0xFFFB7185); // Stream / Lossless sister rose

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
    crimson, // Color(0xFFE11D48) - Pulsr Crimson
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

  // Overlay tokens: black scrims and white specular highlights. These replace
  // ad-hoc Colors.black/white.withValues(alpha:) call sites so the overlay
  // source colours stay centralized. Use scrimAt/specularAt for one-off alphas.
  static const Color scrim = Color(0xA6000000);
  static const Color scrimLight = Color(0x73000000);
  static const Color scrimStrong = Color(0xD9000000);
  static const Color specular = Color(0x12FFFFFF);
  static const Color specularStrong = Color(0x24FFFFFF);
  static const Color highlightSoft = Color(0x0AFFFFFF);

  // Scroll-edge ShaderMask alpha gradient stops.
  static const Color fadeStopOpaque = Color(0xFFFFFFFF);
  static const Color fadeStopMid = Color(0xB3FFFFFF);
  static const Color fadeStopTransparent = Color(0x00FFFFFF);

  // Integration brand accents.
  static const Color discordBlurple = Color(0xFF5865F2);
  static const Color quranEmerald = Color(0xFF10B981);

  // Player-control ink used when the active colour is too bright for white.
  static const Color controlInk = Color(0xFF101223);

  // Lyrics share-card poster palette (exact values preserved so the exported
  // bitmap looks identical). These are artwork colours, not semantic UI.
  static const Color posterScrimStrong = Color(0xCC08080C);
  static const Color posterScrimDeep = Color(0xDD0D0D14);
  static const Color posterScrimFull = Color(0xF208080C);
  static const Color posterSurface = Color(0xFF101018);
  static const Color posterSurfaceAlt = Color(0xFF161524);
  static const Color posterInk = Color(0xFF09090E);
  static const Color posterThumb = Color(0xFF222230);
  static const Color chartNeutral = Color(0x33888888);

  static Color scrimAt(double alpha) =>
      const Color(0xFF000000).withValues(alpha: alpha);

  static Color specularAt(double alpha) =>
      const Color(0xFFFFFFFF).withValues(alpha: alpha);
}
