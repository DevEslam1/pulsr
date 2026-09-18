// RTL ratchet (defect 28-02): hardcoded `left:`/`right:` positioning does not
// mirror for Arabic, so controls can appear reversed. All known sites were
// migrated to PositionedDirectional / EdgeInsetsDirectional; this test keeps
// the count at zero so no NEW non-directional site can be introduced.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('non-directional positioning stays at zero (28-02 ratchet)', () {
    const baseline = 0;
    final positioned =
        RegExp(r'Positioned\s*\(\s*[^)]*\b(left|right)\s*:');
    final insets =
        RegExp(r'EdgeInsets\.only\s*\([^)]*\b(left|right)\s*:');
    final fromLtrb = RegExp(r'EdgeInsets\.fromLTRB\s*\(');
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
      for (final m in positioned
          .allMatches(text)
          .followedBy(insets.allMatches(text))
          .followedBy(fromLtrb.allMatches(text))) {
        count++;
        final line = '\n'.allMatches(text.substring(0, m.start)).length + 1;
        offenders.add('${f.path}:$line');
      }
    }
    expect(count, lessThanOrEqualTo(baseline),
        reason: 'non-directional positioning found ($count > $baseline). Use '
            'PositionedDirectional / EdgeInsetsDirectional / '
            'AlignmentDirectional so Arabic mirrors correctly. Offenders:\n'
            '${offenders.join('\n')}');
  });
}
