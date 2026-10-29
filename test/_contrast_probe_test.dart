// TEMPORARY contrast probe.
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/theme/aura_theme.dart';

double cr(Color fg, Color bg) {
  final a = fg.computeLuminance();
  final b = bg.computeLuminance();
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
}

void report(String name, PulsrPalette p) {
  final pairs = <String, List<Color>>{
    'textPrimary/bg': [p.textPrimary, p.bg],
    'textPrimary/surface': [p.textPrimary, p.surface],
    'textPrimary/surfaceContainer': [p.textPrimary, p.surfaceContainer],
    'textSecondary/bg': [p.textSecondary, p.bg],
    'textSecondary/surface': [p.textSecondary, p.surface],
    'textTertiary/surface': [p.textTertiary, p.surface],
    'textTertiary/bg': [p.textTertiary, p.bg],
    'accent/bg': [p.accent, p.bg],
    'accent/surface': [p.accent, p.surface],
    'onAccent/accent': [p.onAccent, p.accent],
    'accent/accentContainer': [p.accent, Color.alphaBlend(p.accentContainer, p.surface)],
    'success/surface': [p.success, p.surface],
    'error/surface': [p.error, p.surface],
    'warning/surface': [p.warning, p.surface],
  };
  print('=== $name ===');
  pairs.forEach((k, v) {
    final r = cr(v[0], v[1]);
    final flag = r >= 4.5 ? 'AA' : (r >= 3.0 ? 'AA-large' : 'FAIL');
    print('${k.padRight(32)} ${r.toStringAsFixed(2).padLeft(6)}  $flag');
  });
}

void main() {
  test('contrast probe', () {
    report('LIGHT', AuraTheme.lightTheme.extension<PulsrPalette>()!);
    report('DARK', AuraTheme.darkTheme.extension<PulsrPalette>()!);
    report('AMOLED', AuraTheme.amoledTheme.extension<PulsrPalette>()!);
    report('HIGH-CONTRAST DARK', AuraTheme.highContrastTheme.extension<PulsrPalette>()!);
    report('HIGH-CONTRAST LIGHT', AuraTheme.highContrastThemeFor(Brightness.light).extension<PulsrPalette>()!);
    print('dacGold on light surface: ${cr(AppColors.dacGold, Colors.white).toStringAsFixed(2)}');
  });
}
