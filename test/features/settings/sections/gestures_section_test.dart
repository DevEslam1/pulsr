// Covers lib/features/settings/presentation/sections/gestures_section.dart
// via the real SettingsScreen forced onto the "look" category.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/widgets/pulsr_bottom_sheet.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import '../support/settings_section_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('en'));

  setUp(stubSettingsChannels);
  tearDown(clearSettingsChannels);

  Finder inSheet(String text) => find.descendant(
        of: find.byType(PulsrBottomSheetContainer),
        matching: find.text(text),
      );

  testWidgets('renders every gesture row and opens the left-swipe picker',
      (tester) async {
    final h = await pumpSettingsCategory(tester, category: 'look');
    addTearDown(h.cubit.close);

    expect(find.text(l10n.gestures.toUpperCase()), findsOneWidget);
    expect(find.text(l10n.miniPlayerSwipeLeft), findsOneWidget);
    expect(find.text(l10n.miniPlayerSwipeRight), findsOneWidget);
    expect(find.text(l10n.nowPlayingDoubleTap), findsOneWidget);
    expect(find.text(l10n.artworkSwipe), findsOneWidget);

    await tester.tap(find.text(l10n.miniPlayerSwipeLeft));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(PulsrBottomSheetContainer), findsOneWidget);
    expect(find.text(l10n.settingsSwipeLeftAction), findsOneWidget);

    // Select "Adjust Volume" for the left swipe.
    await tester.tap(inSheet(l10n.settingsSwipeAdjustVolume));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      h.cubit.state.miniPlayerSwipeLeft,
      MiniPlayerSwipeAction.volume,
    );
  });

  testWidgets('right-swipe picker selects next track and pops',
      (tester) async {
    final h = await pumpSettingsCategory(tester, category: 'look');
    addTearDown(h.cubit.close);

    await tester.tap(find.text(l10n.miniPlayerSwipeRight));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(l10n.settingsSwipeRightAction), findsOneWidget);
    await tester.tap(inSheet(l10n.settingsSwipeNextTrack));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(h.cubit.state.miniPlayerSwipeRight, MiniPlayerSwipeAction.next);
    expect(find.byType(PulsrBottomSheetContainer), findsNothing);
  });

  testWidgets('double-tap picker selects lyrics overlay action',
      (tester) async {
    final h = await pumpSettingsCategory(tester, category: 'look');
    addTearDown(h.cubit.close);

    await tester.tap(find.text(l10n.nowPlayingDoubleTap));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(l10n.npDoubleTap), findsOneWidget);
    await tester.tap(inSheet(l10n.settingsDoubleTapToggleLyrics));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      h.cubit.state.nowPlayingDoubleTap,
      NowPlayingDoubleTapAction.toggleLyrics,
    );
  });

  testWidgets('artwork-swipe picker can disable the gesture', (tester) async {
    final h = await pumpSettingsCategory(tester, category: 'look');
    addTearDown(h.cubit.close);

    await tester.tap(find.text(l10n.artworkSwipe));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(l10n.npArtworkSwipe), findsOneWidget);
    // The "Disabled" option is the last list tile in the sheet.
    await tester.tap(inSheet(l10n.settingsArtworkSwipeDisabled));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      h.cubit.state.nowPlayingArtworkSwipe,
      NowPlayingArtworkSwipeAction.none,
    );
  });
}
