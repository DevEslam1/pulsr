import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Phase 5 (B-63): The 'Audio Output & DAC' tooltip must appear exactly once
/// per player theme file — guards against duplicated tooltip blocks being
/// pasted into the same widget tree.
void main() {
  const themeFiles = [
    'lib/features/player/presentation/themes/card_player_theme.dart',
    'lib/features/player/presentation/themes/circle_player_theme.dart',
    'lib/features/player/presentation/themes/classic_player_theme.dart',
    'lib/features/player/presentation/themes/minimal_player_theme.dart',
  ];

  // Robust to formatting: allows arbitrary spacing around ':' and either
  // single- or double-quoted string literals.
  final tooltipPattern =
      RegExp(r'''tooltip\s*:\s*['"]Audio Output & DAC['"]''');

  group('Phase 5 Tooltip Dedup (B-63)', () {
    for (final path in themeFiles) {
      test("'$path' declares the 'Audio Output & DAC' tooltip exactly once",
          () async {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: 'Missing theme file: $path');
        final source = await file.readAsString();
        final matches = tooltipPattern.allMatches(source).toList();
        expect(
          matches.length,
          equals(1),
          reason:
              "Expected exactly one 'Audio Output & DAC' tooltip in $path "
              'but found ${matches.length} (duplicated tooltip block?)',
        );
      });
    }
  });
}
