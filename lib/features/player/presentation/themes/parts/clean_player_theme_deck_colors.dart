part of '../clean_player_theme.dart';

/// Every foreground colour Clean's lower deck paints, resolved once from the
/// live [PulsrPalette].
///
/// Clean used to hardcode `Colors.white` for the title, artist, timestamps,
/// transport glyphs, the seek bar and the Lossless pill. Over a dark deck that
/// is exactly the Apple look, but in `AuraTheme.lightTheme` the deck sits on
/// [PlayerThemeProps.bgColor] (derived from `colorScheme.surface`, so light)
/// and the whole lower half turned white-on-light. One palette-backed value
/// set keeps every child consistent instead of re-deriving ad-hoc alphas per
/// widget, which is how the theme drifted in the first place.
class _CleanDeckColors {
  const _CleanDeckColors({
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.frostedFill,
    required this.chipFill,
    required this.chipBorder,
    required this.sliderActive,
    required this.sliderInactive,
  });

  /// Resolves the deck palette for [context].
  factory _CleanDeckColors.of(BuildContext context) {
    final p = context.palette;
    // A "wash" is the translucent fill behind the frosted action circles and
    // the Lossless pill. White is only correct while the deck itself is dark;
    // on the light deck the same soft chip is ink, otherwise it vanishes.
    final wash = p.isDark ? Colors.white : p.textPrimary;
    return _CleanDeckColors(
      primary: p.textPrimary,
      secondary: p.textSecondary,
      tertiary: p.textTertiary,
      frostedFill: wash.withValues(alpha: p.isDark ? 0.16 : 0.07),
      chipFill: wash.withValues(alpha: p.isDark ? 0.16 : 0.06),
      chipBorder: p.isDark ? wash.withValues(alpha: 0.12) : p.hairline,
      sliderActive: p.textPrimary.withValues(alpha: p.isDark ? 1.0 : 0.82),
      sliderInactive: p.textPrimary.withValues(alpha: p.isDark ? 0.22 : 0.20),
    );
  }

  /// Titles, the play/pause glyph, enabled transport glyphs and the timestamp
  /// being scrubbed.
  final Color primary;

  /// Artist line, idle timestamps and inactive shuffle/repeat glyphs.
  final Color secondary;

  /// Unavailable neighbours (no previous/next track) and other de-emphasised
  /// affordances.
  final Color tertiary;

  /// Frosted circle fill behind the header actions.
  final Color frostedFill;

  /// Lossless pill fill and its hairline border.
  final Color chipFill;
  final Color chipBorder;

  /// Played part of the seek bar. Stays monochrome (textPrimary) rather than
  /// the accent so the bar keeps Apple's quiet hierarchy in both brightnesses.
  final Color sliderActive;

  /// Unplayed part of the seek bar.
  final Color sliderInactive;
}

/// Diameter of the visible frosted circle. The tappable box is larger — see
/// [_CleanActionCircleButton].
const double _cleanActionCircleSize = 36;
