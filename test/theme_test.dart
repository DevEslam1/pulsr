import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/theme/aura_theme.dart';

void main() {
  group('Theme Palette and Accent Variations', () {
    final accents = <String, Color>{
      'Neon Cyan': const Color(0xFF00E5FF),
      'Deep Violet': const Color(0xFF9B9EF5),
      'Sunset Amber': const Color(0xFFFF9100),
      'Electric Emerald': const Color(0xFF00E676),
      'Monokai Magenta': const Color(0xFFFF007F),
    };

    for (final entry in accents.entries) {
      test('Theme builds valid palette for ${entry.key}', () {
        final darkTheme = AuraTheme.customTheme(entry.value, brightness: Brightness.dark);
        final lightTheme = AuraTheme.customTheme(entry.value, brightness: Brightness.light);
        final amoledTheme = AuraTheme.customTheme(entry.value, brightness: Brightness.dark, isAmoled: true);

        final darkPalette = darkTheme.extension<PulsrPalette>();
        final lightPalette = lightTheme.extension<PulsrPalette>();
        final amoledPalette = amoledTheme.extension<PulsrPalette>();

        expect(darkPalette, isNotNull);
        expect(lightPalette, isNotNull);
        expect(amoledPalette, isNotNull);

        expect(darkPalette!.accent, equals(entry.value));
        expect(amoledPalette!.bg, equals(Colors.black));
        expect(lightPalette!.isDark, isFalse);
      });
    }

    testWidgets('Renders mini player and card across all 5 accent themes', (tester) async {
      for (final entry in accents.entries) {
        final theme = AuraTheme.customTheme(entry.value, brightness: Brightness.dark);

        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Builder(
              builder: (context) {
                final p = context.palette;
                return Scaffold(
                  backgroundColor: p.bg,
                  body: Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: p.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: p.accent),
                      ),
                      child: Text(
                        entry.key,
                        style: TextStyle(color: p.textPrimary),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );

        await tester.pumpAndSettle();
        expect(find.text(entry.key), findsOneWidget);
      }
    });
  });
}
