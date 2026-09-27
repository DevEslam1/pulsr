// test/features/polish/phase10_polish_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/sound_feedback_service.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/utils/pulsr_haptics.dart';
import 'package:pulsr/core/widgets/pulsr_refresh_indicator.dart';
import 'package:pulsr/features/player/presentation/themes/player_theme_chrome.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 10: Polish & Delight Tests', () {
    test('1. SoundFeedbackService is disabled by default and can be toggled', () {
      expect(SoundFeedbackService.enabled, isFalse);
      
      // Should not throw when calling methods while disabled
      SoundFeedbackService.playClick();
      SoundFeedbackService.playAlert();

      // Enable and verify
      SoundFeedbackService.setEnabled(true);
      expect(SoundFeedbackService.enabled, isTrue);
      SoundFeedbackService.playClick();
      SoundFeedbackService.playAlert();

      // Reset
      SoundFeedbackService.setEnabled(false);
      expect(SoundFeedbackService.enabled, isFalse);
    });

    test('2. PulsrHaptics methods execute cleanly', () {
      expect(() => PulsrHaptics.tap(), returnsNormally);
      expect(() => PulsrHaptics.light(), returnsNormally);
      expect(() => PulsrHaptics.confirm(), returnsNormally);
      expect(() => PulsrHaptics.destructive(), returnsNormally);
      expect(() => PulsrHaptics.selection(), returnsNormally);
    });

    testWidgets('3. PulsrRefreshIndicator integrates with AuraTheme and triggers callback',
        (tester) async {
      bool refreshed = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: [AuraTheme.defaultDark],
          ),
          home: Scaffold(
            body: PulsrRefreshIndicator(
              onRefresh: () async {
                refreshed = true;
              },
              child: ListView(
                children: const [
                  SizedBox(height: 100, child: Text('Pull down item 1')),
                  SizedBox(height: 100, child: Text('Pull down item 2')),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.byType(PulsrRefreshIndicator), findsOneWidget);
      expect(find.byType(RefreshIndicator), findsOneWidget);

      // Trigger pull down gesture
      await tester.fling(find.text('Pull down item 1'), const Offset(0.0, 300.0), 1000.0);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(refreshed, isTrue);
      await tester.pumpAndSettle();
    });

    testWidgets('4. PlayerAnimatedFavoriteButton triggers heart burst transition and callbacks',
        (tester) async {
      bool tapped = false;
      bool isFavorite = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: [AuraTheme.defaultDark],
          ),
          home: StatefulBuilder(
            builder: (context, setState) {
              return Scaffold(
                body: Center(
                  child: PlayerAnimatedFavoriteButton(
                    isFavorite: isFavorite,
                    favoriteColor: Colors.redAccent,
                    inactiveColor: Colors.grey,
                    semanticLabel: 'Favorite Track',
                    onTap: () {
                      tapped = true;
                      setState(() {
                        isFavorite = !isFavorite;
                      });
                    },
                  ),
                ),
              );
            },
          ),
        ),
      );

      // Initial state: outline heart
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
      expect(find.byIcon(Icons.favorite_rounded), findsNothing);

      // Tap to trigger favorite
      await tester.tap(find.byType(PlayerAnimatedFavoriteButton));
      await tester.pump(); // start animation
      await tester.pump(const Duration(milliseconds: 150)); // mid-transition

      expect(tapped, isTrue);

      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border_rounded), findsNothing);
    });
  });
}
