// lib/core/constants/app_typography.dart

/// Canonical type scale for the app.
///
/// Mirrors the Apple HIG / Material 3 idea of a small, fixed set of text sizes
/// instead of ad-hoc values. Use these instead of raw `fontSize` numbers so the
/// whole app stays on one scale.
///
/// | token | size | role |
/// |---|---|---|
/// | micro | 9 | badges, counters |
/// | tiny | 10 | dense micro-labels |
/// | caption | 11 | captions, timer readouts |
/// | label | 12 | chips, meta, overlines |
/// | bodySmall | 13 | secondary rows |
/// | body | 14 | default body |
/// | callout | 15 | emphasised body |
/// | bodyLarge | 16 | song titles, list primary |
/// | title | 18 | section/card titles |
/// | titleLarge | 20 | screen titles |
/// | headline | 24 | large headings |
/// | display | 28 | hero headings |
/// | displayLarge | 32 | numeric hero values |
abstract class AppFontSize {
  static const double micro = 9;
  static const double tiny = 10;
  static const double caption = 11;
  static const double label = 12;
  static const double bodySmall = 13;
  static const double body = 14;
  static const double callout = 15;
  static const double bodyLarge = 16;
  static const double title = 18;
  static const double titleLarge = 20;
  static const double headline = 24;
  static const double display = 28;
  static const double displayLarge = 32;
}

/// Canonical letter-spacing (tracking) scale.
///
/// Negative tracking tightens large display text; positive tracking opens up
/// small overlines and all-caps labels. Keeping a single scale stops the app
/// from accumulating a dozen near-identical `.3/.4/.5` values.
abstract class AppTracking {
  /// −0.8 — large display / hero numerals.
  static const double display = -0.8;

  /// −0.4 — headings.
  static const double heading = -0.4;

  /// −0.2 — titles.
  static const double title = -0.2;

  /// 0.0 — body copy.
  static const double none = 0.0;

  /// 0.3 — labels.
  static const double label = 0.3;

  /// 0.5 — medium emphasis labels.
  static const double medium = 0.5;

  /// 0.8 — overlines / small caps.
  static const double overline = 0.8;

  /// 1.2 — wide overlines.
  static const double wide = 1.2;

  /// 2.0 — extra-wide branding.
  static const double widest = 2.0;
}
