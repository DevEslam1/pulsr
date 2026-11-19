import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Hit-target ratchet.
///
/// Material's compact density subtracts 8dp from the *tap target*, so an
/// `IconButton` under `VisualDensity.compact` renders 40x40 even when the call
/// site declares a 48dp constraint — the mini player shipped exactly that bug.
/// `MaterialTapTargetSize.shrinkWrap` is worse: it collapses the target to the
/// glyph, and paired with `Size.zero` it produces a ~13dp button.
///
/// This is a static ratchet (fast, no DI harness): it fails on the two
/// anti-patterns that caused the measured regressions. Widget-level target
/// sizes stay covered by `test/a11y/*`.
void main() {
  final roots = [Directory('lib')];

  Iterable<File> dartFiles() sync* {
    for (final root in roots) {
      if (!root.existsSync()) continue;
      for (final entity in root.listSync(recursive: true)) {
        if (entity is File &&
            entity.path.endsWith('.dart') &&
            !entity.path.endsWith('.g.dart') &&
            !entity.path.endsWith('.freezed.dart')) {
          yield entity;
        }
      }
    }
  }

  test('no IconButton uses VisualDensity.compact', () {
    final offenders = <String>[];
    for (final file in dartFiles()) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        if (!line.contains('visualDensity: VisualDensity.compact')) continue;
        final start = (i - 12).clamp(0, lines.length - 1);
        final window = lines.sublist(start, i).join('\n');
        if (window.contains('IconButton(')) {
          offenders.add('${file.path}:${i + 1}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'VisualDensity.compact shrinks an IconButton tap target to 40dp. '
          'Remove it (the theme sets standard density) or use a Pulsr primitive:'
          '\n${offenders.join('\n')}',
    );
  });

  test('no zero-size shrink-wrapped tap targets', () {
    final offenders = <String>[];
    for (final file in dartFiles()) {
      final content = file.readAsStringSync();
      if (!content.contains('minimumSize: Size.zero')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].contains('minimumSize: Size.zero')) continue;
        final start = (i - 6).clamp(0, lines.length - 1);
        final end = (i + 6).clamp(0, lines.length - 1);
        final window = lines.sublist(start, end).join('\n');
        if (window.contains('shrinkWrap')) {
          offenders.add('${file.path}:${i + 1}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'Size.zero + MaterialTapTargetSize.shrinkWrap makes a control '
          'unreachable. Use at least Size(48, 48):\n${offenders.join('\n')}',
    );
  });

  test('player chrome has no sub-48 circle buttons', () {
    final file =
        File('lib/features/player/presentation/themes/player_theme_chrome.dart');
    if (!file.existsSync()) return;
    final content = file.readAsStringSync();
    expect(content.contains('width: 46'), isFalse,
        reason: 'The Now Playing top-bar buttons must be 48dp.');
    expect(content.contains('width: 34'), isFalse,
        reason: 'The bookmark-prompt close target must be 48dp.');
  });
}
