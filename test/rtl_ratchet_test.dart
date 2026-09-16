// RTL ratchet (defect 28-02): hardcoded `left:`/`right:` positioning does not
// mirror for Arabic, so controls can appear reversed. A full migration is a
// project in itself; this test freezes the count so no NEW non-directional
// site can be introduced. Fix a site (PositionedDirectional /
// EdgeInsetsDirectional / AlignmentDirectional), then lower the baseline.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('non-directional positioning does not increase (28-02 ratchet)', () {
    const baseline = 70;
    final positioned =
        RegExp(r'Positioned\s*\(\s*[^)]*\b(left|right)\s*:');
    final insets =
        RegExp(r'EdgeInsets\.only\s*\([^)]*\b(left|right)\s*:');
    var count = 0;
    final offenders = <String>[];
    final dir = Directory('lib');
    for (final f in dir.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      if (f.path.contains('l10n${Platform.pathSeparator}generated')) continue;
      if (f.path.endsWith('.freezed.dart') || f.path.endsWith('.g.dart')) {
        continue;
      }
      final text = f.readAsStringSync();
      for (final m in positioned.allMatches(text).followedBy(insets.allMatches(text))) {
        count++;
        final line = '\n'.allMatches(text.substring(0, m.start)).length + 1;
        offenders.add('${f.path}:$line');
      }
    }
    expect(count, lessThanOrEqualTo(baseline),
        reason: 'non-directional positioning grew ($count > $baseline). Use '
            'PositionedDirectional / EdgeInsetsDirectional / '
            'AlignmentDirectional so Arabic mirrors correctly. New offenders:\n'
            '${offenders.join('\n')}');
  });
}
