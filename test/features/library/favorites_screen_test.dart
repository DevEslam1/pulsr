// test/features/library/favorites_screen_test.dart
//
// Exercises the standalone Favorites surface: empty/populated local + online
// buckets, search filtering (match + no-match), row playback, and the inline
// favorite toggle.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/widgets/song_tile.dart';
import 'package:pulsr/features/library/cubit/library_state.dart';
import 'package:pulsr/features/library/presentation/favorites_screen.dart';
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

  Future<void> pumpFavorites(
    WidgetTester tester,
    LibraryState state, {
    MockPlayerCubit? player,
  }) async {
    disableAnimations(tester);
    setSurface(tester);
    await tester.pumpWidget(libraryHarness(
      libraryCubit: stubLibraryCubit(state),
      playerCubit: player,
      child: const FavoritesScreen(),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('empty local favorites renders the empty state', (tester) async {
    await pumpFavorites(tester, const LibraryState());
    expect(find.text('No Local Favorites'), findsOneWidget);
    expect(find.byType(SongTile), findsNothing);
  });

  testWidgets('local favorites render a tile per song', (tester) async {
    await pumpFavorites(
      tester,
      LibraryState(favorites: [
        testSong(id: 1, title: 'First Love', isFavorite: true),
        testSong(id: 2, title: 'Second Love', isFavorite: true),
      ]),
    );
    expect(find.byType(SongTile), findsNWidgets(2));
    expect(find.text('First Love'), findsOneWidget);
  });

  testWidgets('online sub-tab shows only the online bucket', (tester) async {
    await pumpFavorites(
      tester,
      LibraryState(favorites: [
        testSong(id: 1, title: 'Local Love', isFavorite: true),
        testOnlineSong(id: 2, title: 'Cloud Love'),
      ]),
    );

    expect(find.text('Local Love'), findsOneWidget);
    expect(find.text('Cloud Love'), findsNothing);

    await tester.tap(find.textContaining('Online'));
    await tester.pumpAndSettle();

    expect(find.text('Cloud Love'), findsOneWidget);
    expect(find.text('Local Love'), findsNothing);
  });

  testWidgets('tapping a favorite plays it', (tester) async {
    final player = stubPlayerCubit();
    await pumpFavorites(
      tester,
      LibraryState(favorites: [
        testSong(id: 1, title: 'First Love', isFavorite: true),
      ]),
      player: player,
    );

    await tester.tap(find.byType(SongTile).first);
    await tester.pump();

    verify(() => player.playSong(any(), queue: any(named: 'queue'))).called(1);
  });

  testWidgets('the inline favorite button toggles the favorite', (tester) async {
    final cubit = stubLibraryCubit(LibraryState(favorites: [
      testSong(id: 1, title: 'First Love', isFavorite: true),
    ]));
    disableAnimations(tester);
    setSurface(tester);
    await tester.pumpWidget(libraryHarness(
      libraryCubit: cubit,
      child: const FavoritesScreen(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.favorite_rounded).last);
    await tester.pump();

    verify(() => cubit.toggleFavorite(1)).called(1);
  });

  testWidgets('opening search and filtering narrows the list', (tester) async {
    await pumpFavorites(
      tester,
      LibraryState(favorites: [
        testSong(id: 1, title: 'Alpha', isFavorite: true),
        testSong(id: 2, title: 'Beta', isFavorite: true),
      ]),
    );

    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'alpha');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsNothing);
  });

  testWidgets('a search with no matches shows the no-results state',
      (tester) async {
    await pumpFavorites(
      tester,
      LibraryState(favorites: [
        testSong(id: 1, title: 'Alpha', isFavorite: true),
      ]),
    );

    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('No songs match'), findsOneWidget);
  });
}
