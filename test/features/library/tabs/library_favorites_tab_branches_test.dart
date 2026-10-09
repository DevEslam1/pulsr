// LibraryFavoritesTab branch coverage: pull-to-refresh, the quick-play shuffle,
// the two-swipe dismissible confirmations (play next / remove favorite + undo),
// multi-select taps and the grid-card tap.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/widgets/pulsr_dismissible.dart';
import 'package:pulsr/core/widgets/song_tile.dart';
import 'package:pulsr/features/library/cubit/library_state.dart';
import 'package:pulsr/features/library/presentation/library_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../library_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(registerLibraryFallbacks);

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'pulsr_hint_song_tile_swipe': true,
    });
  });

  Future<MockPlayerCubit> pumpFavorites(
    WidgetTester tester, {
    required MockLibraryCubit cubit,
    MockPlayerCubit? player,
    MockSettingsCubit? settings,
    LibraryState? state,
  }) async {
    disableAnimations(tester);
    setSurface(tester);
    final p = player ?? stubPlayerCubit();
    await tester.pumpWidget(libraryHarness(
      libraryCubit: cubit,
      playerCubit: p,
      settingsCubit: settings,
      child: const LibraryScreen(initialTabName: 'favorites'),
    ));
    await tester.pumpAndSettle();
    return p;
  }

  testWidgets('pull-to-refresh rescans the library', (tester) async {
    final cubit = stubLibraryCubit(LibraryState(favorites: [
      testSong(id: 1, title: 'Loved', isFavorite: true),
    ]));
    final settings = stubSettingsCubit();
    await pumpFavorites(tester, cubit: cubit, settings: settings);

    final indicator = tester.widget<RefreshIndicator>(
        find.byType(RefreshIndicator).first);
    await indicator.onRefresh();
    await tester.pumpAndSettle();

    verify(() => settings.rescanLibrary()).called(1);
    verify(() => cubit.init()).called(1);
  });

  testWidgets('the quick-play shuffle starts a shuffled queue',
      (tester) async {
    final cubit = stubLibraryCubit(LibraryState(favorites: [
      testSong(id: 1, title: 'Loved', isFavorite: true),
      testSong(id: 2, title: 'Also', isFavorite: true),
    ]));
    final player = await pumpFavorites(tester, cubit: cubit);

    await tester.tap(find.byIcon(Icons.shuffle_rounded));
    await tester.pump();

    verify(() => player.playSong(any(), queue: any(named: 'queue'))).called(1);
  });

  testWidgets('swiping a favorite start-to-end queues it as next',
      (tester) async {
    final cubit = stubLibraryCubit(LibraryState(favorites: [
      testSong(id: 1, title: 'Loved', isFavorite: true),
    ]));
    final player = await pumpFavorites(tester, cubit: cubit);

    final dismissible =
        tester.widget<PulsrDismissible>(find.byType(PulsrDismissible).first);
    await dismissible.onConfirm(DismissDirection.startToEnd);
    await tester.pump();

    verify(() => player.playNext(any())).called(1);
  });

  testWidgets('swiping a favorite end-to-start removes it and Undo restores',
      (tester) async {
    final cubit = stubLibraryCubit(LibraryState(favorites: [
      testSong(id: 1, title: 'Loved', isFavorite: true),
    ]));
    var toggles = 0;
    when(() => cubit.toggleFavorite(any())).thenAnswer((_) async {
      toggles++;
    });
    await pumpFavorites(tester, cubit: cubit);

    final dismissible =
        tester.widget<PulsrDismissible>(find.byType(PulsrDismissible).first);
    await dismissible.onConfirm(DismissDirection.endToStart);
    await tester.pumpAndSettle();
    expect(toggles, 1);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(toggles, 2);
  });

  testWidgets('tapping a favorite in multi-select toggles selection',
      (tester) async {
    final cubit = stubLibraryCubit(LibraryState(
      isMultiSelectMode: true,
      selectedSongIds: const {1},
      favorites: [testSong(id: 1, title: 'Loved', isFavorite: true)],
    ));
    await pumpFavorites(tester, cubit: cubit);

    await tester.tap(find.byType(SongTile).first);
    await tester.pump();

    verify(() => cubit.toggleSongSelection(1)).called(1);
  });

  testWidgets('long-pressing a favorite toggles selection', (tester) async {
    final cubit = stubLibraryCubit(LibraryState(favorites: [
      testSong(id: 3, title: 'Loved', isFavorite: true),
    ]));
    await pumpFavorites(tester, cubit: cubit);

    await tester.longPress(find.byType(SongTile).first);
    await tester.pump();

    verify(() => cubit.toggleSongSelection(3)).called(1);
  });

  testWidgets('tapping a grid card plays the favorite', (tester) async {
    final cubit = stubLibraryCubit(LibraryState(
      viewMode: LibraryViewMode.grid,
      favorites: [testSong(id: 5, title: 'Loved', isFavorite: true)],
    ));
    final player = await pumpFavorites(tester, cubit: cubit);

    await tester.tap(find.text('Loved').first);
    await tester.pump();

    verify(() => player.playSong(any(), queue: any(named: 'queue'))).called(1);
  });
}
