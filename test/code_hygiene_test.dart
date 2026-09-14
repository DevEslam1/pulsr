// Code-hygiene guards for defect classes that are cheap to reintroduce and
// expensive to notice. These tests scan lib/ directly, so they fail the moment
// the pattern comes back rather than when a user reports the symptom.
//
// Introduced by remediation tranche 1 (defects 08-04 and 01-01).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('code hygiene guards', () {
    // Baseline counted at commit 09ce0cb plus remediation tranches 1-2. Lower
    // this constant as empty catch bodies are fixed; never raise it.
    const int emptyCatchBaseline = 439;

    List<File> dartFilesUnderLib() {
      final dir = Directory('lib');
      if (!dir.existsSync()) {
        fail('lib/ not found from ${Directory.current.path} - run from the '
            'repository root');
      }
      return dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
    }

    test('lib/ contains no raw print() calls (defect 08-04)', () {
      final printCall = RegExp(r'\bprint\s*\(');
      final offenders = <String>[];

      for (final file in dartFilesUnderLib()) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          final trimmed = line.trimLeft();
          if (trimmed.startsWith('//')) continue;
          if (printCall.hasMatch(line)) {
            offenders.add('${file.path}:${i + 1}: ${line.trim()}');
          }
        }
      }

      expect(offenders, isEmpty,
          reason: 'raw print() writes to the release console and bypasses '
              'ErrorLogger/Sentry. Use ErrorLogger.log instead. Found:\n'
              '${offenders.join('\n')}');
    });

    test('empty catch bodies do not increase (defect 01-01 ratchet)', () {
      // `catch (...) {}` swallows a failure with no user signal and no
      // telemetry. The ratchet allows the existing baseline and forces the
      // number down over time, instead of blocking the whole remediation.
      final emptyCatch = RegExp(r'catch\s*\([^)]*\)\s*\{\s*\}');

      var count = 0;
      for (final file in dartFilesUnderLib()) {
        count += emptyCatch.allMatches(file.readAsStringSync()).length;
      }

      expect(count, lessThanOrEqualTo(emptyCatchBaseline),
          reason: 'empty catch bodies swallow failures silently. Baseline is '
              '$emptyCatchBaseline; fix existing ones and lower the constant, '
              'but never add new ones. Actual: $count');
    });
  });
}
