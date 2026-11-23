// lib/core/theme/pulsr_button_style.dart
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../constants/app_colors.dart';
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
    return PulsrCapsuleStyle.resolveRadius(appButtonStyle,
        rectRadius: rectRadius);
  }
}

/// Token constants and decoration factories for the translucent frosted glass
/// button, badge, and chip design (matching the badge under the seek bar slider).
class PulsrCapsuleStyle {
  const PulsrCapsuleStyle._();

  /// Resolves the border radius for the active [style].
  static BorderRadius resolveRadius(AppButtonStyle style,
      {double rectRadius = 10.0}) {
    switch (style) {
      case AppButtonStyle.rectangular:
        return BorderRadius.circular(rectRadius);
      case AppButtonStyle.capsule:
        return AppRadii.full;
      case AppButtonStyle.classic:
        return BorderRadius.circular(rectRadius);
    }
  }

  /// Aurora glass: crisp fill, legible specular edge, and solid high-contrast
  /// fallback when [PulsrPalette.isHighContrast] is active.
  static Color backgroundColor(PulsrPalette p) {
    if (p.isHighContrast) return p.surfaceContainer;
    if (p.isAmoled) return Colors.white.withValues(alpha: 0.11);
    return p.isDark
        ? Colors.white.withValues(alpha: 0.10)
        : AppColors.inkSlateAt(0.065);
  }

  static Border border(PulsrPalette p, {double width = 0.8}) {
    if (p.isHighContrast) {
      return Border.all(
        color: p.borderStrong,
        width: width < 1.5 ? 1.5 : width,
      );
    }
    return Border.all(
      color: p.isDark
          ? Colors.white.withValues(alpha: p.isAmoled ? 0.18 : 0.14)
          : AppColors.inkSlateAt(0.14),
      width: width,
    );
  }

  /// NEW: subtle top-lit gradient for larger glass surfaces (docks, clusters).
  static LinearGradient surfaceSheen(PulsrPalette p) {
    if (p.isHighContrast) {
      return LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [p.surfaceContainer, p.surfaceContainer],
      );
    }
    final spec = p.specularScale;
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: p.isDark
          ? [
              Colors.white.withValues(alpha: 0.13 * spec),
              Colors.white.withValues(alpha: 0.07 * spec),
            ]
          : [
              Colors.white.withValues(alpha: 0.72),
              Colors.white.withValues(alpha: 0.46),
            ],
    );
  }

  /// Primary high-contrast foreground color on the frosted glass surface.
  static Color foregroundColor(PulsrPalette p) {
    return p.isDark ? Colors.white : p.textPrimary;
  }

  /// Secondary muted foreground color on the frosted glass surface.
  static Color secondaryForegroundColor(PulsrPalette p) {
    if (p.isHighContrast) return p.textSecondary;
    return (p.isDark ? Colors.white : p.textPrimary).withValues(alpha: 0.74);
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
