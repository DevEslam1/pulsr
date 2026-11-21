// test/core/theme/no_raw_color_literals_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Shrink-only baseline allowlist for pre-existing `Color.fromARGB` /
/// `Color.fromRGBO` literals outside `lib/core/theme/` and `lib/core/constants/`.
///
/// Entries may only decrease or be removed as Wave 2 / Wave 3 cleans remaining
/// files; adding new files or increasing any count fails the test immediately.
const Map<String, int> _rawFromColorAllowlist = {
  'lib/features/player/presentation/widgets/visualizer/milkdrop_renderer.dart':
      1,
};

/// Shrink-only baseline allowlist for pre-existing raw `Color(0x...)` literals
/// outside `lib/core/theme/` and `lib/core/constants/`.
///
/// Currently empty (zero debt). Any new raw hex `Color(0x...)` literal anywhere
/// in feature code will immediately fail this guard.
const Map<String, int> _rawHexColorAllowlist = {};

/// Wave 1A cleaned files that must also contain zero `Colors.*` literals.
const List<String> _wave1ACleanedNoColorsFiles = [
  'lib/features/player/presentation/themes/milkdrop_player_theme.dart',
  'lib/features/player/presentation/themes/painters/cassette_body.dart',
  'lib/features/player/presentation/themes/painters/cd_painters.dart',
  'lib/features/player/presentation/themes/painters/cd_stage.dart',
  'lib/features/player/presentation/themes/painters/circle_stage.dart',
  'lib/features/player/presentation/themes/painters/platter_scrub.dart',
  'lib/features/player/presentation/themes/painters/vinyl_deck.dart',
  'lib/features/player/presentation/themes/painters/vinyl_painters.dart',
  'lib/features/player/presentation/themes/painters/waveform_stage.dart',
];

final RegExp _rawHexColorPattern = RegExp(r'\bColor\s*\(\s*0x[0-9A-Fa-f]+\s*\)');
final RegExp _rawFromColorPattern = RegExp(r'\bColor\.from(?:ARGB|RGBO)\s*\(');
final RegExp _materialColorsPattern = RegExp(r'\bColors\.[A-Za-z0-9_]+');

String _stripLineComment(String line) {
  final trimmed = line.trimLeft();
  if (trimmed.startsWith('//')) return '';
  final commentIdx = line.indexOf('//');
  if (commentIdx < 0) return line;
  // Ignore `//` inside string literals (e.g. `https://`).
  final prefix = line.substring(0, commentIdx);
  if (prefix.contains('http:') || prefix.contains('https:')) return line;
  return prefix;
}

int _countMatches(File file, RegExp pattern) {
  int total = 0;
  for (final line in file.readAsLinesSync()) {
    final code = _stripLineComment(line);
    if (code.isEmpty) continue;
    total += pattern.allMatches(code).length;
  }
  return total;
}

String _normalizePath(String path) => path.replaceAll('\\', '/');

bool _isExemptDesignTokenPath(String relPath) {
  return relPath.startsWith('lib/core/theme/') ||
      relPath.startsWith('lib/core/constants/');
}

void main() {
  group('Design token guard: no raw color literals outside theme/constants',
      () {
    test('no raw Color(0x...) literals outside lib/core/theme and constants',
        () {
      final libDir = Directory('lib');
      expect(libDir.existsSync(), isTrue,
          reason: 'Expected test to run from repository root containing lib/');

      final violations = <String>[];
      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final relPath = _normalizePath(entity.path);
        if (_isExemptDesignTokenPath(relPath)) continue;

        final count = _countMatches(entity, _rawHexColorPattern);
        final allowed = _rawHexColorAllowlist[relPath] ?? 0;
        if (count > allowed) {
          violations.add(
            '$relPath: found $count raw Color(0x...) literal(s) (allowed: $allowed)',
          );
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'Use AuraTheme / PlayerSurfacePalette / AppColors tokens instead of raw Color(0x...) literals:\n'
            '${violations.join('\n')}',
      );
    });

    test(
        'no new Color.fromARGB / Color.fromRGBO literals beyond shrink-only baseline',
        () {
      final libDir = Directory('lib');
      final violations = <String>[];

      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final relPath = _normalizePath(entity.path);
        if (_isExemptDesignTokenPath(relPath)) continue;

        final count = _countMatches(entity, _rawFromColorPattern);
        final allowed = _rawFromColorAllowlist[relPath] ?? 0;
        if (count > allowed) {
          violations.add(
            '$relPath: found $count Color.fromARGB/RGBO literal(s) (allowed: $allowed)',
          );
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'Do not introduce new Color.fromARGB/Color.fromRGBO calls outside theme/constants:\n'
            '${violations.join('\n')}',
      );
    });

    test('Wave 1A player painters and Milkdrop theme have zero Colors.* literals',
        () {
      final violations = <String>[];
      for (final relPath in _wave1ACleanedNoColorsFiles) {
        final file = File(relPath);
        expect(file.existsSync(), isTrue, reason: 'Missing file: $relPath');
        final count = _countMatches(file, _materialColorsPattern);
        if (count > 0) {
          violations.add('$relPath: found $count raw Colors.* literal(s)');
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'Wave 1A cleaned files must resolve colors from PlayerSurfacePalette / AuraTheme:\n'
            '${violations.join('\n')}',
      );
    });
  });
}
