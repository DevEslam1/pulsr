import 'package:material_ui/material_ui.dart';

/// WCAG 2.4.7 focus indication + 1.4.11 non-text contrast.
/// Aurora focus = crisp 2dp accent ring + a 1dp contrast halo so the ring is
/// visible on *any* surface, plus an optional soft glow.
abstract class FocusTokens {
  static BorderSide ringSide(Color accentColor) =>
      BorderSide(color: accentColor, width: 2.0);

  /// Contrast halo drawn just outside the accent ring (dark UI → white halo,
  /// light UI → black halo) so accent-on-accent-tinted surfaces still pass.
  static BorderSide contrastHalo(bool isDark) => BorderSide(
        color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.55),
        width: 1.0,
      );

  static List<BoxShadow> focusRingShadow(Color accentColor) => [
        BoxShadow(
          color: accentColor.withValues(alpha: 0.35),
          blurRadius: 8,
          spreadRadius: 2,
        ),
      ];

  /// Complete focused decoration for custom (non-Material) focusables.
  static BoxDecoration ring(
    Color accentColor, {
    required bool isDark,
    BorderRadius radius = const BorderRadius.all(Radius.circular(12)),
  }) =>
      BoxDecoration(
        borderRadius: radius,
        border: Border.fromBorderSide(ringSide(accentColor)),
        boxShadow: [
          BoxShadow(
            color:
                (isDark ? Colors.white : Colors.black).withValues(alpha: 0.5),
            spreadRadius: 3.0,
            blurRadius: 0,
          ),
          ...focusRingShadow(accentColor),
        ],
      );
}
