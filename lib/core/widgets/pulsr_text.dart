import 'package:flutter/material.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/constants/app_typography.dart';
import 'package:pulsr/core/theme/aura_theme.dart';

/// {@category DesignSystem}
/// Canonical typography factories for the Pulsr design system.
///
/// Returns standardized [TextStyle]s configured with cohesive font size,
/// weight, tracking, height, and semantic theme colors.
class PulsrText {
  PulsrText._();

  static const String fontFamily = 'Manrope';
  static const List<String> fontFallbacks = [
    '.SF Pro Text',
    'Segoe UI',
    'Roboto',
    'sans-serif',
  ];

  /// Hero display heading style (30dp, w800, -0.8 tracking).
  static TextStyle display({
    BuildContext? context,
    Color? color,
    FontWeight? weight,
    double? fontSize,
    double? height = 1.15,
    double? letterSpacing,
  }) {
    final p = context?.palette;
    return TextStyle(
      fontFamily: fontFamily,
      fontFamilyFallback: fontFallbacks,
      fontSize: fontSize ?? AppFontSize.display,
      fontWeight: weight ?? FontWeight.w800,
      letterSpacing: letterSpacing ?? AppTracking.display,
      height: height,
      color: color ?? p?.textPrimary ?? AppColors.textPrimary,
    );
  }

  /// Prominent title style (18dp, w700, -0.2 tracking).
  static TextStyle title({
    BuildContext? context,
    Color? color,
    FontWeight? weight,
    double? fontSize,
    double? height = 1.25,
    double? letterSpacing,
  }) {
    final p = context?.palette;
    return TextStyle(
      fontFamily: fontFamily,
      fontFamilyFallback: fontFallbacks,
      fontSize: fontSize ?? AppFontSize.title,
      fontWeight: weight ?? FontWeight.w700,
      letterSpacing: letterSpacing ?? AppTracking.title,
      height: height,
      color: color ?? p?.textPrimary ?? AppColors.textPrimary,
    );
  }

  /// Default body reading style (14dp, w500, 0.0 tracking).
  static TextStyle body({
    BuildContext? context,
    Color? color,
    FontWeight? weight,
    double? fontSize,
    double? height = 1.4,
    double? letterSpacing,
  }) {
    final p = context?.palette;
    return TextStyle(
      fontFamily: fontFamily,
      fontFamilyFallback: fontFallbacks,
      fontSize: fontSize ?? AppFontSize.body,
      fontWeight: weight ?? FontWeight.w500,
      letterSpacing: letterSpacing ?? AppTracking.none,
      height: height,
      color: color ?? p?.textPrimary ?? AppColors.textPrimary,
    );
  }

  /// Secondary caption / timestamp readout (11dp, w500, +0.3 tracking).
  static TextStyle caption({
    BuildContext? context,
    Color? color,
    FontWeight? weight,
    double? fontSize,
    double? height = 1.3,
    double? letterSpacing,
  }) {
    final p = context?.palette;
    return TextStyle(
      fontFamily: fontFamily,
      fontFamilyFallback: fontFallbacks,
      fontSize: fontSize ?? AppFontSize.caption,
      fontWeight: weight ?? FontWeight.w500,
      letterSpacing: letterSpacing ?? AppTracking.label,
      height: height,
      color: color ?? p?.textSecondary ?? AppColors.textSecondary,
    );
  }

  /// Wide all-caps section overline style (11dp, w800, +1.2 tracking).
  static TextStyle overline({
    BuildContext? context,
    Color? color,
    FontWeight? weight,
    double? fontSize,
    double? height = 1.2,
    double? letterSpacing,
  }) {
    final p = context?.palette;
    return TextStyle(
      fontFamily: fontFamily,
      fontFamilyFallback: fontFallbacks,
      fontSize: fontSize ?? AppFontSize.caption,
      fontWeight: weight ?? FontWeight.w800,
      letterSpacing: letterSpacing ?? AppTracking.wide,
      height: height,
      color: color ?? p?.textTertiary ?? AppColors.textSecondary,
    );
  }
}
