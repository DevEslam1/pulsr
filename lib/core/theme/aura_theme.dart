import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import '../constants/app_colors.dart';
import '../constants/app_radii.dart';
import 'player_material_colors.dart';
import 'pulsr_page_transitions.dart';
import 'package:pulsr/core/constants/app_spacing.dart';
import 'package:pulsr/core/constants/app_typography.dart';
export 'pulsr_elevation.dart';

/// The single app typeface. Applied to [ThemeData], its text theme and every
/// component style so no surface silently falls back to the platform font.
const fontFamily = 'Manrope';

/// Fallback chain used whenever [fontFamily] has no glyph coverage (e.g.
/// Arabic text on platforms without Manrope coverage).
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
    Color? goldAccent,
    this.isCalmDensity = false,
    this.isHighContrast = false,
  })  : _accentMedium = accentMedium,
        _goldAccent = goldAccent,
        surfaceElevated =
            surfaceElevated ?? (isDark ? surfaceContainerHigh : surface),
        surfaceOverlay = surfaceOverlay ??
            (isDark ? const Color(0xFF222230) : const Color(0xFFEEEEEE)),
        scrimLight = scrimLight ??
            (isDark ? const Color(0x26000000) : const Color(0x14000000)),
        scrimMedium = scrimMedium ??
            (isDark ? const Color(0x66000000) : const Color(0x40000000)),
        scrimHeavy = scrimHeavy ??
            (isDark ? const Color(0xB3000000) : const Color(0x80000000)),
        borderSubtle = borderSubtle ?? hairline,
        borderStrong = borderStrong ??
            (isDark ? const Color(0x2EFFFFFF) : const Color(0x33000000)),
        accentSoft = accentSoft ?? accentContainer,
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

  /// Theme-aware Hi-Res / USB-DAC tier gold.
  ///
  /// Brand gold is intentionally fixed for *dark* surfaces, but at ~1.3:1 it is
  /// invisible on a light card. This resolves to a darkened gold that clears
  /// WCAG AA (4.5:1) against [surface] whenever the palette is light.
  final Color? _goldAccent;

  Color get goldAccent =>
      _goldAccent ?? (isDark ? AppColors.dacGold : const Color(0xFF6B5200));
  final bool isDark;

  /// Readable foreground for surfaces painted with [error].
  Color get onError =>
      error.computeLuminance() > 0.179 ? AppColors.onBright : Colors.white;

  /// Immersive card-player surface (glass card / solid card).
  final Color playerCard;

  /// Deepest immersive-player backdrop below [bg] (circle/classic themes).
  final Color deepShade;

  // â”€â”€ Extended Semantic Surface & Overlay Tokens â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  final Color surfaceElevated;
  final Color surfaceOverlay;
  final Color scrimLight;
  final Color scrimMedium;
  final Color scrimHeavy;
  final Color borderSubtle;
  final Color borderStrong;
  final Color accentSoft; // 12% alpha
  final Color? _accentMedium;
  Color get accentMedium => _accentMedium ?? accent.withValues(alpha: 0.25);
  final Color successSoft;
  final Color errorSoft;
  final Color warningSoft;
  final bool isCalmDensity;
  final bool isHighContrast;

  /// Whether this palette renders over a pure-black AMOLED canvas.
  bool get isAmoled => isDark && bg.computeLuminance() < 0.005;

  /// Glow opacity multiplier (reduced in Calm visual density and High Contrast).
  double get chromeGlowScale =>
      isHighContrast ? 0.0 : (isCalmDensity ? 0.35 : 1.0);

  /// Specular hairline opacity multiplier (reduced in Calm visual density).
  double get specularScale =>
      isHighContrast ? 0.0 : (isCalmDensity ? 0.55 : 1.0);

  Color get background => bg;
  Color get primary => accent;
  Color get surfaceCard => surfaceContainer;
  Color get surfaceVariant => surfaceContainerHigh;
  Color get surfaceContainerHighest => surfaceContainerHigh;

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
    Color? goldAccent,
    bool? isCalmDensity,
    bool? isHighContrast,
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
      accentMedium: accentMedium ?? _accentMedium,
      successSoft: successSoft ?? this.successSoft,
      errorSoft: errorSoft ?? this.errorSoft,
      warningSoft: warningSoft ?? this.warningSoft,
      goldAccent: goldAccent ?? _goldAccent,
      isCalmDensity: isCalmDensity ?? this.isCalmDensity,
      isHighContrast: isHighContrast ?? this.isHighContrast,
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
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t) ??
          surfaceElevated,
      surfaceOverlay:
          Color.lerp(surfaceOverlay, other.surfaceOverlay, t) ?? surfaceOverlay,
      scrimLight: Color.lerp(scrimLight, other.scrimLight, t) ?? scrimLight,
      scrimMedium: Color.lerp(scrimMedium, other.scrimMedium, t) ?? scrimMedium,
      scrimHeavy: Color.lerp(scrimHeavy, other.scrimHeavy, t) ?? scrimHeavy,
      borderSubtle:
          Color.lerp(borderSubtle, other.borderSubtle, t) ?? borderSubtle,
      borderStrong:
          Color.lerp(borderStrong, other.borderStrong, t) ?? borderStrong,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t) ?? accentSoft,
      accentMedium:
          Color.lerp(accentMedium, other.accentMedium, t) ?? accentMedium,
      successSoft: Color.lerp(successSoft, other.successSoft, t) ?? successSoft,
      errorSoft: Color.lerp(errorSoft, other.errorSoft, t) ?? errorSoft,
      warningSoft: Color.lerp(warningSoft, other.warningSoft, t) ?? warningSoft,
      goldAccent: Color.lerp(_goldAccent ?? goldAccent, other.goldAccent, t) ??
          goldAccent,
      isCalmDensity: t < 0.5 ? isCalmDensity : other.isCalmDensity,
      isHighContrast: t < 0.5 ? isHighContrast : other.isHighContrast,
    );
  }
}

