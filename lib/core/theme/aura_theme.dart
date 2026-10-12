import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_colors.dart';
import '../constants/app_radii.dart';
import 'player_material_colors.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';
export 'pulsr_elevation.dart';

/// Semantic tokens consumed by every screen via `context.palette`.
@immutable
class PulsrPalette extends ThemeExtension<PulsrPalette> {
  const PulsrPalette({
    required this.accent,
    required this.onAccent,
    required this.accentContainer,
    required this.glow,
    required this.bg,
    required this.surface,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.hairline,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.favorite,
    required this.success,
    required this.error,
    this.warning = AppColors.warning,
    this.info = AppColors.info,
    required this.isDark,
    required this.playerCard,
    required this.deepShade,
    Color? surfaceElevated,
    Color? surfaceOverlay,
    Color? scrimLight,
    Color? scrimMedium,
    Color? scrimHeavy,
    Color? borderSubtle,
    Color? borderStrong,
    Color? accentSoft,
    Color? accentMedium,
    Color? successSoft,
    Color? errorSoft,
    Color? warningSoft,
  })  : surfaceElevated = surfaceElevated ?? (isDark ? surfaceContainerHigh : surface),
        surfaceOverlay = surfaceOverlay ?? (isDark ? const Color(0xCC12121A) : const Color(0xE0FFFFFF)),
        scrimLight = scrimLight ?? (isDark ? const Color(0x26000000) : const Color(0x14000000)),
        scrimMedium = scrimMedium ?? (isDark ? const Color(0x66000000) : const Color(0x40000000)),
        scrimHeavy = scrimHeavy ?? (isDark ? const Color(0xB3000000) : const Color(0x80000000)),
        borderSubtle = borderSubtle ?? hairline,
        borderStrong = borderStrong ?? (isDark ? const Color(0x2EFFFFFF) : const Color(0x33000000)),
        accentSoft = accentSoft ?? accentContainer,
        accentMedium = accentMedium ?? const Color(0x409B9EF5),
        successSoft = successSoft ?? const Color(0x264CAF50),
        errorSoft = errorSoft ?? const Color(0x26FF5252),
        warningSoft = warningSoft ?? const Color(0x26FFB300);

  final Color accent;
  final Color onAccent;
  final Color accentContainer; // soft accent fill (~12-16% alpha)
  final Color glow; // shadows / halos
  final Color bg;
  final Color surface;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color hairline; // 1px borders
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color favorite;
  final Color success;
  final Color error;
  final Color warning; // attention / caution semantic role
  final Color info; // informational / neutral highlight role
  final bool isDark;

  /// Immersive card-player surface (glass card / solid card).
  final Color playerCard;

  /// Deepest immersive-player backdrop below [bg] (circle/classic themes).
  final Color deepShade;

  // ── Extended Semantic Surface & Overlay Tokens ──────────────────────────
  final Color surfaceElevated;
  final Color surfaceOverlay;
  final Color scrimLight;
  final Color scrimMedium;
  final Color scrimHeavy;
  final Color borderSubtle;
  final Color borderStrong;
  final Color accentSoft; // 12% alpha
  final Color accentMedium; // 25% alpha
  final Color successSoft;
  final Color errorSoft;
  final Color warningSoft;

  Color get background => bg;
  Color get primary => accent;
  Color get surfaceCard => surfaceContainer;
  Color get surfaceVariant => surfaceContainerHigh;

  /// Guaranteed WCAG AA contrast (>= 4.5:1) against the accent color.
  Color get textOnAccent {
    final lum = accent.computeLuminance();
    return lum > 0.179 ? AppColors.onBright : Colors.white;
  }

