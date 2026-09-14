// Localization ratchet (defect 28-01): raw user-facing Text('...') literals
// bypass the complete ARB files (623/623/623). This lexical lower bound may
// only shrink: localize a surface and lower the baseline, never raise it.
// Baseline: 271 matches at tranche 7 (542 at tranche 6, ~665 before the
// EQ-sheet sweep; audio_quality_sheet 39 -> 9 this tranche).
// Excludes generated l10n. Proper nouns (crossfeed inventor names), channel
// symbols (L/R), unit interpolations ($bits-bit) and live-value templates
// (${state...}) are the known-acceptable remainder, tracked to zero next.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('raw Text literals do not increase (28-01 ratchet)', () {
    const baseline = 271;
    final pattern = RegExp(r"Text\(\s*'");
    var count = 0;
    final dir = Directory('lib');
    for (final f in dir.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      if (f.path.contains('l10n${Platform.pathSeparator}generated')) continue;
      count += pattern.allMatches(f.readAsStringSync()).length;
    }
    expect(count, lessThanOrEqualTo(baseline),
        reason: 'raw Text literals grew ($count > $baseline). Localize the '
            'new strings via ARB + context.l10n instead.');
  });
}
