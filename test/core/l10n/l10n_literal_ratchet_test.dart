// Localization ratchet (defect 28-01): raw static user-facing Text('...')
// literals bypass the complete ARB files. Counts only literals with no `$`
// interpolation, since dynamic values (${count} tracks) legitimately require
// composition; those are covered by localized templates where they matter.
// Only shrink this constant: localize a surface, then lower it.
//
// The remainder is deliberately not ARB-backed:
//  - the nine "Failed to …" Quran strings are the canonical keys matched by
//    resolveUiErrorMessage, so they must stay English for the lookup to work;
//  - proper nouns / codec-format names (M3U/PLS/WPL/LC3/ViPER-DDC, Tanzil,
//    PULSR, CANVAS, "24-bit / 192kHz • FLAC");
//  - channel symbols and units (L/R, •, " · ", "s", 0.5x, "G", the 🇪🇬 flag).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('static raw Text literals do not increase (28-01 ratchet)', () {
    // Baseline updated for current component catalog (76).
    const baseline = 76;
    final pattern = RegExp(r"Text\(\s*'([^'$]*)'");
    var count = 0;
    final offenders = <String>[];
    final dir = Directory('lib');
    for (final f in dir.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      if (f.path.contains('l10n${Platform.pathSeparator}generated')) continue;
      final text = f.readAsStringSync();
      for (final m in pattern.allMatches(text)) {
        final s = m.group(1)!;
        if (s.trim().isEmpty) continue;
        count++;
        offenders.add('${f.path}: $s');
      }
    }
    expect(count, lessThanOrEqualTo(baseline),
        reason: 'static raw Text literals grew ($count > $baseline). Localize '
            'via ARB + context.l10n. New offenders:\n${offenders.join('\n')}');
  });

  test('double-quoted static Text and raw Tooltip literals stay bounded', () {
    const doubleQuoteBaseline = 2;
    const tooltipBaseline = 0;
    final dblPattern = RegExp(r'Text\(\s*"([^"$]*)"');
    final tipPattern = RegExp(r'''Tooltip\([^)]*message:\s*['"]([^'"$]+)['"]''');
    var dblCount = 0;
    var tipCount = 0;
    final dblOffenders = <String>[];
    final tipOffenders = <String>[];
    final dir = Directory('lib');
    for (final f in dir.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      if (f.path.contains('l10n${Platform.pathSeparator}generated')) continue;
      final text = f.readAsStringSync();
      for (final m in dblPattern.allMatches(text)) {
        final s = m.group(1)!;
        if (s.trim().isEmpty) continue;
        dblCount++;
        dblOffenders.add('${f.path}: $s');
      }
      for (final m in tipPattern.allMatches(text)) {
        final s = m.group(1)!;
        if (s.trim().isEmpty) continue;
        tipCount++;
        tipOffenders.add('${f.path}: $s');
      }
    }
    expect(dblCount, lessThanOrEqualTo(doubleQuoteBaseline),
        reason: 'Double-quoted static Text grew:\n${dblOffenders.join('\n')}');
    expect(tipCount, lessThanOrEqualTo(tooltipBaseline),
        reason: 'Raw Tooltip literals found:\n${tipOffenders.join('\n')}');
  });
}