  @override
  PulsrPalette copyWith({
    Color? accent,
    Color? onAccent,
    Color? accentContainer,
    Color? glow,
    Color? bg,
    Color? surface,
    Color? surfaceContainer,
    Color? surfaceContainerHigh,
    Color? hairline,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? favorite,
    Color? success,
    Color? error,
    Color? warning,
    Color? info,
    bool? isDark,
    Color? playerCard,
    Color? deepShade,
    Color? surfaceElevated,
    Color? surfaceOverlay,
    Color? scrimLight,
    Color? scrimMedium,
    Color? scrimHeavy,
    Color? borderSubtle,
    Color? borderStrong,
    Color? accentSoft,
    Color? accentMedium,
    Color? successSoft,
    Color? errorSoft,
    Color? warningSoft,
  }) {
    return PulsrPalette(
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      accentContainer: accentContainer ?? this.accentContainer,
      glow: glow ?? this.glow,
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surfaceContainer: surfaceContainer ?? this.surfaceContainer,
      surfaceContainerHigh: surfaceContainerHigh ?? this.surfaceContainerHigh,
      hairline: hairline ?? this.hairline,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      favorite: favorite ?? this.favorite,
      success: success ?? this.success,
      error: error ?? this.error,
      warning: warning ?? this.warning,
      info: info ?? this.info,
      isDark: isDark ?? this.isDark,
      playerCard: playerCard ?? this.playerCard,
      deepShade: deepShade ?? this.deepShade,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfaceOverlay: surfaceOverlay ?? this.surfaceOverlay,
      scrimLight: scrimLight ?? this.scrimLight,
      scrimMedium: scrimMedium ?? this.scrimMedium,
      scrimHeavy: scrimHeavy ?? this.scrimHeavy,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      borderStrong: borderStrong ?? this.borderStrong,
      accentSoft: accentSoft ?? this.accentSoft,
      accentMedium: accentMedium ?? this.accentMedium,
      successSoft: successSoft ?? this.successSoft,
      errorSoft: errorSoft ?? this.errorSoft,
      warningSoft: warningSoft ?? this.warningSoft,
    );
  }

  @override
  PulsrPalette lerp(covariant ThemeExtension<PulsrPalette>? other, double t) {
    if (other is! PulsrPalette) return this;
    return PulsrPalette(
      accent: Color.lerp(accent, other.accent, t) ?? accent,
      onAccent: Color.lerp(onAccent, other.onAccent, t) ?? onAccent,
      accentContainer: Color.lerp(accentContainer, other.accentContainer, t) ??
          accentContainer,
      glow: Color.lerp(glow, other.glow, t) ?? glow,
      bg: Color.lerp(bg, other.bg, t) ?? bg,
      surface: Color.lerp(surface, other.surface, t) ?? surface,
      surfaceContainer:
          Color.lerp(surfaceContainer, other.surfaceContainer, t) ??
              surfaceContainer,
      surfaceContainerHigh:
          Color.lerp(surfaceContainerHigh, other.surfaceContainerHigh, t) ??
              surfaceContainerHigh,
      hairline: Color.lerp(hairline, other.hairline, t) ?? hairline,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t) ?? textPrimary,
      textSecondary:
          Color.lerp(textSecondary, other.textSecondary, t) ?? textSecondary,
      textTertiary:
          Color.lerp(textTertiary, other.textTertiary, t) ?? textTertiary,
      favorite: Color.lerp(favorite, other.favorite, t) ?? favorite,
      success: Color.lerp(success, other.success, t) ?? success,
      error: Color.lerp(error, other.error, t) ?? error,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      info: Color.lerp(info, other.info, t) ?? info,
      isDark: t < 0.5 ? isDark : other.isDark,
      playerCard: Color.lerp(playerCard, other.playerCard, t) ?? playerCard,
      deepShade: Color.lerp(deepShade, other.deepShade, t) ?? deepShade,
      surfaceElevated:
          Color.lerp(surfaceElevated, other.surfaceElevated, t) ?? surfaceElevated,
      surfaceOverlay:
          Color.lerp(surfaceOverlay, other.surfaceOverlay, t) ?? surfaceOverlay,
      scrimLight: Color.lerp(scrimLight, other.scrimLight, t) ?? scrimLight,
      scrimMedium: Color.lerp(scrimMedium, other.scrimMedium, t) ?? scrimMedium,
      scrimHeavy: Color.lerp(scrimHeavy, other.scrimHeavy, t) ?? scrimHeavy,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t) ?? borderSubtle,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t) ?? borderStrong,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t) ?? accentSoft,
      accentMedium:
          Color.lerp(accentMedium, other.accentMedium, t) ?? accentMedium,
      successSoft: Color.lerp(successSoft, other.successSoft, t) ?? successSoft,
      errorSoft: Color.lerp(errorSoft, other.errorSoft, t) ?? errorSoft,
      warningSoft: Color.lerp(warningSoft, other.warningSoft, t) ?? warningSoft,
    );
  }
}

