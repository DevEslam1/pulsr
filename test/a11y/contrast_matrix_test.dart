import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';

/// WCAG 2.1 relative-luminance contrast ratio.
double _ratio(Color fg, Color bg) {
  final a = fg.computeLuminance();
  final b = bg.computeLuminance();
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
}

/// A palette plus the label used in failure messages.
class _Case {
  const _Case(this.name, this.palette);
  final String name;
  final PulsrPalette palette;
}

void main() {
  final cases = <_Case>[
    _Case('light', AuraTheme.lightTheme.extension<PulsrPalette>()!),
    _Case('dark', AuraTheme.darkTheme.extension<PulsrPalette>()!),
    _Case('amoled', AuraTheme.amoledTheme.extension<PulsrPalette>()!),
    _Case(
      'high-contrast-dark',
      AuraTheme.highContrastThemeFor(Brightness.dark)
          .extension<PulsrPalette>()!,
    ),
    _Case(
      'high-contrast-light',
      AuraTheme.highContrastThemeFor(Brightness.light)
          .extension<PulsrPalette>()!,
    ),
  ];

  // Every theme must keep body copy readable on all three surfaces it can be
  // painted on. This is the contract that stops a hardcoded `Colors.white`
  // foreground from silently shipping into light mode.
  group('text contrast (WCAG AA 4.5:1)', () {
    for (final c in cases) {
      final p = c.palette;
      final fgs = {
        'textPrimary': p.textPrimary,
        'textSecondary': p.textSecondary,
        'textTertiary': p.textTertiary,
      };
      final bgs = {
        'bg': p.bg,
        'surface': p.surface,
        'surfaceContainer': p.surfaceContainer,
      };
      fgs.forEach((fgName, fg) {
        bgs.forEach((bgName, bg) {
          test('${c.name}: $fgName on $bgName', () {
            final r = _ratio(fg, bg);
            expect(
              r,
              greaterThanOrEqualTo(4.5),
              reason: '${c.name}: $fgName on $bgName is '
                  '${r.toStringAsFixed(2)}:1 (need >= 4.5:1)',
            );
          });
        });
      });
    }
  });

  group('accent contrast', () {
    for (final c in cases) {
      final p = c.palette;
      // Accent painted flat on a page surface.
      test('${c.name}: accent on surface', () {
        final r = _ratio(p.accent, p.surface);
        expect(r, greaterThanOrEqualTo(4.5),
            reason: '${c.name}: accent on surface is '
                '${r.toStringAsFixed(2)}:1 (need >= 4.5:1)');
      });

      // Accent text sitting inside an accent-tinted container.
      test('${c.name}: accent on accentContainer', () {
        final flat = Color.alphaBlend(p.accentContainer, p.surface);
        final r = _ratio(p.accent, flat);
        expect(r, greaterThanOrEqualTo(4.5),
            reason: '${c.name}: accent on accentContainer is '
                '${r.toStringAsFixed(2)}:1 (need >= 4.5:1)');
      });

      test('${c.name}: onAccent on accent', () {
        final r = _ratio(p.onAccent, p.accent);
        expect(r, greaterThanOrEqualTo(4.5),
            reason: '${c.name}: onAccent on accent is '
                '${r.toStringAsFixed(2)}:1 (need >= 4.5:1)');
      });

      // Hi-Res / USB-DAC tier marker must stay readable in both modes.
      test('${c.name}: goldAccent on surface', () {
        final r = _ratio(p.goldAccent, p.surface);
        expect(r, greaterThanOrEqualTo(4.5),
            reason: '${c.name}: goldAccent on surface is '
                '${r.toStringAsFixed(2)}:1 (need >= 4.5:1)');
      });
    }
  });

  // High-contrast mode exists to be *more* legible than the default theme.
  // Regression: its light variant previously shipped at 4.15:1 on bg.
  group('high-contrast accent is genuinely high contrast (AAA 7:1)', () {
    for (final name in ['high-contrast-light', 'high-contrast-dark']) {
      final p = cases.firstWhere((c) => c.name == name).palette;
      test('$name: accent on bg', () {
        final r = _ratio(p.accent, p.bg);
        expect(r, greaterThanOrEqualTo(7.0),
            reason: '$name: accent on bg is ${r.toStringAsFixed(2)}:1 '
                '(need >= 7:1)');
      });
      test('$name: accent on surface', () {
        final r = _ratio(p.accent, p.surface);
        expect(r, greaterThanOrEqualTo(7.0),
            reason: '$name: accent on surface is ${r.toStringAsFixed(2)}:1 '
                '(need >= 7:1)');
      });
    }
  });

  test('light palette uses dark text, dark palette uses light text', () {
    final light = AuraTheme.lightTheme.extension<PulsrPalette>()!;
    final dark = AuraTheme.darkTheme.extension<PulsrPalette>()!;
    expect(light.textPrimary.computeLuminance(), lessThan(0.2),
        reason: 'light mode text must be dark');
    expect(dark.textPrimary.computeLuminance(), greaterThan(0.5),
        reason: 'dark mode text must be light');
    expect(light.isDark, isFalse);
    expect(dark.isDark, isTrue);
  });
}
