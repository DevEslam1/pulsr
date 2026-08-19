// lib/core/theme/aura_theme.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';
import '../constants/app_radii.dart';

class AuraTheme {
  static ThemeData get darkTheme {
    final baseTextTheme = GoogleFonts.manropeTextTheme(ThemeData.dark().textTheme);

    final customTextTheme = baseTextTheme.copyWith(
      displayLarge: baseTextTheme.displayLarge?.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.0,
      ),
      displayMedium: baseTextTheme.displayMedium?.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      headlineMedium: baseTextTheme.headlineMedium?.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w700,
      ),
      headlineSmall: baseTextTheme.headlineSmall?.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: baseTextTheme.titleLarge?.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      titleMedium: baseTextTheme.titleMedium?.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: baseTextTheme.titleSmall?.copyWith(
        color: AppColors.textSecondary,
        fontWeight: FontWeight.w500,
      ),
      bodyLarge: baseTextTheme.bodyLarge?.copyWith(
        color: AppColors.textPrimary,
        fontSize: 16,
      ),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(
        color: AppColors.textSecondary,
        fontSize: 14,
      ),
      bodySmall: baseTextTheme.bodySmall?.copyWith(
        color: AppColors.textSecondary.withValues(alpha: 0.8),
        fontSize: 12,
      ),
      labelLarge: baseTextTheme.labelLarge?.copyWith(
        color: AppColors.onPrimary,
        fontWeight: FontWeight.w700,
        fontSize: 14,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        onPrimary: AppColors.onPrimary,
        primaryContainer: AppColors.ctaLavender,
        onPrimaryContainer: AppColors.onPrimary,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        outline: AppColors.outline,
        error: AppColors.error,
        onError: Colors.white,
      ),
      textTheme: customTextTheme,
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.cardRadius,
          side: const BorderSide(color: AppColors.outline, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(color: AppColors.textPrimary),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.ctaLavender,
          foregroundColor: AppColors.onPrimary,
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
        backgroundColor: AppColors.card,
        disabledColor: AppColors.card.withValues(alpha: 0.5),
        selectedColor: AppColors.primary,
        secondarySelectedColor: AppColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadii.chipRadius,
          side: BorderSide(color: AppColors.outline, width: 1),
        ),
        labelStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        secondaryLabelStyle: const TextStyle(
          color: AppColors.onPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        modalBackgroundColor: AppColors.surface,
        elevation: 16,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.bottomSheetRadius,
        ),
        clipBehavior: Clip.antiAliasWithSaveLayer,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.primary,
        inactiveTrackColor: AppColors.outline,
        thumbColor: AppColors.primary,
        overlayColor: AppColors.accentGlow,
        trackHeight: 4.0,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14.0),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.outline,
        thickness: 1,
        space: 1,
      ),
      iconTheme: const IconThemeData(
        color: AppColors.textPrimary,
        size: 24,
      ),
    );
  }
}
