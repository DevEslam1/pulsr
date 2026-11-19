import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pulsr/core/constants/app_blur.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/glass_container.dart';
import 'package:pulsr/core/widgets/pulsr_dialog.dart';

/// The audit's single most damaging material defect was a dialog that ran an
/// 18-sigma backdrop filter and then painted an opaque slab over it: full GPU
/// cost, zero visual effect. These tests pin the corrected contract.
void main() {
  test('glass presets never exceed the raster ceiling', () {
    for (final preset in GlassPreset.values) {
      expect(
        preset.blur,
        lessThanOrEqualTo(AppBlur.maxSigma),
        reason: '${preset.name} declares a sigma the GPU will clamp',
      );
      expect(preset.blur, AppBlur.clampSigma(preset.blur));
    }
  });

  testWidgets('a caller colour is modulated, not treated as opaque glass',
      (tester) async {
    final palette = AuraTheme.defaultDark;
    await tester.pumpWidget(
      MaterialApp(
        theme: AuraTheme.darkTheme,
        home: Scaffold(
          body: GlassContainer(
            // An opaque palette colour: the primitive must still resolve to a
            // translucent tint so the backdrop shows through.
            color: palette.surfaceContainerHigh,
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      ),
    );

    final containers = tester.widgetList<Container>(find.byType(Container));
    final alphas = <double>[];
    for (final container in containers) {
      final decoration = container.decoration;
      if (decoration is BoxDecoration && decoration.color != null) {
        alphas.add(decoration.color!.a);
      }
    }
    expect(alphas, isNotEmpty, reason: 'no decorated glass surface rendered');
    expect(
      alphas.any((a) => a > 0.0 && a < 1.0),
      isTrue,
      reason: 'an opaque caller colour bypassed the glass tint maths '
          '(alphas: $alphas)',
    );
  });

  testWidgets('PulsrDialog paints a translucent glass surface', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AuraTheme.darkTheme,
        home: const Scaffold(
          body: Center(
            child: PulsrDialog(
              title: Text('Title'),
              content: Text('Body'),
            ),
          ),
        ),
      ),
    );

    // The dialog must not override the glass tint with an opaque palette
    // colour; leaving `color` null is what lets GlassContainer apply alpha.
    final glass = tester.widget<GlassContainer>(find.byType(GlassContainer));
    expect(glass.color, isNull,
        reason: 'PulsrDialog passed an opaque colour, making its blur '
            'invisible while still paying for it');
  });

  testWidgets('in-app High Contrast disables the backdrop filter',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AuraTheme.darkTheme,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(highContrast: true),
            child: const Scaffold(
              body: Center(
                child: PulsrDialog(
                  title: Text('Title'),
                  content: Text('Body'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing,
        reason: 'the app High Contrast mode is mirrored into '
            'MediaQuery.highContrast, so AppBlur.canBlur must return false');
  });
}