/// Semantic hardware, scrim, and high-contrast ink tokens for immersive player
/// themes (vinyl, CD, cassette, rotary circle, waveform, and milkdrop).
///
/// Registered in [ThemeData.extensions] by [AuraTheme.customTheme] across Dark,
/// Light, AMOLED, High Contrast, and Dynamic Aura modes. Consume via
/// `context.playerSurfacePalette` or [AuraTheme.surfacePaletteOf].
@immutable
class PlayerSurfacePalette extends ThemeExtension<PlayerSurfacePalette> {
  const PlayerSurfacePalette({
    required this.platterMetal,
    required this.vinylGroove,
    required this.cassetteShell,
    required this.tapeWindow,
    required this.ledGlow,
    required this.scrimStart,
    required this.scrimEnd,
    required this.highContrastInk,
  });

  /// Brushed aluminum / titanium hardware tone (platter rim, tonearm, hub, spindle).
  final Color platterMetal;

  /// Deep vinyl disc / microgroove substrate tone.
  final Color vinylGroove;

  /// Skeuomorphic deck / cassette housing surface.
  final Color cassetteShell;

  /// Recessed smoked-acrylic tape window, VFD tray, and hardware readout backdrop.
  final Color tapeWindow;

  /// Optical laser / VFD / LED status glow calibrated for >= 4.5:1 contrast
  /// against [tapeWindow] and [cassetteShell].
  final Color ledGlow;

  /// Leading-edge player scrim / veil (top-edge shader & artwork legibility).
  final Color scrimStart;

  /// Trailing-edge player scrim / veil (bottom-edge control legibility).
  final Color scrimEnd;

  /// High-contrast foreground ink guaranteed >= 4.5:1 against hardware surfaces
  /// ([cassetteShell], [tapeWindow], [vinylGroove]).
  final Color highContrastInk;

  /// Secondary hardware legend ink guaranteed >= 4.5:1 against [cassetteShell]
  /// and [tapeWindow].
  Color get mutedInk => highContrastInk.withValues(alpha: 0.72);

  /// Specular highlight / hairline derived from [highContrastInk].
  Color specularAt(double alpha) => highContrastInk.withValues(alpha: alpha);

  /// Brushed-metal highlight crest derived from [platterMetal].
  Color get platterMetalHighlight =>
      Color.lerp(platterMetal, highContrastInk, 0.35) ?? highContrastInk;

  /// Mid-dark shade of [platterMetal] for metallic gradients and bevels.
  Color get platterMetalDeep =>
      Color.lerp(platterMetal, vinylGroove, 0.50) ?? platterMetal;

  /// Deep shadow shade of [platterMetal] for recessed bearings and screws.
  Color get platterMetalShadow =>
      Color.lerp(platterMetal, vinylGroove, 0.78) ?? vinylGroove;

  /// Hardware drop shadow tint anchored to [AppColors.scrimAt].
  Color shadowAt(double alpha) => AppColors.scrimAt(alpha);

  @override
  PlayerSurfacePalette copyWith({
    Color? platterMetal,
    Color? vinylGroove,
    Color? cassetteShell,
    Color? tapeWindow,
    Color? ledGlow,
    Color? scrimStart,
    Color? scrimEnd,
    Color? highContrastInk,
  }) {
    return PlayerSurfacePalette(
      platterMetal: platterMetal ?? this.platterMetal,
      vinylGroove: vinylGroove ?? this.vinylGroove,
      cassetteShell: cassetteShell ?? this.cassetteShell,
      tapeWindow: tapeWindow ?? this.tapeWindow,
      ledGlow: ledGlow ?? this.ledGlow,
      scrimStart: scrimStart ?? this.scrimStart,
      scrimEnd: scrimEnd ?? this.scrimEnd,
      highContrastInk: highContrastInk ?? this.highContrastInk,
    );
  }

  @override
  PlayerSurfacePalette lerp(
    covariant ThemeExtension<PlayerSurfacePalette>? other,
    double t,
  ) {
    if (other is! PlayerSurfacePalette) return this;
    return PlayerSurfacePalette(
      platterMetal:
          Color.lerp(platterMetal, other.platterMetal, t) ?? platterMetal,
      vinylGroove: Color.lerp(vinylGroove, other.vinylGroove, t) ?? vinylGroove,
      cassetteShell:
          Color.lerp(cassetteShell, other.cassetteShell, t) ?? cassetteShell,
      tapeWindow: Color.lerp(tapeWindow, other.tapeWindow, t) ?? tapeWindow,
      ledGlow: Color.lerp(ledGlow, other.ledGlow, t) ?? ledGlow,
      scrimStart: Color.lerp(scrimStart, other.scrimStart, t) ?? scrimStart,
      scrimEnd: Color.lerp(scrimEnd, other.scrimEnd, t) ?? scrimEnd,
      highContrastInk:
          Color.lerp(highContrastInk, other.highContrastInk, t) ??
              highContrastInk,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PlayerSurfacePalette &&
        other.platterMetal == platterMetal &&
        other.vinylGroove == vinylGroove &&
        other.cassetteShell == cassetteShell &&
        other.tapeWindow == tapeWindow &&
        other.ledGlow == ledGlow &&
        other.scrimStart == scrimStart &&
        other.scrimEnd == scrimEnd &&
        other.highContrastInk == highContrastInk;
  }

  @override
  int get hashCode => Object.hash(
        platterMetal,
        vinylGroove,
        cassetteShell,
        tapeWindow,
        ledGlow,
        scrimStart,
        scrimEnd,
        highContrastInk,
      );
}

extension PulsrThemeX on BuildContext {
  PulsrPalette get palette =>
      Theme.of(this).extension<PulsrPalette>() ?? AuraTheme.defaultDark;
  PlayerSurfacePalette get playerSurfacePalette =>
      AuraTheme.surfacePaletteOf(this);
  bool get isDarkUi => palette.isDark;
}

class AuraTheme {
  static PulsrPalette get defaultDark =>
      _palette(AppColors.primary, Brightness.dark, false);
  static PlayerSurfacePalette get defaultSurfaceDark =>
      _surfacePalette(defaultDark, isAmoled: false, isHighContrast: false);
  static PlayerSurfacePalette get defaultSurfaceLight => _surfacePalette(
        _palette(AppColors.lightPrimary, Brightness.light, false),
        isAmoled: false,
        isHighContrast: false,
      );

