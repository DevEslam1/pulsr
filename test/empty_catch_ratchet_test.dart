// Empty-catch ratchet (defect 01-01): a bare `catch {}` makes a failure
// invisible to both the user and crash reporting. A full migration of the
// existing sites is a project in itself, so this freezes the count: new empty
// catches fail the build, and fixing one lets you lower the baseline.
//
// Scope: real Dart sources only. `third_party/` vendored code and the embedded
// browser JS payload (a string literal full of `catch(e){}`) are excluded so the
// number tracks the app's own error handling.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('empty catch blocks do not increase (01-01 ratchet)', () {
    const baseline = 398; // measured 2026-02; only ever lower this.
    final pattern = RegExp(r'catch\s*\([^)]*\)\s*\{\s*\}');
    var count = 0;
    final offenders = <String>[];
    final dir = Directory('lib');
    for (final f in dir.listSync(recursive: true).whereType<File>()) {
      final path = f.path.replaceAll('\\', '/');
      if (!path.endsWith('.dart')) continue;
      if (path.contains('third_party/')) continue;
      if (path.contains('l10n/generated/')) continue;
      if (path.endsWith('.freezed.dart') || path.endsWith('.g.dart')) continue;
      if (path.endsWith('embedded_browser_ua.dart')) continue;
      final text = f.readAsStringSync();
      for (final m in pattern.allMatches(text)) {
        count++;
        final line = '\n'.allMatches(text.substring(0, m.start)).length + 1;
        offenders.add('$path:$line');
      }
    }
    expect(count, lessThanOrEqualTo(baseline),
        reason: 'empty catch blocks grew ($count > $baseline). Replace the bare '
            'catch with at least `ErrorLogger.log(...)` so the failure is '
            'visible. Offenders:\n${offenders.join('\n')}');
  });
}
