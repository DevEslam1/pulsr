import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Motion ratchet: presentation code must resolve durations through
/// `context.motion(...)` / `context.motionMs(...)`, never by handing a bare
/// `PulsrMotion.*` const or raw `Duration(...)` literal to an animated widget.
///
/// A bare const never collapses under Reduce Motion (`PulsrMotion.resolve` is
/// what does that), so passing one silently re-enables animation for users who
/// asked for none.
void main() {
  final dirs = [
    Directory('lib/features'),
    Directory('lib/core/widgets'),
  ];

  test('no bare PulsrMotion durations in animated widgets', () {
    final offenders = <String>[];
    final pattern = RegExp(
      r'duration:\s*(?:const\s+)?(?:PulsrMotion|AppMotion)\.\w+',
    );

    for (final dir in dirs) {
      if (!dir.existsSync()) continue;
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
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

  test('no unwrapped Duration literals in Animated* widgets or animateToPage',
      () {
    final offenders = <String>[];
    final durPattern = RegExp(r'duration:\s*(?:const\s+)?Duration\(');
    final widgetPattern = RegExp(
      r'Animated(Container|Opacity|Size|Switcher|Scale|Padding|Positioned|Align|DefaultTextStyle|CrossFade)|TweenAnimationBuilder|animateToPage',
    );

    for (final dir in dirs) {
      if (!dir.existsSync()) continue;
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.path.endsWith('.g.dart') ||
            entity.path.endsWith('.freezed.dart')) {
          continue;
        }
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('//')) continue;
          if (durPattern.hasMatch(line) && !line.contains('context.motion')) {
            final start = (i - 3).clamp(0, lines.length - 1);
            final window = lines.sublist(start, i + 1).join(' ');
            if (widgetPattern.hasMatch(window)) {
              offenders.add('${entity.path}:${i + 1}: ${line.trim()}');
            }
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Every Animated* widget must resolve its duration through '
          'context.motion(...) so Reduce Motion collapses it to zero:\n'
          '${offenders.join('\n')}',
    );
  });

  test('every repeating animation (.repeat) checks motionEnabled', () {
    final offenders = <String>[];
    final repeatPattern = RegExp(r'\.repeat\(');

    for (final dir in dirs) {
      if (!dir.existsSync()) continue;
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final content = entity.readAsStringSync();
        if (repeatPattern.hasMatch(content) &&
            !content.contains('motionEnabled')) {
          offenders.add(entity.path);
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Files calling AnimationController.repeat() must gate on '
          'context.motionEnabled:\n${offenders.join('\n')}',
    );
  });
}
