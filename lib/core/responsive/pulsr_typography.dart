// lib/core/responsive/pulsr_typography.dart
import 'package:flutter/material.dart';
import '../constants/app_typography.dart';
import 'responsive_typography.dart';

export 'responsive_typography.dart';

/// Unified responsive text styles scaling cleanly across device classes and respecting text scaler limits.
class PulsrTextStyles {
  static TextStyle display(BuildContext context,
      {Color? color, FontWeight? fontWeight}) {
    final typo = context.responsiveTypography;
    return TextStyle(
      fontSize: typo.display,
      fontWeight: fontWeight ?? FontWeight.w800,
      letterSpacing: AppTracking.display,
      color: color,
    );
  }

  static TextStyle headline(BuildContext context,
      {Color? color, FontWeight? fontWeight}) {
    final typo = context.responsiveTypography;
    return TextStyle(
      fontSize: typo.headline,
      fontWeight: fontWeight ?? FontWeight.w700,
      letterSpacing: AppTracking.heading,
      color: color,
    );
  }

  static TextStyle title(BuildContext context,
      {Color? color, FontWeight? fontWeight}) {
    final typo = context.responsiveTypography;
    return TextStyle(
      fontSize: typo.title,
      fontWeight: fontWeight ?? FontWeight.w700,
      letterSpacing: AppTracking.title,
      color: color,
    );
  }

  static TextStyle body(BuildContext context,
      {Color? color, FontWeight? fontWeight}) {
    final typo = context.responsiveTypography;
    return TextStyle(
      fontSize: typo.body,
      fontWeight: fontWeight ?? FontWeight.w500,
      color: color,
    );
  }

  static TextStyle label(BuildContext context,
      {Color? color, FontWeight? fontWeight}) {
    final typo = context.responsiveTypography;
    return TextStyle(
      fontSize: typo.label,
      fontWeight: fontWeight ?? FontWeight.w600,
      color: color,
    );
  }

  static TextStyle caption(BuildContext context,
      {Color? color, FontWeight? fontWeight}) {
    final typo = context.responsiveTypography;
    return TextStyle(
      fontSize: typo.caption,
      fontWeight: fontWeight ?? FontWeight.w400,
      color: color,
    );
  }

  static TextStyle overline(BuildContext context, {Color? color}) {
    final typo = context.responsiveTypography;
    return TextStyle(
      fontSize: (typo.caption - 1.0).clamp(9.0, 12.0),
      fontWeight: FontWeight.w700,
      letterSpacing: 0.5,
      color: color,
    );
  }
}
