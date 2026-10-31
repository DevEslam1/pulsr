import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Motion ratchet: presentation code must resolve durations through
/// `context.motion(...)` / `context.motionMs(...)`, never by handing a bare
/// `PulsrMotion.*` const to an animated widget.
///
/// A bare const never collapses under Reduce Motion (`PulsrMotion.resolve` is
/// what does that), so passing one silently re-enables animation for users who
/// asked for none.
void main() {
  test('no bare PulsrMotion durations in animated widgets', () {
    final offenders = <String>[];
    final dirs = [
      Directory('lib/features'),
      Directory('lib/core/widgets'),
    ];

    final pattern = RegExp(
      r'duration:\s*(?:const\s+)?(?:PulsrMotion|AppMotion)\.\w+',
    );

    for (final dir in dirs) {
      if (!dir.existsSync()) continue;
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        // The token definitions themselves are allowed to reference the consts.
        if (entity.path.endsWith('pulsr_motion.dart')) continue;
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('//')) continue;
          if (pattern.hasMatch(line) && !line.contains('context.motion')) {
            offenders.add('${entity.path}:${i + 1}: ${line.trim()}');
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Wrap bare motion consts in context.motion(...) so Reduce Motion '
          'is honoured:\n${offenders.join('\n')}',
    );
  });
}