  /// Resolves the active [PlayerSurfacePalette] from [context], falling back
  /// gracefully to a brightness-matched default when a widget test uses a bare
  /// [ThemeData] without registered extensions.
  static PlayerSurfacePalette surfacePaletteOf(BuildContext context) {
    final theme = Theme.of(context);
    final ext = theme.extension<PlayerSurfacePalette>();
    if (ext != null) return ext;
    final p = theme.extension<PulsrPalette>();
    if (p != null) {
      return _surfacePalette(
        p,
        isAmoled: p.isAmoled,
        isHighContrast: p.isHighContrast,
      );
    }
    return theme.brightness == Brightness.dark
        ? defaultSurfaceDark
        : defaultSurfaceLight;
  }
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
      {Color seed = AppColors.accentCyan,
      bool isBoldText = false,
      bool dimWhitePoint = false,
      bool isCalmDensity = false,
      BorderRadius? buttonRadius}) {
    final isDark = brightness == Brightness.dark;
    return customTheme(seed,
        brightness: brightness,
        isAmoled: isDark ? true : false,
        isBoldText: isBoldText,
        dimWhitePoint: dimWhitePoint,
        isHighContrast: true,
        isCalmDensity: isCalmDensity,
        buttonRadius: buttonRadius);
  }

  /// Gold tier marker that stays legible on a light surface: darken the brand
  /// gold until it clears WCAG AA/AAA against white (the light surface base).
  static Color _lightGold(double amount) {
    final gold = AppColors.dacGold;
    return Color.lerp(gold, Colors.black, amount)!;
  }

  static double _contrastRatio(Color fg, Color bg) {
    final l1 = fg.computeLuminance();
    final l2 = bg.computeLuminance();
    return l1 > l2 ? (l1 + 0.05) / (l2 + 0.05) : (l2 + 0.05) / (l1 + 0.05);
  }

  /// Darkens bright brand/status colours used as foreground text or icons on
  /// a light surface via HSL lightness reduction so rich jewel hues stay
  /// vibrant while clearing WCAG AA/AAA against white, [bg], and an
  /// accent-tinted container.
  static Color _lightReadable(
    Color color,
    double amount, {
    double minContrast = 4.55,
    double containerAlpha = 0.12,
    Color bg = Colors.white,
  }) {
    var hsl = HSLColor.fromColor(color);
    // Keep extreme pastel/neon saturation controlled as lightness drops so
    // darkened accents read as rich editorial tones rather than harsh primaries.
    final baseSaturation = hsl.saturation.clamp(0.0, 0.90);
    var lightness = hsl.lightness;
    var candidate =
        hsl.withSaturation(baseSaturation).withLightness(lightness).toColor();

    final minBgContrast = minContrast > 5.0 ? minContrast : 4.55;
    for (var i = 0; i < 40; i++) {
      final onSurface = _contrastRatio(candidate, Colors.white);
      final onBg = _contrastRatio(candidate, bg);
      final blendedContainer = Color.alphaBlend(
        candidate.withValues(alpha: containerAlpha),
        Colors.white,
      );
      final onContainer = _contrastRatio(candidate, blendedContainer);
      if (onSurface >= minContrast &&
          onBg >= minBgContrast &&
          onContainer >= 4.55) {
        return candidate;
      }
      lightness = (lightness - 0.025).clamp(0.04, 1.0);
      candidate =
          hsl.withSaturation(baseSaturation).withLightness(lightness).toColor();
      if (lightness <= 0.04) break;
    }

    var step = amount.clamp(0.0, 0.92);
    while (step < 0.94) {
      final onSurface = _contrastRatio(candidate, Colors.white);
      final onBg = _contrastRatio(candidate, bg);
      final blendedContainer = Color.alphaBlend(
        candidate.withValues(alpha: containerAlpha),
        Colors.white,
      );
      final onContainer = _contrastRatio(candidate, blendedContainer);
      if (onSurface >= minContrast &&
          onBg >= minBgContrast &&
          onContainer >= 4.55) {
        break;
      }
      step += 0.04;
      candidate = Color.lerp(candidate, Colors.black, step.clamp(0.0, 0.94))!;
    }
    return candidate;
  }

