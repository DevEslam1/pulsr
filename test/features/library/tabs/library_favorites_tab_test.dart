// test/features/library/tabs/library_favorites_tab_test.dart
//
// Exercises the Favorites library tab: local/online sub-tabs, empty + populated
// rendering, grid mode and the quick play-all action.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
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

  testWidgets('empty local favorites tab renders its empty state',
      (tester) async {
    disableAnimations(tester);
    setSurface(tester);
    final cubit = stubLibraryCubit(const LibraryState());

    await tester.pumpWidget(libraryHarness(
      libraryCubit: cubit,
      child: const LibraryScreen(initialTabName: 'favorites'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('No Local Favorites'), findsOneWidget);
  });

  testWidgets('local favorites render tiles and the quick-play header',
      (tester) async {
    disableAnimations(tester);
    setSurface(tester);
    final player = stubPlayerCubit();
    final cubit = stubLibraryCubit(LibraryState(favorites: [
      testSong(id: 1, title: 'Loved Local', isFavorite: true),
    ]));

    await tester.pumpWidget(libraryHarness(
      libraryCubit: cubit,
      playerCubit: player,
      child: const LibraryScreen(initialTabName: 'favorites'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Favorites Collection'), findsOneWidget);
    expect(find.text('Open Full Favorites'), findsOneWidget);
    expect(find.byType(SongTile), findsOneWidget);

    await tester.tap(find.text('Play All'));
    await tester.pump();

    verify(() => player.playSong(any(), queue: any(named: 'queue'))).called(1);
  });

  testWidgets('switching to the online sub-tab shows only online favorites',
      (tester) async {
    disableAnimations(tester);
    setSurface(tester);
    final cubit = stubLibraryCubit(LibraryState(favorites: [
      testSong(id: 1, title: 'Loved Local', isFavorite: true),
      testOnlineSong(id: 2, title: 'Loved Online'),
    ]));

    await tester.pumpWidget(libraryHarness(
      libraryCubit: cubit,
      child: const LibraryScreen(initialTabName: 'favorites'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Loved Local'), findsOneWidget);
    expect(find.text('Loved Online'), findsNothing);

    await tester.tap(find.textContaining('Online'));
    await tester.pumpAndSettle();

    expect(find.text('Loved Online'), findsOneWidget);
    expect(find.text('Loved Local'), findsNothing);
  });

  testWidgets('grid view mode renders the favorite grid cards',
      (tester) async {
    disableAnimations(tester);
    setSurface(tester);
    final cubit = stubLibraryCubit(LibraryState(
      viewMode: LibraryViewMode.grid,
      favorites: [
        testSong(id: 1, title: 'Loved Local', isFavorite: true),
      ],
    ));

    await tester.pumpWidget(libraryHarness(
      libraryCubit: cubit,
      child: const LibraryScreen(initialTabName: 'favorites'),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(GridView), findsWidgets);
    expect(find.text('Loved Local'), findsOneWidget);
  });

  testWidgets('tapping the grid heart toggles the favorite', (tester) async {
    disableAnimations(tester);
    setSurface(tester);
    final cubit = stubLibraryCubit(LibraryState(
      viewMode: LibraryViewMode.grid,
      favorites: [
        testSong(id: 1, title: 'Loved Local', isFavorite: true),
      ],
    ));

    await tester.pumpWidget(libraryHarness(
      libraryCubit: cubit,
      child: const LibraryScreen(initialTabName: 'favorites'),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.favorite_rounded).last);
    await tester.pump();

    verify(() => cubit.toggleFavorite(1)).called(1);
  });
}
