// lib/core/theme/pulsr_button_style.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../constants/app_radii.dart';
import '../../features/settings/cubit/settings_cubit.dart';
import '../../features/settings/cubit/settings_state.dart';
import 'aura_theme.dart';

export '../../features/settings/cubit/settings_state.dart' show AppButtonStyle;

/// Helper extension on [BuildContext] to inspect the user's preferred button & chip style.
extension AppButtonStyleContextX on BuildContext {
  /// The active [AppButtonStyle] from [SettingsCubit], defaulting to [AppButtonStyle.rectangular].
  AppButtonStyle get appButtonStyle {
    try {
      return select<SettingsCubit, AppButtonStyle>(
        (c) => c.state.appButtonStyle,
      );
    } catch (_) {
      return AppButtonStyle.rectangular;
    }
  }

  /// Whether frosted glass button styling (rectangular or capsule) is active.
  bool get isGlassButtons =>
      appButtonStyle == AppButtonStyle.rectangular ||
      appButtonStyle == AppButtonStyle.capsule;

  /// Whether the button style is rectangular frosted glass.
  bool get isRectangularButtons => appButtonStyle == AppButtonStyle.rectangular;

  /// Backwards compatibility alias for frosted glass styling.
  bool get isCapsuleButtons => isGlassButtons;

  /// Resolves the border radius according to active button style.
  BorderRadius buttonRadius({double rectRadius = 6.0}) {
    return PulsrCapsuleStyle.resolveRadius(appButtonStyle, rectRadius: rectRadius);
  }
}

/// Token constants and decoration factories for the translucent frosted glass
/// button, badge, and chip design (matching the badge under the seek bar slider).
class PulsrCapsuleStyle {
  const PulsrCapsuleStyle._();

  /// Resolves the border radius for the active [style].
  static BorderRadius resolveRadius(
    AppButtonStyle style, {
    double rectRadius = 6.0,
  }) {
    switch (style) {
      case AppButtonStyle.rectangular:
        return BorderRadius.circular(rectRadius);
      case AppButtonStyle.capsule:
        return AppRadii.full;
      case AppButtonStyle.classic:
        return BorderRadius.circular(rectRadius);
    }
  }

  /// Translucent frosted glass surface background.
  static Color backgroundColor(PulsrPalette p) {
    return p.isDark
        ? Colors.white.withValues(alpha: 0.16)
        : Colors.black.withValues(alpha: 0.08);
  }

  /// Translucent specular hairline border.
  static Border border(PulsrPalette p, {double width = 0.8}) {
    return Border.all(
      color: p.isDark
          ? Colors.white.withValues(alpha: 0.12)
          : Colors.black.withValues(alpha: 0.08),
      width: width,
    );
  }

  /// Primary high-contrast foreground color on the frosted glass surface.
  static Color foregroundColor(PulsrPalette p) {
    return p.isDark ? Colors.white : p.textPrimary;
  }

  /// Secondary muted foreground color on the frosted glass surface.
  static Color secondaryForegroundColor(PulsrPalette p) {
    return (p.isDark ? Colors.white : p.textPrimary).withValues(alpha: 0.72);
  }

  /// Standard decoration for a frosted glass rectangular or capsule pill.
  static BoxDecoration decoration(
    PulsrPalette p, {
    BorderRadius? borderRadius,
    double radius = 6.0,
    Color? customBg,
    Border? customBorder,
    List<BoxShadow>? shadows,
  }) {
    return BoxDecoration(
      color: customBg ?? backgroundColor(p),
      borderRadius: borderRadius ?? BorderRadius.circular(radius),
      border: customBorder ?? border(p),
      boxShadow: shadows,
    );
  }
}