  /// Lightens dark accents on dark surfaces via HSL lightness elevation so
  /// deep artwork hues stay crisp and luminous while always clearing WCAG
  /// AA/AAA against [surface] and [accentContainer].
  static Color _darkReadable(
    Color color, {
    required Color surface,
    required double minContrast,
    required double containerAlpha,
  }) {
    final hsl = HSLColor.fromColor(color);
    var lightness = hsl.lightness;
    var saturation = hsl.saturation;
    var candidate = color;

    for (var i = 0; i < 40; i++) {
      final onSurface = _contrastRatio(candidate, surface);
      final blendedContainer = Color.alphaBlend(
        candidate.withValues(alpha: containerAlpha),
        surface,
      );
      final onContainer = _contrastRatio(candidate, blendedContainer);
      if (onSurface >= minContrast && onContainer >= 4.55) {
        return candidate;
      }
      lightness = (lightness + 0.025).clamp(0.0, 0.94);
      // Gently pull back saturation only at very high lightness so luminous
      // dark-mode accents stay refined rather than clipping into harsh neon.
      if (lightness > 0.72 && saturation > 0.78) {
        saturation = (saturation - 0.015).clamp(0.55, 1.0);
      }
      candidate =
          hsl.withSaturation(saturation).withLightness(lightness).toColor();
      if (lightness >= 0.94) break;
    }

    var step = 0.0;
    while (step < 0.88) {
      final onSurface = _contrastRatio(candidate, surface);
      final blendedContainer = Color.alphaBlend(
        candidate.withValues(alpha: containerAlpha),
        surface,
      );
      final onContainer = _contrastRatio(candidate, blendedContainer);
      if (onSurface >= minContrast && onContainer >= 4.55) {
        break;
      }
      step += 0.04;
      candidate = Color.lerp(candidate, Colors.white, step.clamp(0.0, 0.88))!;
    }
    return candidate;
  }

