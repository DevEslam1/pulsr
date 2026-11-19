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
    required double keyAlpha,
    required double ambAlpha,
    required double keyBlur,
    required double ambBlur,
    required double keyDy,
    required double ambDy,
  }) {
    // Light mode needs far less ink to read the same depth.
    final scale = isDark ? 1.0 : 0.45;
    // Over pure black both translucency and shadow lose signal, so the ambient
    // pass needs more ink to keep a surface from reading as a flat rectangle.
    final ambientScale = isAmoled ? 1.25 : 1.0;
    return [
      BoxShadow(
        color: AppColors.scrimAt(keyAlpha * scale),
        blurRadius: keyBlur,
        offset: Offset(0, keyDy),
      ),
      BoxShadow(
        color: AppColors.scrimAt(ambAlpha * scale * ambientScale),
        blurRadius: ambBlur,
        offset: Offset(0, ambDy),
      ),
    ];
  }

  static bool _isAmoled(dynamic contextOrPalette) {
    final candidate = contextOrPalette is BuildContext
        ? contextOrPalette.palette
        : contextOrPalette;
    if (candidate is! PulsrPalette || !candidate.isDark) return false;
    // AMOLED's base is pure black; dark's is #12151D.
    return candidate.bg.computeLuminance() < 0.005;
  }

  static bool _isDark(dynamic contextOrPalette) {
    if (contextOrPalette is BuildContext) {
      return contextOrPalette.palette.isDark;
    }
    if (contextOrPalette is PulsrPalette) return contextOrPalette.isDark;
    return true;
  }
}