extension PulsrThemeX on BuildContext {
  PulsrPalette get palette =>
      Theme.of(this).extension<PulsrPalette>() ?? AuraTheme.defaultDark;
  bool get isDarkUi => palette.isDark;
}

class AuraTheme {
  static PulsrPalette get defaultDark =>
      _palette(AppColors.primary, Brightness.dark, false);
  static ThemeData get darkTheme =>
      customTheme(AppColors.primary, brightness: Brightness.dark);
  static ThemeData get lightTheme =>
      customTheme(AppColors.lightPrimary, brightness: Brightness.light);
  static ThemeData get amoledTheme => customTheme(AppColors.primary,
      brightness: Brightness.dark, isAmoled: true);
  static ThemeData get highContrastTheme => customTheme(AppColors.accentCyan,
      brightness: Brightness.dark, isAmoled: true, isHighContrast: true);

  /// Brightness-aware high-contrast theme. Respects the light/dark mode and
  /// the user's accent seed (custom/system/artwork) instead of forcing
  /// dark-AMOLED cyan everywhere, while genuinely raising text/outline
  /// contrast (the palette and component outlines differ from [customTheme]).
  static ThemeData highContrastThemeFor(Brightness brightness,
      {Color seed = AppColors.accentCyan}) {
    final isDark = brightness == Brightness.dark;
    return customTheme(seed,
        brightness: brightness,
        isAmoled: isDark ? true : false,
        isHighContrast: true);
  }

