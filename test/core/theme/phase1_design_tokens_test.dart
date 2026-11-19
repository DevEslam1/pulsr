// test/core/theme/phase1_design_tokens_test.dart
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/app_blur.dart';
import 'package:pulsr/core/theme/focus_tokens.dart';
import 'package:pulsr/core/theme/scrim_tokens.dart';
import 'package:pulsr/core/widgets/glass_container.dart';
import 'package:pulsr/core/widgets/highlighted_text.dart';

void main() {
  group('Phase 1 Design System Tokens & Components', () {
    test('GlassPreset definitions map to valid blur and opacity pairs', () {
      // A preset must never declare a sigma above AppBlur.maxSigma: the token
      // would then lie about what the GPU rasterises (24 -> 18).
      expect(GlassPreset.dock.blur, AppBlur.maxSigma);
      expect(GlassPreset.dock.blur, AppBlur.clampSigma(GlassPreset.dock.blur));
      expect(GlassPreset.dock.opacity, 0.72);

      expect(GlassPreset.sheet.blur, AppBlur.maxSigma);
      expect(GlassPreset.sheet.blur, AppBlur.clampSigma(GlassPreset.sheet.blur));
      expect(GlassPreset.sheet.opacity, 0.82);

      expect(GlassPreset.dialog.blur, 16.0);
      expect(GlassPreset.dialog.opacity, 0.88);

      expect(GlassPreset.chip.blur, 8.0);
      expect(GlassPreset.chip.opacity, 0.60);
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
