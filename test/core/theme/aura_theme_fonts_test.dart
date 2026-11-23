// Regression guard: component styles in [AuraTheme] must keep the app's
// Manrope font family.
//
// Component themes that set `textStyle` REPLACE the theme's default label
// style (which carries the font family), so omitting the family silently
// falls back to the platform font — a visible typography inconsistency in
// buttons, chips, tabs and navigation labels.
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/theme/aura_theme.dart';

double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final bright = la > lb ? la : lb;
  final dark = la > lb ? lb : la;
  return (bright + 0.05) / (dark + 0.05);
}

void main() {
  const manrope = 'Manrope';

  final themes = <String, ThemeData>{
    'dark': AuraTheme.darkTheme,
    'light': AuraTheme.lightTheme,
  };

  for (final entry in themes.entries) {
    final name = entry.key;
    final theme = entry.value;

    group('$name theme declares $manrope on component text styles', () {
      test('buttons', () {
        final states = <WidgetState>{};
        expect(
            theme.filledButtonTheme.style?.textStyle
                ?.resolve(states)
                ?.fontFamily,
            manrope);
        expect(
            theme.elevatedButtonTheme.style?.textStyle
                ?.resolve(states)
                ?.fontFamily,
            manrope);
        expect(
            theme.outlinedButtonTheme.style?.textStyle
                ?.resolve(states)
                ?.fontFamily,
            manrope);
        expect(
            theme.textButtonTheme.style?.textStyle?.resolve(states)?.fontFamily,
            manrope);
      });

      test('app bar, chips, snack bar and inputs', () {
        expect(theme.appBarTheme.titleTextStyle?.fontFamily, manrope);
        expect(theme.chipTheme.labelStyle?.fontFamily, manrope);
        expect(theme.chipTheme.secondaryLabelStyle?.fontFamily, manrope);
        expect(theme.snackBarTheme.contentTextStyle?.fontFamily, manrope);
        expect(theme.inputDecorationTheme.hintStyle?.fontFamily, manrope);
      });

      test('navigation and tabs', () {
        final states = <WidgetState>{};
        expect(
            theme.navigationBarTheme.labelTextStyle
                ?.resolve(states)
                ?.fontFamily,
            manrope);
        expect(theme.navigationRailTheme.selectedLabelTextStyle?.fontFamily,
            manrope);
        expect(theme.navigationRailTheme.unselectedLabelTextStyle?.fontFamily,
            manrope);
        expect(theme.tabBarTheme.labelStyle?.fontFamily, manrope);
        expect(theme.tabBarTheme.unselectedLabelStyle?.fontFamily, manrope);
      });
    });
  }

  group('AuraTheme token contracts (H-21)', () {
    test('PulsrPalette derives accentMedium dynamically from accent', () {
      const green = Color(0xFF10B981);
      const customPalette = PulsrPalette(
        accent: green,
        onAccent: Colors.black,
        accentContainer: Color(0x2010B981),
        glow: Color(0x3010B981),
        bg: Colors.black,
        surface: Color(0xFF111111),
        surfaceContainer: Color(0xFF1A1A1A),
        surfaceContainerHigh: Color(0xFF222222),
        hairline: Color(0x20FFFFFF),
        textPrimary: Colors.white,
        textSecondary: Color(0xFFAAAAAA),
        textTertiary: Color(0xFF888888),
        favorite: Color(0xFFF43F5E),
        success: Color(0xFF4CAF50),
        error: Color(0xFFFF5252),
        isDark: true,
        playerCard: Color(0xFF111111),
        deepShade: Colors.black,
      );
      expect(customPalette.accentMedium, equals(green.withValues(alpha: 0.25)));
      expect(customPalette.accentMedium, isNot(equals(const Color(0x409B9EF5))));
    });

    test('switch and slider thumbs use palette tokens instead of raw white',
        () {
      final lightBright = AuraTheme.customTheme(
        AppColors.dacGold,
        brightness: Brightness.dark,
      );
      final p = lightBright.extension<PulsrPalette>()!;
      expect(
        lightBright.switchTheme.thumbColor?.resolve({WidgetState.selected}),
        equals(p.onAccent),
      );
      expect(lightBright.sliderTheme.thumbColor, equals(p.accent));
    });

    test('light and light high-contrast favorite/info tokens meet WCAG AA/AAA',
        () {
      final lightPalette = AuraTheme.lightTheme.extension<PulsrPalette>()!;
      final hcLightPalette = AuraTheme.highContrastThemeFor(Brightness.light)
          .extension<PulsrPalette>()!;

      expect(_contrastRatio(lightPalette.favorite, lightPalette.surface),
          greaterThanOrEqualTo(4.5));
      expect(_contrastRatio(lightPalette.info, lightPalette.surface),
          greaterThanOrEqualTo(4.5));
      expect(_contrastRatio(hcLightPalette.favorite, hcLightPalette.surface),
          greaterThanOrEqualTo(7.0));
      expect(_contrastRatio(hcLightPalette.info, hcLightPalette.surface),
          greaterThanOrEqualTo(7.0));
    });
  });
}
