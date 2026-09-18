// lib/core/constants/app_spacing.dart

/// Canonical spacing rhythm for the whole app.
///
/// Apple HIG comfortable rhythm and Material 3 both derive layout from a small
/// 4 dp base scale. Use these tokens instead of raw numbers so gutters, gaps
/// and insets can never drift between screens.
///
/// - [xxs]..[xxl] are the semantic steps used for layout rhythm.
/// - `sN` constants cover the half-steps that already exist in the design
///   (badges, dense chrome) so adoption is value-preserving.
abstract class AppSpacing {
  // ── Semantic scale ──────────────────────────────────────────────────────
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  // ── Half-steps ──────────────────────────────────────────────────────────
  static const double s2 = 2;
  static const double s6 = 6;
  static const double s10 = 10;
  static const double s14 = 14;
  static const double s18 = 18;
  static const double s20 = 20;
  static const double s28 = 28;
  static const double s40 = 40;
  static const double s64 = 64;

  /// Bottom padding so content clears the mini-player + nav dock.
  static const double scrollBottom = 160;
}