  static PulsrPalette _palette(
      Color accent, Brightness brightness, bool isAmoled,
      {bool dimWhitePoint = false,
      bool isHighContrast = false,
      bool isCalmDensity = false}) {
    final isDark = brightness == Brightness.dark;

    if (!isDark) {
      final lightBg = isHighContrast ? Colors.white : const Color(0xFFF3F5F9);
      final readableAccent = _lightReadable(
        accent,
        isHighContrast ? 0.62 : 0.30,
        minContrast: isHighContrast ? 7.05 : 4.65,
        containerAlpha: isHighContrast ? 0.22 : 0.12,
        bg: lightBg,
      );
      final semContrast = isHighContrast ? 7.05 : 4.65;
      final readableSuccess = _lightReadable(
        AppColors.success,
        isHighContrast ? 0.40 : 0.30,
        minContrast: semContrast,
        bg: lightBg,
      );
      final readableError = _lightReadable(
        AppColors.error,
        isHighContrast ? 0.35 : 0.30,
        minContrast: semContrast,
        bg: lightBg,
      );
      final readableWarning = _lightReadable(
        AppColors.warning,
        isHighContrast ? 0.45 : 0.40,
        minContrast: semContrast,
        bg: lightBg,
      );
      final readableFavorite = _lightReadable(
        AppColors.favorite,
        isHighContrast ? 0.35 : 0.30,
        minContrast: semContrast,
        bg: lightBg,
      );
      final readableInfo = _lightReadable(
        AppColors.info,
        isHighContrast ? 0.58 : 0.45,
        minContrast: semContrast,
        bg: lightBg,
      );
      final lightOnAccent = readableAccent.computeLuminance() > 0.179
          ? AppColors.onBright
          : Colors.white;
      if (isHighContrast) {
        return PulsrPalette(
          accent: readableAccent,
          onAccent: lightOnAccent,
          accentContainer: readableAccent.withValues(alpha: 0.20),
          glow: readableAccent.withValues(alpha: isCalmDensity ? 0.12 : 0.36),
          bg: Colors.white,
          surface: Colors.white,
          surfaceContainer: const Color(0xFFEEEEEE),
          surfaceContainerHigh: const Color(0xFFE0E0E0),
          surfaceElevated: Colors.white,
          surfaceOverlay: const Color(0xFFE0E0E0),
          scrimLight: AppColors.scrimAt(0.14),
          scrimMedium: AppColors.scrimAt(0.38),
          scrimHeavy: AppColors.scrimAt(0.68),
          borderSubtle: Colors.black.withValues(alpha: 0.34),
          borderStrong: Colors.black.withValues(alpha: 0.68),
          accentSoft: readableAccent.withValues(alpha: 0.16),
          accentMedium: readableAccent.withValues(alpha: 0.30),
          successSoft: readableSuccess.withValues(alpha: 0.20),
          errorSoft: readableError.withValues(alpha: 0.20),
          warningSoft: readableWarning.withValues(alpha: 0.20),
          hairline: Colors.black.withValues(alpha: 0.45),
          textPrimary: Colors.black,
          textSecondary: const Color(0xFF2B2F38),
          textTertiary: const Color(0xFF3E4452),
          favorite: readableFavorite,
          success: readableSuccess,
          error: readableError,
          warning: readableWarning,
          info: readableInfo,
          isDark: false,
          goldAccent: _lightGold(0.62),
          playerCard: Colors.white,
          deepShade: Colors.white,
          isCalmDensity: isCalmDensity,
          isHighContrast: true,
        );
      }
      return PulsrPalette(
        accent: readableAccent,
        onAccent: lightOnAccent,
        accentContainer:
            readableAccent.withValues(alpha: isCalmDensity ? 0.08 : 0.12),
        glow: readableAccent.withValues(alpha: isCalmDensity ? 0.08 : 0.20),
        bg: lightBg,
        surface: Colors.white,
        surfaceContainer: const Color(0xFFECEFF5),
        surfaceContainerHigh: const Color(0xFFE2E6F0),
        surfaceElevated: Colors.white,
        surfaceOverlay: const Color(0xFFE5E9F2),
        scrimLight: AppColors.scrimAt(0.08),
        scrimMedium: AppColors.scrimAt(0.26),
        scrimHeavy: AppColors.scrimAt(0.52),
        borderSubtle: const Color(0xFF0F1724)
            .withValues(alpha: isCalmDensity ? 0.07 : 0.10),
        borderStrong: const Color(0xFF0F1724).withValues(alpha: 0.24),
        accentSoft:
            readableAccent.withValues(alpha: isCalmDensity ? 0.08 : 0.12),
        accentMedium:
            readableAccent.withValues(alpha: isCalmDensity ? 0.17 : 0.24),
        successSoft: readableSuccess.withValues(alpha: 0.14),
        errorSoft: readableError.withValues(alpha: 0.14),
        warningSoft: readableWarning.withValues(alpha: 0.14),
        hairline: const Color(0xFF0F1724)
            .withValues(alpha: isCalmDensity ? 0.09 : 0.13),
        textPrimary: const Color(0xFF111521),
        textSecondary: const Color(0xFF475063),
        textTertiary: const Color(0xFF5D667A),
        favorite: readableFavorite,
        success: readableSuccess,
        error: readableError,
        warning: readableWarning,
        info: readableInfo,
        isDark: false,
        goldAccent: _lightGold(0.50),
        playerCard: Colors.white,
        deepShade: const Color(0xFFE8ECF4),
        isCalmDensity: isCalmDensity,
        isHighContrast: false,
      );
    }

    final darkSurface = isHighContrast
        ? const Color(0xFF050506)
        : (isAmoled ? const Color(0xFF0A0B0F) : const Color(0xFF12151D));
    final darkContainerAlpha =
        isHighContrast ? 0.26 : (isAmoled ? 0.16 : 0.14);
    final effectiveDarkAccent = _darkReadable(
      accent,
      surface: darkSurface,
      minContrast: isHighContrast ? 7.05 : 4.55,
      containerAlpha: darkContainerAlpha,
    );
    // WCAG-correct black/white decision point (~0.179), matching [textOnAccent].
    final onAccent = effectiveDarkAccent.computeLuminance() > 0.179
        ? AppColors.onBright
        : Colors.white;

    if (isHighContrast) {
      final hcFavorite = _darkReadable(
        AppColors.favorite,
        surface: darkSurface,
        minContrast: 7.05,
        containerAlpha: 0.24,
      );
      final hcSuccess = _darkReadable(
        AppColors.success,
        surface: darkSurface,
        minContrast: 7.05,
        containerAlpha: 0.24,
      );
      final hcError = _darkReadable(
        AppColors.error,
        surface: darkSurface,
        minContrast: 7.05,
        containerAlpha: 0.24,
      );
      final hcWarning = _darkReadable(
        AppColors.warning,
        surface: darkSurface,
        minContrast: 7.05,
        containerAlpha: 0.24,
      );
      final hcInfo = _darkReadable(
        AppColors.info,
        surface: darkSurface,
        minContrast: 7.05,
        containerAlpha: 0.24,
      );
      return PulsrPalette(
        accent: effectiveDarkAccent,
        onAccent: onAccent,
        accentContainer: effectiveDarkAccent.withValues(alpha: 0.24),
        glow: effectiveDarkAccent.withValues(alpha: isCalmDensity ? 0.14 : 0.42),
        bg: Colors.black,
        surface: const Color(0xFF050506),
        surfaceContainer: const Color(0xFF111114),
        surfaceContainerHigh: const Color(0xFF1C1C22),
        surfaceElevated: const Color(0xFF1C1C22),
        surfaceOverlay: const Color(0xFF202028),
        scrimLight: AppColors.scrimAt(0.28),
        scrimMedium: AppColors.scrimAt(0.58),
        scrimHeavy: AppColors.scrimAt(0.88),
        borderSubtle: Colors.white.withValues(alpha: 0.36),
        borderStrong: Colors.white.withValues(alpha: 0.72),
        accentSoft: effectiveDarkAccent.withValues(alpha: 0.20),
        accentMedium: effectiveDarkAccent.withValues(alpha: 0.34),
        successSoft: hcSuccess.withValues(alpha: 0.24),
        errorSoft: hcError.withValues(alpha: 0.24),
        warningSoft: hcWarning.withValues(alpha: 0.24),
        hairline: Colors.white.withValues(alpha: 0.45),
        textPrimary: Colors.white,
        textSecondary: const Color(0xFFD6DBE6),
        textTertiary: const Color(0xFFBDC3D1),
        favorite: hcFavorite,
        success: hcSuccess,
        error: hcError,
        warning: hcWarning,
        info: hcInfo,
        isDark: true,
        playerCard: const Color(0xFF050506),
        deepShade: Colors.black,
        isCalmDensity: isCalmDensity,
        isHighContrast: true,
      );
    }
    if (isAmoled) {
      return PulsrPalette(
        accent: effectiveDarkAccent,
        onAccent: onAccent,
        accentContainer:
            effectiveDarkAccent.withValues(alpha: isCalmDensity ? 0.10 : 0.16),
        glow: effectiveDarkAccent.withValues(alpha: isCalmDensity ? 0.11 : 0.30),
        bg: Colors.black,
        surface: const Color(0xFF0A0B0F),
        surfaceContainer: const Color(0xFF12131A),
        surfaceContainerHigh: const Color(0xFF1B1D26),
        surfaceElevated: const Color(0xFF161822),
        surfaceOverlay: const Color(0xFF1E202B),
        scrimLight: AppColors.scrimAt(0.22),
        scrimMedium: AppColors.scrimAt(0.52),
        scrimHeavy: AppColors.scrimAt(0.86),
        borderSubtle: AppColors.specularAt(isCalmDensity ? 0.08 : 0.11),
        borderStrong: AppColors.specularAt(0.24),
        accentSoft:
            effectiveDarkAccent.withValues(alpha: isCalmDensity ? 0.08 : 0.13),
        accentMedium:
            effectiveDarkAccent.withValues(alpha: isCalmDensity ? 0.18 : 0.25),
        successSoft: AppColors.success.withValues(alpha: 0.16),
        errorSoft: AppColors.error.withValues(alpha: 0.16),
        warningSoft: AppColors.warning.withValues(alpha: 0.16),
        hairline: AppColors.specularAt(isCalmDensity ? 0.09 : 0.13),
        textPrimary:
            dimWhitePoint ? const Color(0xFFCDD0DC) : const Color(0xFFF4F5F9),
        textSecondary: const Color(0xFFA4AAB8),
        textTertiary: const Color(0xFF8F96A6),
        favorite: AppColors.favorite,
        success: AppColors.success,
        error: AppColors.error,
        isDark: true,
        playerCard: const Color(0xFF0A0B0F),
        deepShade: Colors.black,
        isCalmDensity: isCalmDensity,
        isHighContrast: false,
      );
    }
    return PulsrPalette(
      accent: effectiveDarkAccent,
      onAccent: onAccent,
      accentContainer:
          effectiveDarkAccent.withValues(alpha: isCalmDensity ? 0.09 : 0.14),
      glow: effectiveDarkAccent.withValues(alpha: isCalmDensity ? 0.09 : 0.26),
      bg: const Color(0xFF0B0D12),
      surface: const Color(0xFF12151D),
      surfaceContainer: const Color(0xFF191D28),
      surfaceContainerHigh: const Color(0xFF212635),
      surfaceElevated: const Color(0xFF1C2130),
      surfaceOverlay: const Color(0xFF242A3B),
      scrimLight: AppColors.scrimAt(0.16),
      scrimMedium: AppColors.scrimAt(0.42),
      scrimHeavy: AppColors.scrimAt(0.72),
      borderSubtle: AppColors.specularAt(isCalmDensity ? 0.05 : 0.08),
      borderStrong: AppColors.specularAt(0.20),
      accentSoft:
          effectiveDarkAccent.withValues(alpha: isCalmDensity ? 0.08 : 0.12),
      accentMedium:
          effectiveDarkAccent.withValues(alpha: isCalmDensity ? 0.17 : 0.24),
      successSoft: AppColors.success.withValues(alpha: 0.15),
      errorSoft: AppColors.error.withValues(alpha: 0.15),
      warningSoft: AppColors.warning.withValues(alpha: 0.15),
      hairline: AppColors.specularAt(isCalmDensity ? 0.06 : 0.09),
      textPrimary:
          dimWhitePoint ? const Color(0xFFCDD0DC) : const Color(0xFFF2F4FA),
      textSecondary: const Color(0xFFA8AFC4),
      textTertiary: const Color(0xFF9199B0),
      favorite: AppColors.favorite,
      success: AppColors.success,
      error: AppColors.error,
      isDark: true,
      playerCard: const Color(0xFF141926),
      deepShade: PlayerMaterialColors.immersiveBackdrop,
      isCalmDensity: isCalmDensity,
      isHighContrast: false,
    );
  }

