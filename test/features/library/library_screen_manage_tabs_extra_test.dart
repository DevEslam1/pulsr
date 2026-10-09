// LibraryScreen manage-tabs + deep-link coverage: adding an inactive tab,
// removing an active tab, resetting to defaults and the `initialTabName`
// deep-link that appends and selects a non-default tab.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/widgets/pulsr_switch.dart';
import 'package:pulsr/features/library/cubit/library_state.dart';
import 'package:pulsr/features/library/presentation/library_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'library_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(registerLibraryFallbacks);

  Future<void> pumpScreen(
    WidgetTester tester, {
    LibraryState state = const LibraryState(),
    String? initialTabName,
  }) async {
    disableAnimations(tester);
    setSurface(tester);
    await tester.pumpWidget(libraryHarness(
      libraryCubit: stubLibraryCubit(state),
      child: LibraryScreen(initialTabName: initialTabName),
    ));
    await tester.pumpAndSettle();
  }

  Future<List<String>?> activeTabs() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('library_active_tabs');
  }

  testWidgets('adding an inactive tab persists it', (tester) async {
    SharedPreferences.setMockInitialValues({
      'pulsr_hint_song_tile_swipe': true,
      'library_active_tabs': ['songs'],
    });
    await pumpScreen(tester);

    await tester.tap(find.byIcon(Icons.dashboard_customize_rounded));
    await tester.pumpAndSettle();

    // Active rows come first (Songs), so index 1 is the first inactive tab.
    await tester.tap(find.byType(PulsrSwitch).at(1));
    await tester.pumpAndSettle();

    final tabs = await activeTabs();
    expect(tabs, isNotNull);
    expect(tabs!.length, 2);
    expect(tabs.first, 'songs');
  });

  testWidgets('removing an active tab persists the change', (tester) async {
    SharedPreferences.setMockInitialValues({
      'pulsr_hint_song_tile_swipe': true,
    });
    await pumpScreen(tester);

    await tester.tap(find.byIcon(Icons.dashboard_customize_rounded));
    await tester.pumpAndSettle();

    // Remove the first active tab (Songs).
    await tester.tap(find.byType(PulsrSwitch).first);
    await tester.pumpAndSettle();

    final tabs = await activeTabs();
    expect(tabs, isNotNull);
    expect(tabs, isNot(contains('songs')));
  });

  testWidgets('reset restores the default tabs', (tester) async {
    SharedPreferences.setMockInitialValues({
      'pulsr_hint_song_tile_swipe': true,
      'library_active_tabs': ['songs'],
    });
    await pumpScreen(tester);

    await tester.tap(find.byIcon(Icons.dashboard_customize_rounded));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();

    final tabs = await activeTabs();
    expect(tabs, isNotNull);
    expect(tabs, ['songs', 'albums', 'artists', 'favorites']);
  });

  testWidgets('initialTabName appends and selects a non-default tab',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'pulsr_hint_song_tile_swipe': true,
    });
    await pumpScreen(tester, initialTabName: 'genres');

    // The deep-linked tab is now part of the tab bar.
    expect(find.text('Genres'), findsWidgets);
  });
}