  static PulsrPalette _palette(
      Color accent, Brightness brightness, bool isAmoled,
      {bool dimWhitePoint = false, bool isHighContrast = false}) {
    final isDark = brightness == Brightness.dark;
    // WCAG-correct black/white decision point (~0.179), matching [textOnAccent].
    // The old 0.5 threshold picked white text on mid-luminance accents where
    // dark text has higher contrast, dropping onPrimary/button labels below AA.
    final onAccent =
        accent.computeLuminance() > 0.179 ? AppColors.onBright : Colors.white;

    if (!isDark) {
      if (isHighContrast) {
        return PulsrPalette(
          accent: accent,
          onAccent: onAccent,
          accentContainer: accent.withValues(alpha: 0.22),
          glow: accent.withValues(alpha: 0.45),
          bg: Colors.white,
          surface: Colors.white,
          surfaceContainer: const Color(0xFFF1F1F1),
          surfaceContainerHigh: const Color(0xFFE4E4E4),
          surfaceElevated: Colors.white,
          surfaceOverlay: Colors.white.withValues(alpha: 0.95),
          scrimLight: AppColors.scrimAt(0.12),
          scrimMedium: AppColors.scrimAt(0.35),
          scrimHeavy: AppColors.scrimAt(0.65),
          borderSubtle: Colors.black.withValues(alpha: 0.30),
          borderStrong: Colors.black.withValues(alpha: 0.60),
          accentSoft: accent.withValues(alpha: 0.18),
          accentMedium: accent.withValues(alpha: 0.32),
          successSoft: AppColors.success.withValues(alpha: 0.22),
          errorSoft: AppColors.error.withValues(alpha: 0.22),
          warningSoft: AppColors.warning.withValues(alpha: 0.22),
          hairline: Colors.black.withValues(alpha: 0.42),
          textPrimary: Colors.black,
          textSecondary: const Color(0xFF33373F),
          textTertiary: const Color(0xFF444B5A),
          favorite: AppColors.favorite,
          success: AppColors.success,
          error: AppColors.error,
          isDark: false,
          playerCard: Colors.white,
          deepShade: Colors.white,
        );
      }
      return PulsrPalette(
        accent: accent,
        onAccent: onAccent,
        accentContainer: accent.withValues(alpha: 0.12),
        glow: accent.withValues(alpha: 0.22),
        bg: const Color(0xFFFAFAFA),
        surface: Colors.white,
        surfaceContainer: const Color(0xFFF5F5F5),
        surfaceContainerHigh: const Color(0xFFEEEEEE),
        surfaceElevated: Colors.white,
        surfaceOverlay: Colors.white.withValues(alpha: 0.88),
        scrimLight: AppColors.scrimAt(0.08),
        scrimMedium: AppColors.scrimAt(0.25),
        scrimHeavy: AppColors.scrimAt(0.50),
        borderSubtle: const Color(0x14000000),
        borderStrong: const Color(0x33000000),
        accentSoft: accent.withValues(alpha: 0.12),
        accentMedium: accent.withValues(alpha: 0.25),
        successSoft: AppColors.success.withValues(alpha: 0.15),
        errorSoft: AppColors.error.withValues(alpha: 0.15),
        warningSoft: AppColors.warning.withValues(alpha: 0.15),
        hairline: const Color(0xFF0F1724).withValues(alpha: 0.09),
        textPrimary: const Color(0xFF101425),
        textSecondary: const Color(0xFF5D6880),
        textTertiary: const Color(0xFF59657E),
        favorite: AppColors.favorite,
        success: AppColors.success,
        error: AppColors.error,
        isDark: false,
        playerCard: Colors.white,
        deepShade: const Color(0xFFFAFAFA),
      );
    }
    if (isHighContrast) {
      return PulsrPalette(
        accent: accent,
        onAccent: onAccent,
        accentContainer: accent.withValues(alpha: 0.26),
        glow: accent.withValues(alpha: 0.50),
        bg: Colors.black,
        surface: const Color(0xFF050506),
        surfaceContainer: const Color(0xFF111114),
        surfaceContainerHigh: const Color(0xFF1B1B20),
        surfaceElevated: const Color(0xFF1B1B20),
        surfaceOverlay: Colors.black.withValues(alpha: 0.90),
        scrimLight: AppColors.scrimAt(0.25),
        scrimMedium: AppColors.scrimAt(0.55),
        scrimHeavy: AppColors.scrimAt(0.85),
        borderSubtle: Colors.white.withValues(alpha: 0.35),
        borderStrong: Colors.white.withValues(alpha: 0.70),
        accentSoft: accent.withValues(alpha: 0.20),
        accentMedium: accent.withValues(alpha: 0.35),
        successSoft: AppColors.success.withValues(alpha: 0.25),
        errorSoft: AppColors.error.withValues(alpha: 0.25),
        warningSoft: AppColors.warning.withValues(alpha: 0.25),
        hairline: Colors.white.withValues(alpha: 0.42),
        textPrimary: Colors.white,
        textSecondary: const Color(0xFFD3D8E2),
        textTertiary: const Color(0xFFB9BFCC),
        favorite: AppColors.favorite,
        success: AppColors.success,
        error: AppColors.error,
        isDark: true,
        playerCard: const Color(0xFF050506),
        deepShade: Colors.black,
      );
    }
    if (isAmoled) {
      return PulsrPalette(
        accent: accent,
        onAccent: onAccent,
        accentContainer: accent.withValues(alpha: 0.16),
        glow: accent.withValues(alpha: 0.30),
        bg: Colors.black,
        surface: const Color(0xFF0B0B0E),
        surfaceContainer: const Color(0xFF121216),
        surfaceContainerHigh: const Color(0xFF18181E),
        surfaceElevated: const Color(0xFF16161D),
        surfaceOverlay: Colors.black.withValues(alpha: 0.85),
        scrimLight: AppColors.scrimAt(0.20),
        scrimMedium: AppColors.scrimAt(0.50),
        scrimHeavy: AppColors.scrimAt(0.85),
        borderSubtle: AppColors.specularAt(0.08),
        borderStrong: AppColors.specularAt(0.20),
        accentSoft: accent.withValues(alpha: 0.12),
        accentMedium: accent.withValues(alpha: 0.25),
        successSoft: AppColors.success.withValues(alpha: 0.15),
        errorSoft: AppColors.error.withValues(alpha: 0.15),
        warningSoft: AppColors.warning.withValues(alpha: 0.15),
        hairline: AppColors.specularAt(0.09),
        textPrimary:
            dimWhitePoint ? const Color(0xFFCDD0DC) : const Color(0xFFF5F6FA),
        textSecondary: const Color(0xFF9BA1AE),
        textTertiary: const Color(0xFF8D94A3),
        favorite: AppColors.favorite,
        success: AppColors.success,
        error: AppColors.error,
        isDark: true,
        playerCard: const Color(0xFF0B0B0E),
        deepShade: Colors.black,
      );
    }
    return PulsrPalette(
      accent: accent,
      onAccent: onAccent,
      accentContainer: accent.withValues(alpha: 0.14),
      glow: accent.withValues(alpha: 0.28),
      bg: const Color(0xFF0A0A0F),
      surface: const Color(0xFF12121A),
      surfaceContainer: const Color(0xFF1A1A24),
      surfaceContainerHigh: const Color(0xFF222230),
      surfaceElevated: const Color(0xFF1E1E2A),
      surfaceOverlay: const Color(0xFF12121A).withValues(alpha: 0.78),
      scrimLight: AppColors.scrimAt(0.15),
      scrimMedium: AppColors.scrimAt(0.40),
      scrimHeavy: AppColors.scrimAt(0.70),
      borderSubtle: AppColors.specularAt(0.08),
      borderStrong: AppColors.specularAt(0.18),
      accentSoft: accent.withValues(alpha: 0.12),
      accentMedium: accent.withValues(alpha: 0.25),
      successSoft: AppColors.success.withValues(alpha: 0.15),
      errorSoft: AppColors.error.withValues(alpha: 0.15),
      warningSoft: AppColors.warning.withValues(alpha: 0.15),
      hairline: AppColors.specular,
      textPrimary:
          dimWhitePoint ? const Color(0xFFCDD0DC) : const Color(0xFFEDEFF7),
      textSecondary: const Color(0xFF98A0B3),
      textTertiary: const Color(0xFF909AB0),
      favorite: AppColors.favorite,
      success: AppColors.success,
      error: AppColors.error,
      isDark: true,
      playerCard: const Color(0xFF141828),
      deepShade: PlayerMaterialColors.immersiveBackdrop,
    );
  }

