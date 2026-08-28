import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/theme/aura_theme.dart';

double _relativeLuminance(Color color) {
  double channelLuminance(double value) {
    return value <= 0.04045
        ? value / 12.92
        : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  }

  final r = channelLuminance(color.r);
  final g = channelLuminance(color.g);
  final b = channelLuminance(color.b);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

double _contrastRatio(Color c1, Color c2) {
  final l1 = _relativeLuminance(c1);
  final l2 = _relativeLuminance(c2);
  final lighter = math.max(l1, l2);
  final darker = math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('Theme Palette and Accent Variations', () {
    final accents = <String, Color>{
      'Neon Cyan': const Color(0xFF00E5FF),
      'Deep Violet': const Color(0xFF9B9EF5),
      'Sunset Amber': const Color(0xFFFF9100),
      'Electric Emerald': const Color(0xFF00E676),
      'Monokai Magenta': const Color(0xFFFF007F),
    };

    test('WCAG 2.1 AA Contrast: lightTextSecondary against lightBackground >= 4.5:1 (BUG-024)', () {
      final ratioBg = _contrastRatio(AppColors.lightTextSecondary, AppColors.lightBackground);
      final ratioSurface = _contrastRatio(AppColors.lightTextSecondary, AppColors.lightSurface);
      
      expect(ratioBg, greaterThanOrEqualTo(4.5),
          reason: 'lightTextSecondary must meet WCAG AA normal text contrast (4.5:1) on lightBackground');
      expect(ratioSurface, greaterThanOrEqualTo(4.5),
          reason: 'lightTextSecondary must meet WCAG AA normal text contrast (4.5:1) on lightSurface');
    });

    for (final entry in accents.entries) {
      test('Theme builds valid palette for ${entry.key}', () {
        final darkTheme =
            AuraTheme.customTheme(entry.value, brightness: Brightness.dark);
        final lightTheme =
            AuraTheme.customTheme(entry.value, brightness: Brightness.light);
        final amoledTheme = AuraTheme.customTheme(entry.value,
            brightness: Brightness.dark, isAmoled: true);

        final darkPalette = darkTheme.extension<PulsrPalette>();
        final lightPalette = lightTheme.extension<PulsrPalette>();
        final amoledPalette = amoledTheme.extension<PulsrPalette>();

        expect(darkPalette, isNotNull);
        expect(lightPalette, isNotNull);
        expect(amoledPalette, isNotNull);

        expect(darkPalette!.accent, equals(entry.value));
        expect(amoledPalette!.bg, equals(Colors.black));
        expect(lightPalette!.isDark, isFalse);
      });
    }

    testWidgets('Renders mini player and card across all 5 accent themes',
        (tester) async {
      for (final entry in accents.entries) {
        final theme =
            AuraTheme.customTheme(entry.value, brightness: Brightness.dark);

        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Builder(
              builder: (context) {
                final p = context.palette;
                return Scaffold(
                  backgroundColor: p.bg,
                  body: Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: p.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: p.accent),
                      ),
                      child: Text(
                        entry.key,
                        style: TextStyle(color: p.textPrimary),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );

        await tester.pumpAndSettle();
        expect(find.text(entry.key), findsOneWidget);
      }
    });
  });
}
