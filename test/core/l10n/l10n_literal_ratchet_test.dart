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
    // Baseline lowered from 63 after the full-app l10n sweep (Discord, updater,
    // radio cards, wizard, room correction, quality sheet, Quran errors).
    const baseline = 34;
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
}
