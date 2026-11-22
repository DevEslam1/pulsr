part of '../clean_player_theme.dart';

/// Brightness-aware foreground and surface palette for Clean Modern Flow.
///
/// Resolved once per widget from [PulsrPalette] so Light, Dark, AMOLED, and
/// High Contrast modes all maintain crisp contrast without hardcoded whites.
class _CleanDeckColors {
  const _CleanDeckColors({
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.frostedFill,
    required this.frostedBorder,
    required this.chipFill,
    required this.chipBorder,
    required this.sliderActive,
    required this.sliderActiveScrub,
    required this.sliderInactive,
  });

  factory _CleanDeckColors.of(BuildContext context) {
    final p = context.palette;
    final wash = p.isDark ? AppColors.onPrimary : p.textPrimary;
    return _CleanDeckColors(
      primary: p.textPrimary,
      secondary: p.textSecondary,
      tertiary: p.textTertiary,
      frostedFill: wash.withValues(alpha: p.isDark ? 0.14 : 0.07),
      frostedBorder: p.isDark ? AppColors.specularAt(0.14) : p.hairline,
      chipFill: wash.withValues(alpha: p.isDark ? 0.14 : 0.06),
      chipBorder: p.isDark ? AppColors.specularAt(0.14) : p.hairline,
      sliderActive: p.textPrimary.withValues(alpha: p.isDark ? 0.88 : 0.84),
      sliderActiveScrub: p.textPrimary,
      sliderInactive: p.textPrimary.withValues(alpha: p.isDark ? 0.22 : 0.18),
    );
  }

  /// Titles, primary transport glyphs, and active scrubbing timestamp.
  final Color primary;

  /// Artist subtitle, idle timestamps, and secondary dock icons.
  final Color secondary;

  /// Disabled transport glyphs and subtle hints.
  final Color tertiary;

  /// Translucent circle fill behind header action buttons.
  final Color frostedFill;

  /// Subtle hairline rim around frosted action buttons.
  final Color frostedBorder;

  /// Audio quality / Lossless pill fill and border.
  final Color chipFill;
  final Color chipBorder;

  /// Played fill of the capsule scrubber at rest.
  final Color sliderActive;

  /// Played fill of the capsule scrubber while actively dragging.
  final Color sliderActiveScrub;

  /// Unplayed translucent track of the capsule scrubber.
  final Color sliderInactive;
}

/// Visual diameter of header frosted action circles (padded to 48dp touch area).
const double _cleanActionCircleSize = 36.0;
