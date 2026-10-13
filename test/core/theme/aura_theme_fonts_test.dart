// Regression guard: component styles in [AuraTheme] must keep the app's
// Manrope font family.
//
// Component themes that set `textStyle` REPLACE the theme's default label
// style (which carries the font family), so omitting the family silently
// falls back to the platform font — a visible typography inconsistency in
// buttons, chips, tabs and navigation labels.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';

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
            theme.textButtonTheme.style?.textStyle
                ?.resolve(states)
                ?.fontFamily,
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
}
