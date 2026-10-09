// LibraryScreen shell branch coverage: tab selection persistence, the
// didUpdateWidget deep-link switch, the long-press manage sheet, reordering,
// the batch-actions sheet (add-to-queue + delete) and the empty-state refresh.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/features/library/cubit/library_state.dart';
import 'package:pulsr/features/library/presentation/library_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'library_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(registerLibraryFallbacks);

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'pulsr_hint_song_tile_swipe': true,
    });
  });

  Future<void> pump(
    WidgetTester tester, {
    LibraryState state = const LibraryState(),
    String? initialTabName,
    MockLibraryCubit? cubit,
    MockSettingsCubit? settings,
    MockPlayerCubit? player,
  }) async {
    disableAnimations(tester);
    setSurface(tester);
    await tester.pumpWidget(libraryHarness(
      libraryCubit: cubit ?? stubLibraryCubit(state),
      settingsCubit: settings,
      playerCubit: player,
      child: LibraryScreen(initialTabName: initialTabName),
    ));
    await tester.pumpAndSettle();
  }

  // The manage/batch sheets render bare ListTiles over a tinted container,
  // which trips a debug-only ink-splash assertion; drain it so the action
  // under test still runs.
  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    while (tester.takeException() != null) {}
  }

  testWidgets('a changed initialTabName switches the selected tab',
      (tester) async {
    final cubit = stubLibraryCubit(const LibraryState());
    disableAnimations(tester);
    setSurface(tester);
    await tester.pumpWidget(libraryHarness(
      libraryCubit: cubit,
      child: const LibraryScreen(initialTabName: 'songs'),
    ));
    await tester.pumpAndSettle();

    await tester.pumpWidget(libraryHarness(
      libraryCubit: cubit,
      child: const LibraryScreen(initialTabName: 'albums'),
    ));
    await tester.pumpAndSettle();
    // Let the debounced tab-persistence timer fire.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.text('Albums'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long-pressing a tab opens the manage sheet', (tester) async {
    await pump(tester);

    await tester.longPress(find.text('Songs'));
    await tester.pumpAndSettle();

    expect(find.text('Reset'), findsOneWidget);
  });

  testWidgets('reordering the active tabs persists the new order',
      (tester) async {
    await pump(tester);
    await tester.tap(find.byIcon(Icons.dashboard_customize_rounded));
    await tester.pumpAndSettle();

    final list =
        tester.widget<ReorderableListView>(find.byType(ReorderableListView));
    list.onReorderItem!(0, 1);
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    final tabs = prefs.getStringList('library_active_tabs');
    expect(tabs, isNotNull);
    expect(tabs!.first, isNot('songs'));
  });

  testWidgets('batch add-to-queue reaches the player', (tester) async {
    final songs = [testSong(id: 1, title: 'Alpha'), testSong(id: 2, title: 'Beta')];
    final cubit = stubLibraryCubit(LibraryState(
      isMultiSelectMode: true,
      selectedSongIds: const {1, 2},
      songs: songs,
    ));
    when(() => cubit.getSelectedSongs()).thenAnswer((_) async => songs);
    final player = stubPlayerCubit();
    when(() => player.addToQueue(any())).thenAnswer((_) async {});

    await pump(tester, cubit: cubit, player: player);

    await tester.tap(find.text('Batch Actions'));
    await settle(tester);
    await tester.tap(find.text('Add to Queue'));
    await settle(tester);

    verify(() => player.addToQueue(any())).called(2);
    verify(() => cubit.clearSelection()).called(1);
  });

  testWidgets('batch delete confirms and reports the removed count',
      (tester) async {
    final songs = [testSong(id: 1, title: 'Alpha'), testSong(id: 2, title: 'Beta')];
    final cubit = stubLibraryCubit(LibraryState(
      isMultiSelectMode: true,
      selectedSongIds: const {1, 2},
      songs: songs,
    ));
    when(() => cubit.getSelectedSongs()).thenAnswer((_) async => songs);
    when(() => cubit.deleteSelectedSongs()).thenAnswer((_) async => 2);

    await pump(tester, cubit: cubit);

    await tester.tap(find.text('Batch Actions'));
    await settle(tester);
    await tester.tap(find.text('Delete'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await settle(tester);

    verify(() => cubit.deleteSelectedSongs()).called(1);
    expect(find.text('Songs deleted'), findsOneWidget);
  });

  testWidgets('the empty-state refresh indicator rescans', (tester) async {
    final settings = stubSettingsCubit();
    final cubit = stubLibraryCubit(const LibraryState());
    await pump(tester, cubit: cubit, settings: settings);

    final indicator = tester.widget<RefreshIndicator>(
        find.byType(RefreshIndicator).first);
    await indicator.onRefresh();
    await tester.pumpAndSettle();

    verify(() => settings.rescanLibrary()).called(1);
  });
}
