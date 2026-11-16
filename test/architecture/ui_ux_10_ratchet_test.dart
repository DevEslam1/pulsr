// test/architecture/ui_ux_10_ratchet_test.dart
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/app_blur.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/performance/gpu_budget.dart';
import 'package:pulsr/core/theme/aura_theme.dart';

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

    test(
        'all GoRoutes in app_router.dart use pageBuilder (CustomTransitionPage)',
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

    testWidgets('AppBlur.canBlur honours GpuBudget and MediaQuery.highContrast',
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

    test(
        'zero foregroundColor: Colors.white in lib/ (use p.onAccent / AppColors.textOnAccent)',
        () {
      final violations = <String>[];
      final pat = RegExp(r'foregroundColor\s*:\s*Colors\.white\b');
      for (final f in dartFilesUnderLib()) {
        final lines = f.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          if (pat.hasMatch(lines[i])) {
            violations.add('${f.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
      expect(
        violations,
        isEmpty,
        reason:
            'Button foregroundColor must never hardcode Colors.white:\n${violations.join('\n')}',
      );
    });

    test('zero raw numeric fontSize literals in lib/ (use AppFontSize.*)', () {
      final violations = <String>[];
      final pat = RegExp(r'fontSize\s*:\s*([0-9]+(?:\.[0-9]+)?)\b');
      for (final f in dartFilesUnderLib()) {
        final p = f.path.replaceAll('\\', '/');
        if (p.endsWith('app_typography.dart') ||
            p.endsWith('responsive_typography.dart')) {
          continue;
        }
        final lines = f.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('//')) continue;
          if (pat.hasMatch(line)) {
            violations.add('${f.path}:${i + 1}: ${line.trim()}');
          }
        }
      }
      expect(
        violations,
        isEmpty,
        reason:
            'All font sizes must use AppFontSize tokens:\n${violations.join('\n')}',
      );
    });

    test(
        'sub-11sp font tokens (nano/micro/tiny) only live inside decorative ExcludeSemantics/painter allowlist',
        () {
      const decorativeAllowlist = {
        'app_typography.dart',
        'cassette_body.dart',
        'vinyl_deck.dart',
        'waveform_stage.dart',
        'milkdrop_player_theme.dart',
        'eq_curve_visualizer.dart',
        'dock_style_picker_sheet.dart',
        'pulsr_viewport_debug_overlay.dart',
      };
      final violations = <String>[];
      final pat = RegExp(r'AppFontSize\.(nano|micro|tiny)\b');
      for (final f in dartFilesUnderLib()) {
        final name = f.uri.pathSegments.last;
        if (decorativeAllowlist.contains(name)) continue;
        final lines = f.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          if (pat.hasMatch(lines[i])) {
            violations.add('${f.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
      expect(
        violations,
        isEmpty,
        reason:
            'Functional UI text must be >= 11sp (AppFontSize.caption):\n${violations.join('\n')}',
      );
    });

    test(
        'textTertiary clears WCAG AA (>= 4.5:1) against real surfaces in light/dark/AMOLED/calm',
        () {
      double contrastRatio(Color fg, Color bg) {
        final l1 = fg.computeLuminance();
        final l2 = bg.computeLuminance();
        return l1 > l2 ? (l1 + 0.05) / (l2 + 0.05) : (l2 + 0.05) / (l1 + 0.05);
      }

      final configs = [
        ('light', Brightness.light, false, false, false),
        ('light_calm', Brightness.light, false, false, true),
        ('light_hc', Brightness.light, false, true, false),
        ('dark', Brightness.dark, false, false, false),
        ('dark_calm', Brightness.dark, false, false, true),
        ('amoled', Brightness.dark, true, false, false),
        ('amoled_calm', Brightness.dark, true, false, true),
        ('dark_hc', Brightness.dark, true, true, false),
      ];
      for (final (name, brightness, amoled, hc, calm) in configs) {
        final p = AuraTheme.customTheme(
          AppColors.primary,
          brightness: brightness,
          isAmoled: amoled,
          isHighContrast: hc,
          isCalmDensity: calm,
        ).extension<PulsrPalette>()!;
        for (final surface in [
          p.bg,
          p.surface,
          p.surfaceContainer,
          p.surfaceContainerHigh,
          p.surfaceOverlay,
        ]) {
          final ratio = contrastRatio(p.textTertiary, surface);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason:
                '$name textTertiary (${p.textTertiary}) vs $surface had contrast $ratio < 4.5',
          );
        }
      }
    });
  });
}
