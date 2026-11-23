import 'package:material_ui/material_ui.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/theme/aura_theme.dart';

/// {@category DesignSystem}
/// Aurora elevation: every level pairs a tight directional *key* shadow with a
/// wide, soft *ambient* shadow. Single-shadow elevation reads as a grey sticker;
/// the pair reads as a physical surface lit from above.
///
/// - [level0]: flat
/// - [level1]: cards & tiles at rest
/// - [level2]: cards hovered / pressed
/// - [level3]: sheets, dialogs, popovers
/// - [level4]: floating dock, now-playing hero
class PulsrElevation {
  const PulsrElevation._();

  static const List<BoxShadow> level0 = [];

  static List<BoxShadow> level1([dynamic contextOrPalette]) => _pair(
        _isDark(contextOrPalette),
        isAmoled: _isAmoled(contextOrPalette),
        isCalmDensity: _isCalmDensity(contextOrPalette),
        isHighContrast: _isHighContrast(contextOrPalette),
        keyAlpha: 0.16,
        ambAlpha: 0.10,
        keyBlur: 3,
        ambBlur: 8,
        keyDy: 1,
        ambDy: 2,
      );

  static List<BoxShadow> level2([dynamic contextOrPalette]) => _pair(
        _isDark(contextOrPalette),
        isAmoled: _isAmoled(contextOrPalette),
        isCalmDensity: _isCalmDensity(contextOrPalette),
        isHighContrast: _isHighContrast(contextOrPalette),
        keyAlpha: 0.24,
        ambAlpha: 0.16,
        keyBlur: 6,
        ambBlur: 14,
        keyDy: 2,
        ambDy: 4,
      );

  static List<BoxShadow> level3([dynamic contextOrPalette]) => _pair(
        _isDark(contextOrPalette),
        isAmoled: _isAmoled(contextOrPalette),
        isCalmDensity: _isCalmDensity(contextOrPalette),
        isHighContrast: _isHighContrast(contextOrPalette),
        keyAlpha: 0.34,
        ambAlpha: 0.24,
        keyBlur: 10,
        ambBlur: 24,
        keyDy: 4,
        ambDy: 8,
      );

  static List<BoxShadow> level4([dynamic contextOrPalette]) => _pair(
        _isDark(contextOrPalette),
        isAmoled: _isAmoled(contextOrPalette),
        isCalmDensity: _isCalmDensity(contextOrPalette),
        isHighContrast: _isHighContrast(contextOrPalette),
        keyAlpha: 0.44,
        ambAlpha: 0.32,
        keyBlur: 16,
        ambBlur: 40,
        keyDy: 8,
        ambDy: 16,
      );

  static List<BoxShadow> _pair(
    bool isDark, {
    bool isAmoled = false,
    bool isCalmDensity = false,
    bool isHighContrast = false,
    required double keyAlpha,
    required double ambAlpha,
    required double keyBlur,
    required double ambBlur,
    required double keyDy,
    required double ambDy,
  }) {
    if (isHighContrast) {
      // High Contrast communicates hierarchy through crisp borders rather than
      // wide blurred shadows; keep only a tight grounding key shadow.
      return [
        BoxShadow(
          color: isDark
              ? AppColors.scrimAt(0.40)
              : AppColors.inkSlateAt(0.14),
          blurRadius: keyBlur,
          offset: Offset(0, keyDy),
        ),
      ];
    }
    // Light mode uses cool-slate shadows at lower ink so cards lift crisply
    // instead of reading as muddy grey stickers.
    final scale = isDark ? 1.0 : 0.36;
    final calmScale = isCalmDensity ? 0.65 : 1.0;
    // Over pure black both translucency and shadow lose signal, so the ambient
    // pass needs more ink to keep a surface from reading as a flat rectangle.
    final ambientScale = isAmoled ? 1.25 : 1.0;
    final shadowBase = isDark ? AppColors.scrimAt : AppColors.inkSlateAt;
    return [
      BoxShadow(
        color: shadowBase((keyAlpha * scale * calmScale).clamp(0.0, 1.0)),
        blurRadius: keyBlur,
        offset: Offset(0, keyDy),
      ),
      BoxShadow(
        color: shadowBase(
            (ambAlpha * scale * ambientScale * calmScale).clamp(0.0, 1.0)),
        blurRadius: ambBlur,
        offset: Offset(0, ambDy),
      ),
    ];
  }

  static PulsrPalette? _paletteOf(dynamic contextOrPalette) {
    if (contextOrPalette is BuildContext) return contextOrPalette.palette;
    if (contextOrPalette is PulsrPalette) return contextOrPalette;
    return null;
  }

  static bool _isAmoled(dynamic contextOrPalette) =>
      _paletteOf(contextOrPalette)?.isAmoled ?? false;

  static bool _isCalmDensity(dynamic contextOrPalette) =>
      _paletteOf(contextOrPalette)?.isCalmDensity ?? false;

  static bool _isHighContrast(dynamic contextOrPalette) =>
      _paletteOf(contextOrPalette)?.isHighContrast ?? false;

  static bool _isDark(dynamic contextOrPalette) =>
      _paletteOf(contextOrPalette)?.isDark ?? true;
}