  static PlayerSurfacePalette _surfacePalette(
    PulsrPalette p, {
    required bool isAmoled,
    required bool isHighContrast,
  }) {
    if (!p.isDark) {
      if (isHighContrast) {
        const shell = Color(0xFF151822);
        const window = Color(0xFF090B10);
        return PlayerSurfacePalette(
          platterMetal: AppColors.discSteel,
          vinylGroove: const Color(0xFF0C0E14),
          cassetteShell: shell,
          tapeWindow: window,
          ledGlow: _darkReadable(
            AppColors.accentCyan,
            surface: shell,
            minContrast: 8.0,
            containerAlpha: 0.22,
          ),
          scrimStart: p.surface.withValues(alpha: 0.72),
          scrimEnd: p.surface.withValues(alpha: 0.90),
          highContrastInk: const Color(0xFFFFFFFF),
        );
      }
      final shell = Color.alphaBlend(
        p.accent.withValues(alpha: 0.05),
        const Color(0xFF1F2330),
      );
      final window = Color.alphaBlend(
        p.accent.withValues(alpha: 0.03),
        const Color(0xFF11141D),
      );
      final ledSeed = Color.lerp(AppColors.accentCyan, p.accent, 0.30)!;
      return PlayerSurfacePalette(
        platterMetal: Color.alphaBlend(
          p.accent.withValues(alpha: 0.07),
          AppColors.discAluminum,
        ),
        vinylGroove: Color.alphaBlend(
          p.accent.withValues(alpha: 0.04),
          const Color(0xFF14161E),
        ),
        cassetteShell: shell,
        tapeWindow: window,
        ledGlow: _darkReadable(
          ledSeed,
          surface: shell,
          minContrast: 7.0,
          containerAlpha: 0.16,
        ),
        scrimStart: p.bg.withValues(alpha: 0.62),
        scrimEnd: p.surface.withValues(alpha: 0.82),
        highContrastInk: const Color(0xFFFFFFFF),
      );
    }

    if (isHighContrast) {
      const shell = Color(0xFF0D0E12);
      return PlayerSurfacePalette(
        platterMetal: AppColors.discSilver,
        vinylGroove: Colors.black,
        cassetteShell: shell,
        tapeWindow: Colors.black,
        ledGlow: _darkReadable(
          p.accent,
          surface: shell,
          minContrast: 7.5,
          containerAlpha: 0.22,
        ),
        scrimStart: AppColors.scrimAt(0.65),
        scrimEnd: AppColors.scrimAt(0.90),
        highContrastInk: const Color(0xFFFFFFFF),
      );
    }

    if (isAmoled) {
      final shell = Color.alphaBlend(
        p.accent.withValues(alpha: 0.04),
        const Color(0xFF101116),
      );
      final ledSeed = Color.lerp(AppColors.accentCyan, p.accent, 0.35)!;
      return PlayerSurfacePalette(
        platterMetal: Color.alphaBlend(
          p.accent.withValues(alpha: 0.05),
          AppColors.discSilver,
        ),
        vinylGroove: const Color(0xFF050608),
        cassetteShell: shell,
        tapeWindow: Colors.black,
        ledGlow: _darkReadable(
          ledSeed,
          surface: shell,
          minContrast: 7.0,
          containerAlpha: 0.16,
        ),
        scrimStart: AppColors.scrimAt(0.50),
        scrimEnd: AppColors.scrimAt(0.82),
        highContrastInk: const Color(0xFFFFFFFF),
      );
    }

    final shell = Color.alphaBlend(
      p.accent.withValues(alpha: 0.05),
      PlayerMaterialColors.cassetteShell,
    );
    final window = Color.alphaBlend(
      p.accent.withValues(alpha: 0.03),
      PlayerMaterialColors.cassetteWell,
    );
    final ledSeed = Color.lerp(AppColors.accentCyan, p.accent, 0.35)!;
    return PlayerSurfacePalette(
      platterMetal: Color.alphaBlend(
        p.accent.withValues(alpha: 0.06),
        AppColors.discSilver,
      ),
      vinylGroove: Color.alphaBlend(
        p.accent.withValues(alpha: 0.04),
        PlayerMaterialColors.recordBase,
      ),
      cassetteShell: shell,
      tapeWindow: window,
      ledGlow: _darkReadable(
        ledSeed,
        surface: shell,
        minContrast: 7.0,
        containerAlpha: 0.16,
      ),
      scrimStart: p.deepShade.withValues(alpha: 0.52),
      scrimEnd: p.deepShade.withValues(alpha: 0.76),
      highContrastInk: const Color(0xFFFFFFFF),
    );
  }

