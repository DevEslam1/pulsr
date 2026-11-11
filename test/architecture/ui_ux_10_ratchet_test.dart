// test/architecture/ui_ux_10_ratchet_test.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/app_blur.dart';
import 'package:pulsr/core/performance/gpu_budget.dart';

void main() {
  List<File> dartFilesUnderLib() {
    return Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) {
      final p = f.path.replaceAll('\\', '/');
      if (p.contains('l10n/generated/')) return false;
      if (p.endsWith('.freezed.dart') ||
          p.endsWith('.g.dart') ||
          p.endsWith('.config.dart')) {
        return false;
      }
      if (p.endsWith('embedded_browser_ua.dart')) return false;
      return true;
    }).toList();
  }

  group('UI/UX 10/10 Architecture & Token Ratchets', () {
    test(
        'zero raw Color(0x...) literals outside AppColors, AuraTheme, and PlayerMaterialColors',
        () {
      const allowedFiles = {
        'app_colors.dart',
        'aura_theme.dart',
        'player_material_colors.dart',
      };
      final hexColor = RegExp(r'Color\(0x[0-9A-Fa-f]+\)');
      final offenders = <String>[];

      for (final file in dartFilesUnderLib()) {
        final name = file.uri.pathSegments.last;
        if (allowedFiles.contains(name)) continue;
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('//')) continue;
          if (hexColor.hasMatch(line)) {
            offenders.add('${file.path}:${i + 1}: ${line.trim()}');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'Raw Color(0x...) literals bypass theme tokens and break '
            'Aura / High-Contrast parity. Define tokens in AppColors, '
            'PulsrPalette, or PlayerMaterialColors:\n${offenders.join('\n')}',
      );
    });

    test('every file using ImageFilter.blur routes through AppBlur', () {
      final blurCall = RegExp(r'ImageFilter\.blur\(');
      final offenders = <String>[];

      for (final file in dartFilesUnderLib()) {
        final content = file.readAsStringSync();
        if (blurCall.hasMatch(content) && !content.contains('AppBlur')) {
          offenders.add(file.path);
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'All ImageFilter.blur call sites must use AppBlur tokens and '
            'AppBlur.canBlur(context) gating:\n${offenders.join('\n')}',
      );
    });

    test('all GoRoutes in app_router.dart use pageBuilder (CustomTransitionPage)',
        () {
      final routerFile = File('lib/core/router/app_router.dart');
      expect(routerFile.existsSync(), isTrue);
      final lines = routerFile.readAsLinesSync();
      final offenders = <String>[];
      final rawBuilder = RegExp(r'^\s*builder:\s*\(context,\s*state\)\s*=>');

      for (var i = 0; i < lines.length; i++) {
        if (rawBuilder.hasMatch(lines[i])) {
          offenders.add('app_router.dart:${i + 1}: ${lines[i].trim()}');
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'Every GoRoute must use pageBuilder with PulsrMotion '
            'transitions instead of default MaterialPage builder:\n'
            '${offenders.join('\n')}',
      );
    });

    test('CircularProgressIndicator count does not exceed ratchet ceiling (65)',
        () {
      const ceiling = 65;
      final pattern = RegExp(r'CircularProgressIndicator\(');
      var count = 0;
      for (final file in dartFilesUnderLib()) {
        count += pattern.allMatches(file.readAsStringSync()).length;
      }
      expect(
        count,
        lessThanOrEqualTo(ceiling),
        reason: 'Use PulsrProgressBar or ShimmerSkeleton instead of adding '
            'raw CircularProgressIndicators. Ceiling: $ceiling, actual: $count',
      );
    });

    testWidgets(
        'AppBlur.canBlur honours GpuBudget and MediaQuery.highContrast',
        (tester) async {
      GpuBudget.setEnabled(false);
      addTearDown(() => GpuBudget.setEnabled(false));

      late bool canBlurNormal;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(highContrast: false),
            child: Builder(
              builder: (context) {
                canBlurNormal = AppBlur.canBlur(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      expect(canBlurNormal, isTrue);

      // High contrast disables blur for legibility
      late bool canBlurHighContrast;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(highContrast: true),
            child: Builder(
              builder: (context) {
                canBlurHighContrast = AppBlur.canBlur(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      expect(canBlurHighContrast, isFalse);

      // GPU saver disables blur
      GpuBudget.setEnabled(true);
      late bool canBlurGpuSaver;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(highContrast: false),
            child: Builder(
              builder: (context) {
                canBlurGpuSaver = AppBlur.canBlur(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      expect(canBlurGpuSaver, isFalse);
      expect(AppBlur.clampSigma(24.0), equals(AppBlur.maxSigma));
      expect(AppBlur.clampSigma(-2.0), equals(0.0));
    });
  });
}
