// test/core/theme/phase1_design_tokens_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/app_elevation.dart';
import 'package:pulsr/core/theme/focus_tokens.dart';
import 'package:pulsr/core/theme/scrim_tokens.dart';
import 'package:pulsr/core/widgets/glass_container.dart';
import 'package:pulsr/core/widgets/highlighted_text.dart';

void main() {
  group('Phase 1 Design System Tokens & Components', () {
    test('GlassPreset definitions map to valid blur and opacity pairs', () {
      expect(GlassPreset.dock.blur, 24.0);
      expect(GlassPreset.dock.opacity, 0.72);

      expect(GlassPreset.sheet.blur, 20.0);
      expect(GlassPreset.sheet.opacity, 0.82);

      expect(GlassPreset.dialog.blur, 16.0);
      expect(GlassPreset.dialog.opacity, 0.88);

      expect(GlassPreset.chip.blur, 8.0);
      expect(GlassPreset.chip.opacity, 0.60);
    });

    test('AppElevation scale produces valid BoxShadow cascades', () {
      expect(AppElevation.e0, isEmpty);

      final e1 = AppElevation.e1(Colors.black);
      expect(e1.length, 1);
      expect(e1.first.blurRadius, 8.0);
      expect(e1.first.offset, const Offset(0, 2));

      final e2 = AppElevation.e2(Colors.black, glowColor: Colors.blue);
      expect(e2.length, 2);
      expect(e2.first.blurRadius, 16.0);
      expect(e2.first.offset, const Offset(0, 4));

      final e3 = AppElevation.e3(Colors.black, glowColor: Colors.purple);
      expect(e3.length, 2);
      expect(e3.first.blurRadius, 24.0);
      expect(e3.first.offset, const Offset(0, 8));
    });

    test('ScrimTokens return dark and light theme alpha variants', () {
      final darkBarrier = ScrimTokens.barrierScrim(true);
      final lightBarrier = ScrimTokens.barrierScrim(false);
      expect(darkBarrier.a, greaterThan(lightBarrier.a));

      final darkPlayer = ScrimTokens.playerScrim(true);
      final lightPlayer = ScrimTokens.playerScrim(false);
      expect(darkPlayer.a, greaterThan(lightPlayer.a));

      final dock = ScrimTokens.dockScrim(Colors.black);
      expect(dock.length, 3);
      expect(dock.first.a, 0.0);
      expect(dock.last.a, closeTo(0.95, 0.01));
    });

    test('FocusTokens ringSide and shadow comply with WCAG 2.4.7', () {
      const accent = Colors.cyan;
      final side = FocusTokens.ringSide(accent);
      expect(side.width, 2.0);
      expect(side.color, accent);

      final shadows = FocusTokens.focusRingShadow(accent);
      expect(shadows.first.spreadRadius, 2.0);
    });

    testWidgets('PulsrHighlightedText highlights search substrings',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PulsrHighlightedText(
              text: 'Audiophile Player',
              query: 'audio',
              baseStyle: TextStyle(color: Colors.white),
              matchStyle:
                  TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      );

      expect(find.byType(PulsrHighlightedText), findsOneWidget);
      expect(find.byType(RichText), findsOneWidget);
    });
  });
}
