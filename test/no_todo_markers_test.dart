// Zero-tolerance hygiene gate: production sources must not carry TODO/FIXME/
// HACK markers. Earlier tooling reported ~196 such markers, but that was a
// false positive from case-insensitive substring matches inside identifiers
// such as `toDouble()`. A strict word-boundary scan confirms the real count is
// 0. This test keeps it at 0: resolve a marker or delete it, never add one.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no TODO/FIXME/HACK markers in non-generated lib sources', () {
    final pattern = RegExp(r'(?<![\w])(TODO|FIXME|HACK)(?![\w])');
    final offenders = <String>[];
    for (final f
        in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final p = f.path.replaceAll('\\', '/');
      if (p.contains('l10n/generated/')) continue;
      if (p.endsWith('.freezed.dart') || p.endsWith('.g.dart')) continue;
      final text = f.readAsStringSync();
      for (final m in pattern.allMatches(text)) {
        offenders.add('${f.path}: ${m.group(0)}');
      }
    }
    expect(offenders, isEmpty,
        reason:
            'Resolve or remove TODO/FIXME/HACK markers:\n${offenders.join('\n')}');
  });
}