  static ThemeData customTheme(
    Color accent, {
    Brightness brightness = Brightness.dark,
    bool isAmoled = false,
    bool isBoldText = false,
    bool dimWhitePoint = false,
    bool isHighContrast = false,
    bool isCalmDensity = false,
    BorderRadius? buttonRadius,
  }) {
    // "Button style" in Settings → Look resolves to one radius used by every
    // Material button, so changing it changes real buttons rather than only
    // chips and section headers.
    final resolvedButtonRadius = buttonRadius ?? AppRadii.buttonRadius;
    final p = _palette(accent, brightness, isAmoled,
        dimWhitePoint: dimWhitePoint,
        isHighContrast: isHighContrast,
        isCalmDensity: isCalmDensity);
    final surfacePalette = _surfacePalette(
      p,
      isAmoled: isAmoled,
      isHighContrast: isHighContrast,
    );
    final isDark = p.isDark;
    final outlineWidth = isHighContrast ? 1.6 : 1.0;
    final focusRingWidth = isHighContrast ? 2.6 : 1.5;
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
          fontSize: AppFontSize.caption,
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallbacks),
    );

    final outlineBorder = OutlineInputBorder(
      borderRadius: AppRadii.r16All,
      borderSide: BorderSide(color: p.hairline, width: outlineWidth),
    );

    return ThemeData(
      useMaterial3: true,
      focusColor: p.accent.withValues(alpha: 0.20),
      // Android predictive-back page transitions; other platforms keep their
      // framework defaults.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          // Android 14+ predictive back owns the gesture; the router returns
          // MaterialPage so this builder is actually consulted.
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          // iOS/macOS keep the native edge-swipe pop.
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          // Desktop keeps Pulsr's tuned slide + parallax.
          TargetPlatform.windows: PulsrPageTransitionsBuilder(),
          TargetPlatform.linux: PulsrPageTransitionsBuilder(),
          TargetPlatform.fuchsia: PulsrPageTransitionsBuilder(),
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
      extensions: [p, surfacePalette],
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: p.accent,
        onPrimary: p.onAccent,
        primaryContainer: p.accentContainer,
        onPrimaryContainer: isDark ? p.accent : p.textPrimary,
        secondary: p.accent,
        onSecondary: p.onAccent,
        secondaryContainer: p.accentContainer,
        onSecondaryContainer: isDark ? p.accent : p.textPrimary,
        surface: p.surface,
        onSurface: p.textPrimary,
        onSurfaceVariant: p.textSecondary,
        surfaceContainerLowest: p.bg,
        surfaceContainerLow: p.surface,
        surfaceContainer: p.surfaceContainer,
        surfaceContainerHigh: p.surfaceContainerHigh,
        surfaceContainerHighest: p.surfaceOverlay,
        outline: p.hairline,
        outlineVariant: p.borderSubtle,
        scrim: p.scrimHeavy,
        shadow: Colors.black,
        error: p.error,
        onError: p.onError,
      ),
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
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
            fontFamily: fontFamily,
            fontFamilyFallback: fontFallbacks,
            fontSize: AppFontSize.titleLarge,
            fontWeight: FontWeight.w800,
            letterSpacing: AppTracking.title),
        iconTheme: IconThemeData(color: p.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: p.surfaceContainer,
        surfaceTintColor: Colors.transparent,
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
              fontFamily: fontFamily,
              fontFamilyFallback: fontFallbacks,
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
            fontFamily: fontFamily,
            fontFamilyFallback: fontFallbacks,
            fontWeight: FontWeight.w800,
            fontSize: AppFontSize.label),
        unselectedLabelTextStyle: TextStyle(
            color: p.textSecondary,
            fontFamily: fontFamily,
            fontFamilyFallback: fontFallbacks,
            fontWeight: FontWeight.w600,
            fontSize: AppFontSize.label),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: p.onAccent,
        unselectedLabelColor: p.textSecondary,
        indicator: BoxDecoration(
          color: p.accent,
          borderRadius: AppRadii.r20All,
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        splashBorderRadius: AppRadii.r20All,
        labelPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        labelStyle: const TextStyle(
            fontFamily: fontFamily,
            fontFamilyFallback: fontFallbacks,
            fontWeight: FontWeight.w700,
            fontSize: AppFontSize.label),
        unselectedLabelStyle: const TextStyle(
            fontFamily: fontFamily,
            fontFamilyFallback: fontFallbacks,
            fontWeight: FontWeight.w600,
            fontSize: AppFontSize.label),
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
            fontFamily: fontFamily,
            fontFamilyFallback: fontFallbacks,
            fontSize: AppFontSize.bodySmall,
            fontWeight: FontWeight.w600),
        secondaryLabelStyle: TextStyle(
            color: p.accent,
            fontFamily: fontFamily,
            fontFamilyFallback: fontFallbacks,
            fontSize: AppFontSize.bodySmall,
            fontWeight: FontWeight.w700),
      ),
      // Material SegmentedButton is still used by a handful of dense settings
      // rows. Give it the same surface, radius and type as the canonical
      // PulsrSegmentedControl so the two never read as different products.
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? p.accent
                  : p.surfaceContainer),
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? p.onAccent
                  : p.textSecondary),
          overlayColor:
              WidgetStatePropertyAll(p.accent.withValues(alpha: 0.08)),
          side: WidgetStatePropertyAll(BorderSide(color: p.hairline)),
          shape: const WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: AppRadii.r20All)),
          textStyle: WidgetStatePropertyAll(TextStyle(
            fontFamily: fontFamily,
            fontFamilyFallback: fontFallbacks,
            fontSize: AppFontSize.bodySmall,
            fontWeight: FontWeight.w700,
          )),
          visualDensity: VisualDensity.compact,
        ),
      ),
      // One material for every context menu. Without this the 12 raw
      // PopupMenuButtons inherit the Material default surface, elevation and
      // radius — the only surface class outside the Pulsr system.
      popupMenuTheme: PopupMenuThemeData(
        color: p.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 18,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.cardRadius,
          side: BorderSide(color: p.hairline, width: 1.0),
        ),
        textStyle: TextStyle(
          color: p.textPrimary,
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallbacks,
          fontSize: AppFontSize.body,
          fontWeight: FontWeight.w600,
        ),
      ),
      // Material's compact density subtracts 8dp from the *tap target*, so an
      // IconButton under `VisualDensity.compact` renders 40x40 even when the
      // call site declares a 48dp constraint. Standardise on the design
      // system's 48dp floor at the theme level.
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          visualDensity: VisualDensity.standard,
          tapTargetSize: MaterialTapTargetSize.padded,
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: AppRadii.r14All),
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        modalBackgroundColor: p.surface,
        elevation: 24,
        shape: const RoundedRectangleBorder(
            borderRadius: AppRadii.bottomSheetRadius),
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
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
            fontFamily: fontFamily,
            fontFamilyFallback: fontFallbacks,
            fontWeight: FontWeight.w600,
            fontSize: AppFontSize.bodySmall),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.r14All),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return p.onAccent;
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
        inactiveTrackColor:
            (p.isDark ? Colors.white : Colors.black).withValues(alpha: 0.22),
        thumbColor: p.accent,
        overlayColor: p.accent.withValues(alpha: 0.14),
        trackHeight: 5.0,
        trackShape: const RoundedRectSliderTrackShape(),
        thumbShape: const RoundSliderThumbShape(
          enabledThumbRadius: 7.0,
          elevation: 3.0,
          pressedElevation: 6.0,
        ),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16.0),
      ),
      dividerTheme: DividerThemeData(color: p.hairline, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: p.textPrimary, size: 24),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceContainer,
        hintStyle: TextStyle(
            color: p.textTertiary,
            fontFamily: fontFamily,
            fontFamilyFallback: fontFallbacks,
            fontSize: AppFontSize.body),
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
          shape: RoundedRectangleBorder(borderRadius: resolvedButtonRadius),
          textStyle: const TextStyle(
              fontFamily: fontFamily,
              fontFamilyFallback: fontFallbacks,
              fontWeight: FontWeight.w700,
              fontSize: AppFontSize.body),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: p.onAccent,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.s14),
          shape: RoundedRectangleBorder(borderRadius: resolvedButtonRadius),
          textStyle: const TextStyle(
              fontFamily: fontFamily,
              fontFamilyFallback: fontFallbacks,
              fontWeight: FontWeight.w800,
              fontSize: AppFontSize.body),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.textPrimary,
          side: BorderSide(color: p.hairline, width: outlineWidth),
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s20, vertical: AppSpacing.s14),
          shape: RoundedRectangleBorder(borderRadius: resolvedButtonRadius),
          textStyle: const TextStyle(
              fontFamily: fontFamily,
              fontFamilyFallback: fontFallbacks,
              fontWeight: FontWeight.w700,
              fontSize: AppFontSize.body),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
            foregroundColor: p.accent,
            textStyle: const TextStyle(
                fontFamily: fontFamily,
                fontFamilyFallback: fontFallbacks,
                fontWeight: FontWeight.w700)),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll<double>(6.0),
        radius: const Radius.circular(AppRadii.r3),
        thumbColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.dragged) ||
              states.contains(WidgetState.pressed)) {
            return p.accent.withValues(alpha: 0.70);
          }
          return p.accent.withValues(alpha: 0.40);
        }),
        trackColor: WidgetStatePropertyAll<Color>(p.surfaceContainer),
        trackBorderColor: WidgetStatePropertyAll<Color>(p.hairline),
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
