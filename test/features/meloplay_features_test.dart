import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/app_colors.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/pulsr_toast.dart';
import 'package:pulsr/core/widgets/spinning_vinyl_disc.dart';
import 'package:pulsr/core/widgets/staggered_list_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Meloplay Features Adapted to Pulsr', () {
    test('AuraTheme presets are properly defined with distinct gradients', () {
      expect(AuraTheme.presets.length, greaterThanOrEqualTo(6));

      final names = AuraTheme.presets.map((p) => p.name).toSet();
      expect(names.length, equals(AuraTheme.presets.length),
          reason: 'All preset names must be unique');

      for (final preset in AuraTheme.presets) {
        expect(preset.name.isNotEmpty, isTrue);
        expect(preset.primaryColor, isNotNull);
        expect(preset.secondaryColor, isNotNull);
        expect(preset.accentColor, isNotNull);
        expect(preset.gradient.colors.length, equals(2));
      }

      final amoledPreset = AuraTheme.presets.firstWhere((p) => p.isAmoled);
      expect(amoledPreset.name, equals('Midnight AMOLED'));
      expect(amoledPreset.primaryColor, equals(const Color(0xFF000000)));
    });

    testWidgets(
        'SpinningVinylDisc renders with correct size and outer groove decoration',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AuraTheme.darkTheme,
          home: const Scaffold(
            body: Center(
              child: SpinningVinylDisc(
                id: 101,
                size: 60.0,
                isPlaying: true,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(SpinningVinylDisc), findsOneWidget);
      // The disc itself is the sized surface; the first SizedBox inside it is
      // the centre label, not the outer groove.
      expect(tester.getSize(find.byType(SpinningVinylDisc)),
          const Size(60.0, 60.0));
      final disc = tester.widget<Container>(find
          .descendant(
              of: find.byType(SpinningVinylDisc),
              matching: find.byType(Container))
          .first);
      final decoration = disc.decoration as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
      expect(decoration.border!.top.color, AppColors.vinylDiscRim);
    });

    testWidgets('StaggeredListItem animates its child into view',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StaggeredListItem(
              index: 0,
              animDuration: Duration(milliseconds: 100),
              child: Text('Cascading Track Item'),
            ),
          ),
        ),
      );

      expect(find.text('Cascading Track Item'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.text('Cascading Track Item'), findsOneWidget);
    });

    testWidgets('PulsrToast shows floating pill with message and icon',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AuraTheme.darkTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  PulsrToast.show(
                    context,
                    message: 'Playlist updated (+3 / -1)',
                    icon: Icons.check_circle_rounded,
                  );
                },
                child: const Text('Show Toast'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Toast'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Playlist updated (+3 / -1)'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

      // Settle the auto-dismiss timer
      await tester.pump(const Duration(milliseconds: 2500));
    });
  });
}
