// lib/core/theme/aura_theme.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';
import '../constants/app_radii.dart';

class AuraTheme {
  static ThemeData get darkTheme => customTheme(AppColors.primary, brightness: Brightness.dark);

  static ThemeData get lightTheme => customTheme(AppColors.lightPrimary, brightness: Brightness.light);

  static ThemeData get amoledTheme => customTheme(AppColors.primary, brightness: Brightness.dark, isAmoled: true);

  static ThemeData customTheme(
    Color accent, {
    Brightness brightness = Brightness.dark,
    bool isAmoled = false,
  }) {
    final isDark = brightness == Brightness.dark;

    final Color scaffoldBg;
    final Color surfaceColor;
    final Color cardColor;
    final Color textPrimary;
    final Color textSecondary;
    final Color outlineColor;

    if (!isDark) {
      scaffoldBg = AppColors.lightBackground;
      surfaceColor = AppColors.lightSurface;
      cardColor = AppColors.lightCard;
      textPrimary = AppColors.lightTextPrimary;
      textSecondary = AppColors.lightTextSecondary;
      outlineColor = AppColors.lightOutline;
    } else if (isAmoled) {
      scaffoldBg = AppColors.amoledBackground;
      surfaceColor = AppColors.amoledSurface;
      cardColor = AppColors.amoledCard;
      textPrimary = AppColors.amoledTextPrimary;
      textSecondary = AppColors.amoledTextSecondary;
      outlineColor = AppColors.amoledOutline;
    } else {
      scaffoldBg = AppColors.background;
      surfaceColor = AppColors.surface;
      cardColor = AppColors.card;
      textPrimary = AppColors.textPrimary;
      textSecondary = AppColors.textSecondary;
      outlineColor = AppColors.outline;
    }

    final onAccent = accent.computeLuminance() > 0.5 ? Colors.black : Colors.white;

    final baseTextTheme = isDark
        ? GoogleFonts.manropeTextTheme(ThemeData.dark().textTheme)
        : GoogleFonts.manropeTextTheme(ThemeData.light().textTheme);

    final customTextTheme = baseTextTheme.copyWith(
      displayLarge: baseTextTheme.displayLarge?.copyWith(
        color: textPrimary,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.0,
      ),
      displayMedium: baseTextTheme.displayMedium?.copyWith(
        color: textPrimary,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      headlineMedium: baseTextTheme.headlineMedium?.copyWith(
        color: textPrimary,
        fontWeight: FontWeight.w700,
      ),
      headlineSmall: baseTextTheme.headlineSmall?.copyWith(
        color: textPrimary,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: baseTextTheme.titleLarge?.copyWith(
        color: textPrimary,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      titleMedium: baseTextTheme.titleMedium?.copyWith(
        color: textPrimary,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: baseTextTheme.titleSmall?.copyWith(
        color: textSecondary,
        fontWeight: FontWeight.w500,
      ),
      bodyLarge: baseTextTheme.bodyLarge?.copyWith(
        color: textPrimary,
        fontSize: 16,
      ),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(
        color: textSecondary,
        fontSize: 14,
      ),
      bodySmall: baseTextTheme.bodySmall?.copyWith(
        color: textSecondary.withValues(alpha: 0.8),
        fontSize: 12,
      ),
      labelLarge: baseTextTheme.labelLarge?.copyWith(
        color: onAccent,
        fontWeight: FontWeight.w700,
        fontSize: 14,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: scaffoldBg,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: accent,
        onPrimary: onAccent,
        primaryContainer: accent.withValues(alpha: isDark ? 0.25 : 0.15),
        onPrimaryContainer: isDark ? accent : textPrimary,
        secondary: accent,
        onSecondary: onAccent,
        surface: surfaceColor,
        onSurface: textPrimary,
        outline: outlineColor,
        error: AppColors.error,
        onError: Colors.white,
      ),
      textTheme: customTextTheme,
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.cardRadius,
          side: BorderSide(color: outlineColor, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
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
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surfaceColor,
        selectedItemColor: accent,
        unselectedItemColor: textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: onAccent,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadii.buttonRadius,
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: cardColor,
        disabledColor: cardColor.withValues(alpha: 0.5),
        selectedColor: accent,
        secondarySelectedColor: accent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.chipRadius,
          side: BorderSide(color: outlineColor, width: 1),
        ),
        labelStyle: TextStyle(
          color: textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        secondaryLabelStyle: TextStyle(
          color: onAccent,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surfaceColor,
        modalBackgroundColor: surfaceColor,
        elevation: 16,
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadii.bottomSheetRadius,
        ),
        clipBehavior: Clip.antiAliasWithSaveLayer,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        inactiveTrackColor: outlineColor,
        thumbColor: accent,
        overlayColor: accent.withValues(alpha: 0.2),
        trackHeight: 4.0,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14.0),
      ),
      dividerTheme: DividerThemeData(
        color: outlineColor,
        thickness: 1,
        space: 1,
      ),
      iconTheme: IconThemeData(
        color: textPrimary,
        size: 24,
      ),
    );
  }
}