  static ThemeData customTheme(
    Color accent, {
    Brightness brightness = Brightness.dark,
    bool isAmoled = false,
    bool isBoldText = false,
    bool dimWhitePoint = false,
    bool isHighContrast = false,
  }) {
    final p = _palette(accent, brightness, isAmoled,
        dimWhitePoint: dimWhitePoint, isHighContrast: isHighContrast);
    final isDark = p.isDark;
    final outlineWidth = isHighContrast ? 1.6 : 1.0;
    final focusRingWidth = isHighContrast ? 2.6 : 1.5;
    const fontFamily = 'Manrope';
    const fontFallbacks = [
      '.SF Pro Text',
      '.SF Pro Display',
      '.SF UI Text',
      'SF Pro',
      '-apple-system',
      'Noto Sans Arabic',
      'Segoe UI',
      'Roboto',
      'Arial',
      'sans-serif'
    ];
    final baseTextTheme =
        (isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme)
            .apply(
      fontFamily: fontFamily,
      fontFamilyFallback: fontFallbacks,
    );

    final textTheme = baseTextTheme.copyWith(
      displayLarge: baseTextTheme.displayLarge?.copyWith(
          color: p.textPrimary,
          fontWeight: isBoldText ? FontWeight.w900 : FontWeight.w800,
          letterSpacing: AppTracking.display,
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallbacks),
      displayMedium: baseTextTheme.displayMedium?.copyWith(
          color: p.textPrimary,
          fontWeight: isBoldText ? FontWeight.w900 : FontWeight.w800,
          letterSpacing: AppTracking.display,
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallbacks),
      headlineMedium: baseTextTheme.headlineMedium?.copyWith(
          color: p.textPrimary,
          fontWeight: isBoldText ? FontWeight.w900 : FontWeight.w800,
          letterSpacing: AppTracking.heading,
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallbacks),
      headlineSmall: baseTextTheme.headlineSmall?.copyWith(
          color: p.textPrimary,
          fontWeight: isBoldText ? FontWeight.w900 : FontWeight.w800,
          letterSpacing: AppTracking.heading,
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallbacks),
      titleLarge: baseTextTheme.titleLarge?.copyWith(
          color: p.textPrimary,
          fontWeight: isBoldText ? FontWeight.w800 : FontWeight.w700,
          letterSpacing: AppTracking.title,
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallbacks),
      titleMedium: baseTextTheme.titleMedium?.copyWith(
          color: p.textPrimary,
          fontWeight: isBoldText ? FontWeight.w800 : FontWeight.w700,
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallbacks),
      titleSmall: baseTextTheme.titleSmall?.copyWith(
          color: p.textSecondary,
          fontWeight: isBoldText ? FontWeight.w700 : FontWeight.w600,
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallbacks),
      bodyLarge: baseTextTheme.bodyLarge?.copyWith(
          color: p.textPrimary,
          fontSize: AppFontSize.bodyLarge,
          fontWeight: isBoldText ? FontWeight.w600 : FontWeight.w400,
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallbacks),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(
          color: p.textSecondary,
          fontSize: AppFontSize.body,
          fontWeight: isBoldText ? FontWeight.w600 : FontWeight.w400,
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallbacks),
      bodySmall: baseTextTheme.bodySmall?.copyWith(
          color: p.textTertiary,
          fontSize: AppFontSize.label,
          fontWeight: isBoldText ? FontWeight.w600 : FontWeight.w400,
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallbacks),
      labelLarge: baseTextTheme.labelLarge?.copyWith(
          color: p.onAccent,
          fontWeight: isBoldText ? FontWeight.w800 : FontWeight.w700,
          fontSize: AppFontSize.body,
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallbacks),
      labelSmall: baseTextTheme.labelSmall?.copyWith(
          color: p.textTertiary,
          fontWeight: FontWeight.w800,
          letterSpacing: AppTracking.wide,
          fontSize: AppFontSize.tiny,
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallbacks),
    );

    final outlineBorder = OutlineInputBorder(
      borderRadius: AppRadii.r16All,
      borderSide: BorderSide(color: p.hairline, width: outlineWidth),
    );

    return ThemeData(
      useMaterial3: true,
      // Android predictive-back page transitions; other platforms keep their
      // framework defaults.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
      fontFamily: fontFamily,
      fontFamilyFallback: fontFallbacks,
      brightness: brightness,
      scaffoldBackgroundColor: p.bg,
      cupertinoOverrideTheme: CupertinoThemeData(
        brightness: brightness,
        primaryColor: p.accent,
        primaryContrastingColor: p.onAccent,
        scaffoldBackgroundColor: p.bg,
        barBackgroundColor: p.surface.withValues(alpha: 0.82),
        textTheme: CupertinoTextThemeData(
          primaryColor: p.textPrimary,
          textStyle: TextStyle(
            color: p.textPrimary,
            fontFamily: fontFamily,
            fontFamilyFallback: fontFallbacks,
          ),
        ),
      ),
      extensions: [p],
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: p.accent,
        onPrimary: p.onAccent,
        primaryContainer: p.accentContainer,
        onPrimaryContainer: isDark ? p.accent : p.textPrimary,
        secondary: p.accent,
        onSecondary: p.onAccent,
        surface: p.surface,
        onSurface: p.textPrimary,
        outline: p.hairline,
        error: p.error,
        onError: Colors.white,
      ),
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        ),
        titleTextStyle: TextStyle(
            color: p.textPrimary,
            fontSize: AppFontSize.titleLarge,
            fontWeight: FontWeight.w800,
            letterSpacing: AppTracking.title),
        iconTheme: IconThemeData(color: p.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: p.surfaceContainer,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.cardRadius,
          side: BorderSide(color: p.hairline, width: outlineWidth),
        ),
        margin: EdgeInsets.zero,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: p.accentContainer,
        elevation: 0,
        height: 68,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: p.accent, size: 24);
          }
          return IconThemeData(color: p.textSecondary, size: 24);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              fontSize: AppFontSize.label,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w800
                  : FontWeight.w600,
              color: states.contains(WidgetState.selected)
                  ? p.accent
                  : p.textSecondary,
            )),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: p.accentContainer,
        selectedIconTheme: IconThemeData(color: p.accent, size: 24),
        unselectedIconTheme: IconThemeData(color: p.textSecondary, size: 24),
        selectedLabelTextStyle: TextStyle(
            color: p.accent,
            fontWeight: FontWeight.w800,
            fontSize: AppFontSize.label),
        unselectedLabelTextStyle: TextStyle(
            color: p.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: AppFontSize.label),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: p.accent,
        unselectedLabelColor: p.textTertiary,
        indicatorColor: p.accent,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: p.hairline,
        labelPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        labelStyle: const TextStyle(
            fontWeight: FontWeight.w800, fontSize: AppFontSize.body),
        unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w600, fontSize: AppFontSize.body),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.transparent,
        selectedItemColor: p.accent,
        unselectedItemColor: p.textTertiary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surfaceContainer,
        disabledColor: p.surfaceContainer.withValues(alpha: 0.5),
        selectedColor: p.accentContainer,
        secondarySelectedColor: p.accentContainer,
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        shape: RoundedRectangleBorder(
            borderRadius: AppRadii.chipRadius,
            side: BorderSide(color: p.hairline)),
        labelStyle: TextStyle(
            color: p.textSecondary,
            fontSize: AppFontSize.bodySmall,
            fontWeight: FontWeight.w600),
        secondaryLabelStyle: TextStyle(
            color: p.accent,
            fontSize: AppFontSize.bodySmall,
            fontWeight: FontWeight.w700),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        modalBackgroundColor: p.surface,
        elevation: 24,
        shape: const RoundedRectangleBorder(
            borderRadius: AppRadii.bottomSheetRadius),
        clipBehavior: Clip.antiAliasWithSaveLayer,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        elevation: 24,
        shape:
            const RoundedRectangleBorder(borderRadius: AppRadii.dialogRadius),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.textTertiary,
        textColor: p.textPrimary,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.tileRadius),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.surfaceContainerHigh,
        contentTextStyle: TextStyle(
            color: p.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: AppFontSize.bodySmall),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.r14All),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return p.textSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return p.accent;
          return p.isDark
              ? AppColors.specularAt(0.12)
              : AppColors.scrimAt(0.08);
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.transparent;
          return p.hairline;
        }),
        trackOutlineWidth: WidgetStatePropertyAll(outlineWidth),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: p.accent,
        // 0.20 (was 0.14) keeps the inactive track visible over bright artwork
        // in the player, matching iOS/Apple Music track legibility.
        inactiveTrackColor:
            (p.isDark ? Colors.white : Colors.black).withValues(alpha: 0.20),
        thumbColor: Colors.white,
        overlayColor: p.accent.withValues(alpha: 0.16),
        trackHeight: 6.0,
        trackShape: const RoundedRectSliderTrackShape(),
        thumbShape: const RoundSliderThumbShape(
          enabledThumbRadius: 8.0,
          elevation: 4.0,
          pressedElevation: 7.0,
        ),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 18.0),
      ),
      dividerTheme: DividerThemeData(color: p.hairline, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: p.textPrimary, size: 24),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceContainer,
        hintStyle: TextStyle(color: p.textTertiary, fontSize: AppFontSize.body),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.s14),
        border: outlineBorder,
        enabledBorder: outlineBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadii.r16All,
          borderSide: BorderSide(color: p.accent, width: focusRingWidth),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: p.onAccent,
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s20, vertical: AppSpacing.sm),
          shape:
              const RoundedRectangleBorder(borderRadius: AppRadii.buttonRadius),
          textStyle: const TextStyle(
              fontWeight: FontWeight.w700, fontSize: AppFontSize.body),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: p.onAccent,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.s14),
          shape:
              const RoundedRectangleBorder(borderRadius: AppRadii.buttonRadius),
          textStyle: const TextStyle(
              fontWeight: FontWeight.w800, fontSize: AppFontSize.body),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.textPrimary,
          side: BorderSide(color: p.hairline, width: outlineWidth),
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s20, vertical: AppSpacing.s14),
          shape:
              const RoundedRectangleBorder(borderRadius: AppRadii.buttonRadius),
          textStyle: const TextStyle(
              fontWeight: FontWeight.w700, fontSize: AppFontSize.body),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
            foregroundColor: p.accent,
            textStyle: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }

  static const List<AuraThemePreset> presets = [
    AuraThemePreset(
      name: 'Cyber Purple',
      primaryColor: Color(0xFF0F0C29),
      secondaryColor: Color(0xFF6A11CB),
      accentColor: Color(0xFF9D4EDD),
    ),
    AuraThemePreset(
      name: 'Deep Ocean',
      primaryColor: Color(0xFF0F2027),
      secondaryColor: Color(0xFF0072FF),
      accentColor: Color(0xFF00C6FF),
    ),
    AuraThemePreset(
      name: 'Emerald Velvet',
      primaryColor: Color(0xFF071811),
      secondaryColor: Color(0xFF059669),
      accentColor: AppColors.studioGreen,
    ),
    AuraThemePreset(
      name: 'Solar Flare',
      primaryColor: Color(0xFF1F0F07),
      secondaryColor: Color(0xFFE65100),
      accentColor: Color(0xFFFF6B4A),
    ),
    AuraThemePreset(
      name: 'Electric Rose',
      primaryColor: Color(0xFF1C0916),
      secondaryColor: Color(0xFFD81B60),
      accentColor: Color(0xFFFF2E93),
    ),
    AuraThemePreset(
      name: 'Midnight AMOLED',
      primaryColor: Colors.black,
      secondaryColor: Color(0xFF241542),
      accentColor: AppColors.ldacViolet,
      isAmoled: true,
    ),
  ];
}

class AuraThemePreset {
  final String name;
  final Color primaryColor;
  final Color secondaryColor;
  final Color accentColor;
  final bool isAmoled;

  const AuraThemePreset({
    required this.name,
    required this.primaryColor,
    required this.secondaryColor,
    required this.accentColor,
    this.isAmoled = false,
  });

  LinearGradient get gradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [primaryColor, secondaryColor],
      );
}

