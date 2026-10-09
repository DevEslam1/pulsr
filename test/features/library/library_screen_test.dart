// test/features/library/library_screen_test.dart
//
// Exercises the LibraryScreen shell: app bar + tab bar, view-mode / sort
// actions, the manage-tabs sheet, the multi-select app bar + batch actions
// sheet, the refresh path and the info-message snackbar.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/widgets/pulsr_empty_state.dart';
import 'package:pulsr/features/library/cubit/library_cubit.dart';
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

  Future<void> pumpScreen(
    WidgetTester tester, {
    LibraryState state = const LibraryState(),
    LibraryCubit? cubit,
    MockSettingsCubit? settings,
  }) async {
    disableAnimations(tester);
    setSurface(tester);
    await tester.pumpWidget(libraryHarness(
      libraryCubit: cubit ?? stubLibraryCubit(state),
      settingsCubit: settings,
      child: const LibraryScreen(),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('renders the library app bar and the default tabs',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Songs'), findsOneWidget);
    expect(find.text('Albums'), findsOneWidget);
    expect(find.text('Artists'), findsOneWidget);
  });

  testWidgets('the view-mode action toggles the cubit view mode',
      (tester) async {
    final cubit = stubLibraryCubit(const LibraryState());
    await pumpScreen(tester, cubit: cubit);

    await tester.tap(find.byIcon(Icons.grid_view_rounded));
    await tester.pump();

    verify(() => cubit.toggleViewMode()).called(1);
  });

  testWidgets('the sort action opens the sort sheet and applies a sort',
      (tester) async {
    final cubit = stubLibraryCubit(const LibraryState());
    await pumpScreen(tester, cubit: cubit);

    await tester.tap(find.byIcon(Icons.sort_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Sort & Filter'), findsOneWidget);

    await tester.tap(find.text('Title'));
    await tester.pumpAndSettle();

    verify(() => cubit.updateSort('title', false)).called(1);
  });

  testWidgets('the manage-tabs action opens the tabs sheet', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byIcon(Icons.dashboard_customize_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Tabs'), findsWidgets);
    expect(find.byType(ReorderableListView), findsOneWidget);

    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();

    expect(find.byType(ReorderableListView), findsOneWidget);
  });

  testWidgets('the empty state scan action refreshes the library',
      (tester) async {
    final libCubit = stubLibraryCubit(const LibraryState());
    final settingsCubit = stubSettingsCubit();
    await pumpScreen(tester, cubit: libCubit, settings: settingsCubit);

    expect(find.byType(PulsrEmptyState), findsOneWidget);

    await tester.tap(find.text('Scan Storage'));
    await tester.pumpAndSettle();

    verify(() => settingsCubit.rescanLibrary()).called(1);
    verify(() => libCubit.init()).called(1);
  });

  testWidgets('multi-select mode shows the selection app bar', (tester) async {
    final state = LibraryState(
      isMultiSelectMode: true,
      selectedSongIds: const {1, 2},
      songs: [
        testSong(id: 1, title: 'Alpha'),
        testSong(id: 2, title: 'Beta'),
      ],
    );
    final cubit = stubLibraryCubit(state);
    await pumpScreen(tester, cubit: cubit);

    expect(find.text('2 Selected'), findsOneWidget);
    expect(find.text('Batch Actions'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();

    verify(() => cubit.clearSelection()).called(1);
  });

  testWidgets('the multi-select select-all action reaches the cubit',
      (tester) async {
    final state = LibraryState(
      isMultiSelectMode: true,
      selectedSongIds: const {1},
      songs: [testSong(id: 1, title: 'Alpha')],
    );
    final cubit = stubLibraryCubit(state);
    await pumpScreen(tester, cubit: cubit);

    await tester.tap(find.byIcon(Icons.select_all_rounded));
    await tester.pump();

    verify(() => cubit.selectAllSongs()).called(1);
  });

  testWidgets('an info message is surfaced as a snackbar', (tester) async {
    final controller = StreamController<LibraryState>.broadcast();
    addTearDown(controller.close);
    final cubit =
        stubLibraryCubit(const LibraryState(), stream: controller.stream);

    await pumpScreen(tester, cubit: cubit);

    controller.add(const LibraryState(infoMessage: 'Library notice'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Library notice'), findsOneWidget);
  });
}
