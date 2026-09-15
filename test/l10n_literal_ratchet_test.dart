// Localization ratchet (defect 28-01): raw static user-facing Text('...')
// literals bypass the complete ARB files. Counts only literals with no `$`
// interpolation, since dynamic values (${count} tracks) legitimately require
// composition; those are covered by localized templates where they matter.
// Baseline: 32 at tranche 8 (271 raw Text( matches at tranche 7; the gap is
// interpolated/brand text). Only shrink this constant: localize a surface,
// then lower it. The known remainder is proper nouns (autoEQ preset names,
// codec names M3U/PLS/WPL, crossfeed inventors), channel symbols (L/R, A/B),
// and theme brand labels (PULSR TAPE, VINYL ...).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('static raw Text literals do not increase (28-01 ratchet)', () {
    const baseline = 32;
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
