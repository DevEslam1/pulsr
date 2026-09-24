import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/widgets/equalizer_sheet.dart';
import 'package:pulsr/features/shell/presentation/bottom_nav_bar.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Pulsr UI/UX Audit Remediation Regression Tests', () {
    test('H2: dspSheetRebuildGate detects changes in DspSlice and ignores position ticks', () {
      const a = PlayerState();
      // 1. Position/tick changes are ignored (prevents hot path 10 Hz rebuilds)
      final tickState = a.copyWith(
        playback: a.playback.copyWith(position: const Duration(seconds: 42)),
      );
      expect(dspSheetRebuildGate(a, tickState), isFalse);

      // 2. Any DSP toggle triggers rebuild
      final dspChangedState = a.copyWith(
        dsp: a.dsp.copyWith(isSaturationEnabled: true),
      );
      expect(dspSheetRebuildGate(a, dspChangedState), isTrue);

      // 3. Any DSP slider / numerical adjustment triggers rebuild
      final eqChangedState = a.copyWith(
        dsp: a.dsp.copyWith(saturationDrive: 0.8),
      );
      expect(dspSheetRebuildGate(a, eqChangedState), isTrue);
    });

    testWidgets('M7: Bottom nav bar gestures and drag feedback render cleanly', (tester) async {
      int swipeUpCalls = 0;
      int swipeDownCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            bottomNavigationBar: PulsrBottomNavBar(
              currentIndex: 0,
              onTap: (_) {},
              onSwipeUp: () => swipeUpCalls++,
              onSwipeDown: () => swipeDownCalls++,
            ),
          ),
        ),
      );

      expect(find.byType(PulsrBottomNavBar), findsOneWidget);

      final navBar = find.byType(PulsrBottomNavBar);
      await tester.drag(navBar, const Offset(0, -60));
      await tester.pumpAndSettle();
      expect(swipeUpCalls, 1);

      await tester.drag(navBar, const Offset(0, 60));
      await tester.pumpAndSettle();
      expect(swipeDownCalls, 1);
    });
  });
}
