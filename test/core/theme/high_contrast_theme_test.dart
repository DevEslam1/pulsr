// test/core/theme/high_contrast_theme_test.dart
//
// The high-contrast setting must produce a genuinely higher-contrast palette
// and stronger outlines — not the byte-identical theme it used to alias.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';

double _luminance(Color color) {
  double channel(double value) => value <= 0.04045
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('high-contrast theme', () {
    test('light variant reaches WCAG AAA text contrast on its background', () {
      final theme = AuraTheme.highContrastThemeFor(Brightness.light);
      final p = theme.extension<PulsrPalette>()!;

      expect(theme.brightness, Brightness.light);
      expect(_contrast(p.textPrimary, p.bg), greaterThanOrEqualTo(7.0));
      expect(_contrast(p.textSecondary, p.bg), greaterThanOrEqualTo(7.0));
      expect(_contrast(p.textTertiary, p.bg), greaterThanOrEqualTo(7.0));
    });

    test('dark variant reaches WCAG AAA text contrast on its background', () {
      final theme = AuraTheme.highContrastThemeFor(Brightness.dark);
      final p = theme.extension<PulsrPalette>()!;

      expect(theme.brightness, Brightness.dark);
      expect(p.bg, Colors.black);
      expect(_contrast(p.textPrimary, p.bg), greaterThanOrEqualTo(7.0));
      expect(_contrast(p.textSecondary, p.bg), greaterThanOrEqualTo(7.0));
      expect(_contrast(p.textTertiary, p.bg), greaterThanOrEqualTo(7.0));
    });

    test('tertiary text contrast is measurably stronger than the normal theme',
        () {
      for (final brightness in Brightness.values) {
        final normal =
            AuraTheme.customTheme(Colors.cyan, brightness: brightness);
        final high =
            AuraTheme.highContrastThemeFor(brightness, seed: Colors.cyan);
        final normalP = normal.extension<PulsrPalette>()!;
        final highP = high.extension<PulsrPalette>()!;

        expect(
          _contrast(highP.textTertiary, highP.bg),
          greaterThan(_contrast(normalP.textTertiary, normalP.bg)),
          reason: '$brightness high-contrast tertiary text must improve',
        );
      }
    });

    test('outlines and focus rings are stronger than the normal theme', () {
      for (final brightness in Brightness.values) {
        final normal =
            AuraTheme.customTheme(Colors.cyan, brightness: brightness);
        final high =
            AuraTheme.highContrastThemeFor(brightness, seed: Colors.cyan);
        final normalP = normal.extension<PulsrPalette>()!;
        final highP = high.extension<PulsrPalette>()!;

        expect(highP.hairline.a, greaterThan(normalP.hairline.a),
            reason: '$brightness hairline must be stronger');

        final normalCardSide =
            (normal.cardTheme.shape as RoundedRectangleBorder).side;
        final highCardSide =
            (high.cardTheme.shape as RoundedRectangleBorder).side;
        expect(highCardSide.width, greaterThan(normalCardSide.width));

        final normalFocus =
            normal.inputDecorationTheme.focusedBorder as OutlineInputBorder;
        final highFocus =
            high.inputDecorationTheme.focusedBorder as OutlineInputBorder;
        expect(highFocus.borderSide.width,
            greaterThan(normalFocus.borderSide.width));
      }
    });
  });
}
