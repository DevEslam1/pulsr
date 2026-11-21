// test/core/theme/player_surface_palette_test.dart
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pulsr/core/theme/aura_theme.dart';

double _relativeLuminance(Color color) {
  double channel(double value) => value <= 0.04045
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

double _contrastRatio(Color fg, Color bg) {
  final effectiveFg = fg.a < 1.0 ? Color.alphaBlend(fg, bg) : fg;
  final l1 = _relativeLuminance(effectiveFg);
  final l2 = _relativeLuminance(bg);
  final lighter = math.max(l1, l2);
  final darker = math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('PlayerSurfacePalette ThemeExtension', () {
    final modes = <String, ThemeData>{
      'Dark': AuraTheme.darkTheme,
      'Light': AuraTheme.lightTheme,
      'AMOLED': AuraTheme.amoledTheme,
      'High Contrast Dark': AuraTheme.highContrastThemeFor(Brightness.dark),
      'High Contrast Light': AuraTheme.highContrastThemeFor(Brightness.light),
      'Dynamic Aura (Dark Crimson)': AuraTheme.customTheme(
        const Color(0xFFB71C1C),
        brightness: Brightness.dark,
      ),
      'Dynamic Aura (Light Solar)': AuraTheme.customTheme(
        const Color(0xFFFFB300),
        brightness: Brightness.light,
      ),
      'Dynamic Aura (AMOLED Emerald)': AuraTheme.customTheme(
        const Color(0xFF00E676),
        brightness: Brightness.dark,
        isAmoled: true,
      ),
      'Dynamic Aura (Dark Deep Navy)': AuraTheme.customTheme(
        const Color(0xFF0D1B4C),
        brightness: Brightness.dark,
      ),
      'Dynamic Aura (Light Pastel Cyan)': AuraTheme.customTheme(
        const Color(0xFF80DEEA),
        brightness: Brightness.light,
      ),
    };

    for (final entry in modes.entries) {
      test(
          '${entry.key}: registered in ThemeData and satisfies >= 4.5:1 contrast',
          () {
        final theme = entry.value;
        final palette = theme.extension<PulsrPalette>();
        final surface = theme.extension<PlayerSurfacePalette>();

        expect(palette, isNotNull, reason: '${entry.key} missing PulsrPalette');
        expect(surface, isNotNull,
            reason: '${entry.key} missing PlayerSurfacePalette');

        final p = palette!;
        final s = surface!;

        // High-contrast ink on all physical hardware surfaces.
        expect(
          _contrastRatio(s.highContrastInk, s.cassetteShell),
          greaterThanOrEqualTo(4.5),
          reason: '${entry.key}: highContrastInk on cassetteShell < 4.5:1',
        );
        expect(
          _contrastRatio(s.highContrastInk, s.tapeWindow),
          greaterThanOrEqualTo(4.5),
          reason: '${entry.key}: highContrastInk on tapeWindow < 4.5:1',
        );
        expect(
          _contrastRatio(s.highContrastInk, s.vinylGroove),
          greaterThanOrEqualTo(4.5),
          reason: '${entry.key}: highContrastInk on vinylGroove < 4.5:1',
        );

        // Secondary hardware legend ink on cassetteShell & tapeWindow.
        expect(
          _contrastRatio(s.mutedInk, s.cassetteShell),
          greaterThanOrEqualTo(4.5),
          reason: '${entry.key}: mutedInk on cassetteShell < 4.5:1',
        );
        expect(
          _contrastRatio(s.mutedInk, s.tapeWindow),
          greaterThanOrEqualTo(4.5),
          reason: '${entry.key}: mutedInk on tapeWindow < 4.5:1',
        );

        // Optical / VFD LED glow on tapeWindow and cassetteShell.
        expect(
          _contrastRatio(s.ledGlow, s.tapeWindow),
          greaterThanOrEqualTo(4.5),
          reason: '${entry.key}: ledGlow on tapeWindow < 4.5:1',
        );
        expect(
          _contrastRatio(s.ledGlow, s.cassetteShell),
          greaterThanOrEqualTo(4.5),
          reason: '${entry.key}: ledGlow on cassetteShell < 4.5:1',
        );

        // Chrome text legibility over scrimEnd even against worst-case bright/dark
        // opposite-polarity shader backdrop.
        final adversarialBackdrop = p.isDark ? Colors.white : Colors.black;
        final scrimComposite =
            Color.alphaBlend(s.scrimEnd, adversarialBackdrop);
        expect(
          _contrastRatio(p.textPrimary, scrimComposite),
          greaterThanOrEqualTo(4.5),
          reason:
              '${entry.key}: textPrimary over scrimEnd + adversarial backdrop < 4.5:1',
        );
      });
    }

    test('copyWith, lerp, equality and hashCode behave consistently', () {
      final dark = AuraTheme.darkTheme.extension<PlayerSurfacePalette>()!;
      final light = AuraTheme.lightTheme.extension<PlayerSurfacePalette>()!;

      final modified = dark.copyWith(ledGlow: const Color(0xFF00FFAA));
      expect(modified.ledGlow, const Color(0xFF00FFAA));
      expect(modified.platterMetal, dark.platterMetal);
      expect(modified, isNot(equals(dark)));

      final same = dark.copyWith();
      expect(same, equals(dark));
      expect(same.hashCode, equals(dark.hashCode));

      final mid = dark.lerp(light, 0.5);
      expect(mid.scrimStart, Color.lerp(dark.scrimStart, light.scrimStart, 0.5));
      expect(mid.scrimEnd, Color.lerp(dark.scrimEnd, light.scrimEnd, 0.5));
      expect(dark.lerp(null, 0.5), equals(dark));
    });

    testWidgets(
        'context.playerSurfacePalette and AuraTheme.surfacePaletteOf resolve and fall back safely',
        (tester) async {
      late PlayerSurfacePalette darkFromContext;
      late PlayerSurfacePalette darkFromStatic;
      late PlayerSurfacePalette fallbackFromBareTheme;

      await tester.pumpWidget(
        MaterialApp(
          theme: AuraTheme.darkTheme,
          home: Builder(
            builder: (context) {
              darkFromContext = context.playerSurfacePalette;
              darkFromStatic = AuraTheme.surfacePaletteOf(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(darkFromContext, equals(darkFromStatic));
      expect(
        darkFromContext,
        equals(AuraTheme.darkTheme.extension<PlayerSurfacePalette>()),
      );

      // Bare ThemeData without extensions must fall back cleanly without throwing.
      await tester.pumpWidget(
        MaterialApp(
          key: const ValueKey('bare_light_theme'),
          theme: ThemeData.light(),
          home: Builder(
            builder: (context) {
              fallbackFromBareTheme = context.playerSurfacePalette;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(fallbackFromBareTheme, equals(AuraTheme.defaultSurfaceLight));

      late PlayerSurfacePalette fallbackFromBareDarkTheme;
      await tester.pumpWidget(
        MaterialApp(
          key: const ValueKey('bare_dark_theme'),
          theme: ThemeData.dark(),
          home: Builder(
            builder: (context) {
              fallbackFromBareDarkTheme = context.playerSurfacePalette;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(fallbackFromBareDarkTheme, equals(AuraTheme.defaultSurfaceDark));
    });
  });
}
