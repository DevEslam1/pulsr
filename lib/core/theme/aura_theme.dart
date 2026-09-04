import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_colors.dart';
import '../constants/app_radii.dart';

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
    required this.isDark,
  });

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
  final bool isDark;

  Color get background => bg;
  Color get primary => accent;
  Color get surfaceCard => surfaceContainer;
  Color get surfaceVariant => surfaceContainerHigh;

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
    bool? isDark,
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
      isDark: isDark ?? this.isDark,
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
      isDark: t < 0.5 ? isDark : other.isDark,
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
  static ThemeData get highContrastTheme => customTheme(const Color(0xFF00E5FF),
      brightness: Brightness.dark, isAmoled: true);

  static PulsrPalette _palette(
      Color accent, Brightness brightness, bool isAmoled) {
    final isDark = brightness == Brightness.dark;
    final onAccent = accent.computeLuminance() > 0.5
        ? const Color(0xFF101223)
        : Colors.white;

    if (!isDark) {
      return PulsrPalette(
        accent: accent,
        onAccent: onAccent,
        accentContainer: accent.withValues(alpha: 0.12),
        glow: accent.withValues(alpha: 0.22),
        bg: const Color(0xFFF4F6FB),
        surface: const Color(0xFFFFFFFF),
        surfaceContainer: const Color(0xFFEDF0F7),
        surfaceContainerHigh: const Color(0xFFE4E9F3),
        hairline: const Color(0xFF0F1724).withValues(alpha: 0.09),
        textPrimary: const Color(0xFF101425),
        textSecondary: const Color(0xFF5D6880),
        textTertiary: const Color(0xFF9AA3B8),
        favorite: AppColors.favorite,
        success: AppColors.success,
        error: AppColors.error,
        isDark: false,
      );
    }
    if (isAmoled) {
      return PulsrPalette(
        accent: accent,
        onAccent: onAccent,
        accentContainer: accent.withValues(alpha: 0.16),
        glow: accent.withValues(alpha: 0.30),
        bg: const Color(0xFF000000),
        surface: const Color(0xFF0B0B0E),
        surfaceContainer: const Color(0xFF121216),
        surfaceContainerHigh: const Color(0xFF18181E),
        hairline: Colors.white.withValues(alpha: 0.09),
        textPrimary: const Color(0xFFF5F6FA),
        textSecondary: const Color(0xFF9BA1AE),
        textTertiary: const Color(0xFF5F6470),
        favorite: AppColors.favorite,
        success: AppColors.success,
        error: AppColors.error,
        isDark: true,
      );
    }
    return PulsrPalette(
      accent: accent,
      onAccent: onAccent,
      accentContainer: accent.withValues(alpha: 0.14),
      glow: accent.withValues(alpha: 0.28),
      bg: const Color(0xFF0A0C12),
      surface: const Color(0xFF12141D),
      surfaceContainer: const Color(0xFF171B28),
      surfaceContainerHigh: const Color(0xFF1E2235),
      hairline: Colors.white.withValues(alpha: 0.07),
      textPrimary: const Color(0xFFEDEFF7),
      textSecondary: const Color(0xFF98A0B3),
      textTertiary: const Color(0xFF5C6478),
      favorite: AppColors.favorite,
      success: AppColors.success,
      error: AppColors.error,
      isDark: true,
    );
  }

  static ThemeData customTheme(
    Color accent, {
    Brightness brightness = Brightness.dark,
    bool isAmoled = false,
  }) {
    final p = _palette(accent, brightness, isAmoled);
    final isDark = p.isDark;
    const fontFamily = 'Manrope';
    const fontFallbacks = [
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
          fontWeight: FontWeight.w800,
          letterSpacing: -1.2,
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallbacks),
      displayMedium: baseTextTheme.displayMedium?.copyWith(
          color: p.textPrimary,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.8,
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallbacks),
      headlineMedium: baseTextTheme.headlineMedium?.copyWith(
          color: p.textPrimary,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.6,
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallbacks),
      headlineSmall: baseTextTheme.headlineSmall?.copyWith(
          color: p.textPrimary,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallbacks),
      titleLarge: baseTextTheme.titleLarge?.copyWith(
          color: p.textPrimary,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallbacks),
      titleMedium: baseTextTheme.titleMedium?.copyWith(
          color: p.textPrimary,
          fontWeight: FontWeight.w700,
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallbacks),
      titleSmall: baseTextTheme.titleSmall?.copyWith(
          color: p.textSecondary,
          fontWeight: FontWeight.w600,
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallbacks),
      bodyLarge: baseTextTheme.bodyLarge?.copyWith(
          color: p.textPrimary,
          fontSize: 16,
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallbacks),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(
          color: p.textSecondary,
          fontSize: 14,
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallbacks),
      bodySmall: baseTextTheme.bodySmall?.copyWith(
          color: p.textTertiary,
          fontSize: 12,
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallbacks),
      labelLarge: baseTextTheme.labelLarge?.copyWith(
          color: p.onAccent,
          fontWeight: FontWeight.w700,
          fontSize: 14,
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallbacks),
      labelSmall: baseTextTheme.labelSmall?.copyWith(
          color: p.textTertiary,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.4,
          fontSize: 10.5,
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallbacks),
    );

    final outlineBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: p.hairline),
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFallbacks,
      brightness: brightness,
      scaffoldBackgroundColor: p.bg,
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
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3),
        iconTheme: IconThemeData(color: p.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: p.surfaceContainer,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.cardRadius,
          side: BorderSide(color: p.hairline),
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
              fontSize: 11.5,
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
            color: p.accent, fontWeight: FontWeight.w800, fontSize: 12),
        unselectedLabelTextStyle: TextStyle(
            color: p.textSecondary, fontWeight: FontWeight.w600, fontSize: 12),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: p.accent,
        unselectedLabelColor: p.textTertiary,
        indicatorColor: p.accent,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: p.hairline,
        labelPadding: const EdgeInsets.symmetric(horizontal: 16),
        labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        unselectedLabelStyle:
            const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: p.surface,
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
            borderRadius: AppRadii.chipRadius,
            side: BorderSide(color: p.hairline)),
        labelStyle: TextStyle(
            color: p.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
        secondaryLabelStyle: TextStyle(
            color: p.accent, fontSize: 13, fontWeight: FontWeight.w700),
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
            color: p.textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: p.accent,
        inactiveTrackColor: p.hairline,
        thumbColor: p.accent,
        overlayColor: p.accent.withValues(alpha: 0.18),
        trackHeight: 4.0,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14.0),
      ),
      dividerTheme: DividerThemeData(color: p.hairline, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: p.textPrimary, size: 24),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceContainer,
        hintStyle: TextStyle(color: p.textTertiary, fontSize: 14),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: outlineBorder,
        enabledBorder: outlineBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: p.accent, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: p.onAccent,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape:
              const RoundedRectangleBorder(borderRadius: AppRadii.buttonRadius),
          textStyle:
              const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.textPrimary,
          side: BorderSide(color: p.hairline),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape:
              const RoundedRectangleBorder(borderRadius: AppRadii.buttonRadius),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
            foregroundColor: p.accent,
            textStyle: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}
