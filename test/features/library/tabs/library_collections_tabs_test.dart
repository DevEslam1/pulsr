// test/features/library/tabs/library_collections_tabs_test.dart
//
// Exercises the Albums / Artists / Genres / Years / Folders library tabs:
// empty + populated rendering across list & grid view modes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/genre_item.dart';
import 'package:pulsr/domain/models/year_item.dart';
import 'package:pulsr/domain/usecases/folder_usecases.dart';
import 'package:pulsr/features/library/cubit/library_state.dart';
import 'package:pulsr/features/library/presentation/library_screen.dart';
import 'package:pulsr/features/library/presentation/widgets/category_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../library_test_harness.dart';

const _album = AlbumsTableData(
  id: 1,
  title: 'Album One',
  artist: 'Artist One',
  songCount: 5,
);

const _artist = ArtistsTableData(
  id: 1,
  name: 'Artist One',
  songCount: 5,
  albumCount: 1,
);

const _folder = FolderItem(
  path: '/music/rock',
  name: 'rock',
  songCount: 12,
  isExcluded: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(registerLibraryFallbacks);

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'pulsr_hint_song_tile_swipe': true,
    });
  });

  Future<void> pumpTab(WidgetTester tester, LibraryState state, String tab) async {
    disableAnimations(tester);
    setSurface(tester);
    await tester.pumpWidget(libraryHarness(
      libraryCubit: stubLibraryCubit(state),
      child: LibraryScreen(initialTabName: tab),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('albums tab renders its empty state', (tester) async {
    await pumpTab(tester, const LibraryState(), 'albums');
    expect(find.text('No albums found in library'), findsOneWidget);
  });

  testWidgets('albums tab renders each album in list mode', (tester) async {
    await pumpTab(
      tester,
      const LibraryState(albums: [_album]),
      'albums',
    );
    expect(find.text('Album One'), findsWidgets);
  });

  testWidgets('albums tab renders a grid when view mode is grid',
      (tester) async {
    await pumpTab(
      tester,
      const LibraryState(albums: [_album], viewMode: LibraryViewMode.grid),
      'albums',
    );
    expect(find.text('Album One'), findsWidgets);
    expect(find.byType(GridView), findsWidgets);
  });

  testWidgets('artists tab renders its empty state', (tester) async {
    await pumpTab(tester, const LibraryState(), 'artists');
    expect(find.text('No Artists Found'), findsOneWidget);
  });

  testWidgets('artists tab renders each artist in list mode', (tester) async {
    await pumpTab(
      tester,
      const LibraryState(artists: [_artist]),
      'artists',
    );
    expect(find.text('Artist One'), findsWidgets);
  });

  testWidgets('genres tab renders category cards when populated',
      (tester) async {
    await pumpTab(
      tester,
      const LibraryState(genres: [GenreItem(name: 'Rock', songCount: 4)]),
      'genres',
    );
    expect(find.byType(CategoryCard), findsOneWidget);
    expect(find.text('Rock'), findsOneWidget);
  });

  testWidgets('genres tab renders its empty state', (tester) async {
    await pumpTab(tester, const LibraryState(), 'genres');
    expect(find.text('No Genres Found'), findsOneWidget);
  });

  testWidgets('years tab renders category cards when populated',
      (tester) async {
    await pumpTab(
      tester,
      const LibraryState(years: [YearItem(year: 2024, songCount: 9)]),
      'years',
    );
    expect(find.byType(CategoryCard), findsOneWidget);
    expect(find.text('2024'), findsOneWidget);
  });

  testWidgets('years tab renders its empty state', (tester) async {
    await pumpTab(tester, const LibraryState(), 'years');
    expect(find.text('No Years Found'), findsOneWidget);
  });

  testWidgets('folders tab lists folders when populated', (tester) async {
    await pumpTab(
      tester,
      const LibraryState(folders: [_folder]),
      'folders',
    );
    expect(find.text('rock'), findsOneWidget);
  });
}
