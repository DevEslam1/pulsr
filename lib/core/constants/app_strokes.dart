import 'package:material_ui/material_ui.dart';

/// {@category DesignSystem}
/// Stroke widths for borders, dividers and focus rings.
///
/// The UI previously authored `0.7 / 0.8 / 1 / 1.0 / 1.2 / 1.5` independently.
/// At 1x DPR these are visually indistinguishable, so the difference bought no
/// hierarchy — only drift. Use [hairline] for a surface's thin edge,
/// [hairlineSubtle] where a lighter touch is wanted over artwork, and
/// [divider] for separators. [focusWidth] and [focusWidthHighContrast] are the
/// only sanctioned focus-ring widths.
abstract class AppStrokes {
  AppStrokes._();

  /// 1.0 — the default edge of a card, sheet, dialog, chip or tile.
  static const double hairline = 1.0;

  /// 0.75 — a deliberately lighter hairline over artwork or glass.
  static const double hairlineSubtle = 0.75;

  /// 1.0 — list/divider separators.
  static const double divider = 1.0;

  /// 2.0 — keyboard focus ring.
  static const double focusWidth = 2.0;

  /// 1.5 — focus ring in dense chrome.
  static const double focusWidthSubtle = 1.5;

  /// 2.6 — focus ring under Pulsr High Contrast.
  static const double focusWidthHighContrast = 2.6;

  /// Convenience: a hairline [BorderSide] in [color].
  static BorderSide side(Color color, {double width = hairline}) =>
      BorderSide(color: color, width: width);
}
