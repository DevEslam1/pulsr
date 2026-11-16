import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/genre_item.dart';
import 'package:pulsr/domain/models/year_item.dart';
import 'package:pulsr/domain/usecases/folder_usecases.dart';
import 'package:pulsr/features/library/cubit/library_state.dart';
import 'package:pulsr/features/library/presentation/library_screen.dart';
import 'package:pulsr/features/library/presentation/library_tab_sort.dart';
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

  group('LibraryTabSort pure comparators', () {
    test('sortAlbums orders by title, artist, songCount, and year', () {
      const a = AlbumsTableData(
        id: 1,
        title: 'Zebra',
        artist: 'Beta',
        songCount: 4,
        year: 2010,
      );
      const b = AlbumsTableData(
        id: 2,
        title: 'Alpha',
        artist: 'Omega',
        songCount: 12,
        year: 2022,
      );

      expect(
        LibraryTabSort.sortAlbums(
          [a, b],
          const LibraryTabSortSpec(sortBy: 'title', ascending: true),
        ).map((e) => e.id),
        [2, 1],
      );
      expect(
        LibraryTabSort.sortAlbums(
          [a, b],
          const LibraryTabSortSpec(sortBy: 'artist', ascending: true),
        ).map((e) => e.id),
        [1, 2],
      );
      expect(
        LibraryTabSort.sortAlbums(
          [a, b],
          const LibraryTabSortSpec(sortBy: 'songCount', ascending: false),
        ).map((e) => e.id),
        [2, 1],
      );
      expect(
        LibraryTabSort.sortAlbums(
          [a, b],
          const LibraryTabSortSpec(sortBy: 'year', ascending: false),
        ).map((e) => e.id),
        [2, 1],
      );
    });

    test('sortArtists orders by name, albumCount, and songCount', () {
      const a = ArtistsTableData(
        id: 1,
        name: 'Zed',
        albumCount: 5,
        songCount: 20,
      );
      const b = ArtistsTableData(
        id: 2,
        name: 'Ada',
        albumCount: 1,
        songCount: 50,
      );

      expect(
        LibraryTabSort.sortArtists(
          [a, b],
          const LibraryTabSortSpec(sortBy: 'name', ascending: true),
        ).map((e) => e.id),
        [2, 1],
      );
      expect(
        LibraryTabSort.sortArtists(
          [a, b],
          const LibraryTabSortSpec(sortBy: 'albumCount', ascending: false),
        ).map((e) => e.id),
        [1, 2],
      );
      expect(
        LibraryTabSort.sortArtists(
          [a, b],
          const LibraryTabSortSpec(sortBy: 'songCount', ascending: false),
        ).map((e) => e.id),
        [2, 1],
      );
    });

    test('sortFolders, sortGenres, sortYears, and sortSongs honor keys', () {
      const f1 = FolderItem(
        path: '/music/z',
        name: 'Zed',
        songCount: 3,
        isExcluded: false,
      );
      const f2 = FolderItem(
        path: '/music/a',
        name: 'Alpha',
        songCount: 12,
        isExcluded: false,
      );
      expect(
        LibraryTabSort.sortFolders(
          [f1, f2],
          const LibraryTabSortSpec(sortBy: 'songCount', ascending: false),
        ).map((e) => e.name),
        ['Alpha', 'Zed'],
      );

      const g1 = GenreItem(name: 'Rock', songCount: 30);
      const g2 = GenreItem(name: 'Ambient', songCount: 5);
      expect(
        LibraryTabSort.sortGenres(
          [g1, g2],
          const LibraryTabSortSpec(sortBy: 'name', ascending: true),
        ).map((e) => e.name),
        ['Ambient', 'Rock'],
      );
      expect(
        LibraryTabSort.sortGenres(
          [g1, g2],
          const LibraryTabSortSpec(sortBy: 'songCount', ascending: false),
        ).map((e) => e.name),
        ['Rock', 'Ambient'],
      );

      const y1 = YearItem(year: 2005, songCount: 40);
      const y2 = YearItem(year: 2024, songCount: 8);
      expect(
        LibraryTabSort.sortYears(
          [y1, y2],
          const LibraryTabSortSpec(sortBy: 'year', ascending: false),
        ).map((e) => e.year),
        [2024, 2005],
      );
      expect(
        LibraryTabSort.sortYears(
          [y1, y2],
          const LibraryTabSortSpec(sortBy: 'songCount', ascending: false),
        ).map((e) => e.year),
        [2005, 2024],
      );

      final s1 = testSong(id: 1, title: 'Short', durationMs: 1000);
      final s2 = testSong(id: 2, title: 'Long', durationMs: 9000);
      expect(
        LibraryTabSort.sortSongs(
          [s1, s2],
          const LibraryTabSortSpec(sortBy: 'duration', ascending: false),
        ).map((e) => e.id),
        [2, 1],
      );
    });
  });

  testWidgets('sort button is enabled on Albums tab, reorders and persists',
      (tester) async {
    disableAnimations(tester);
    final cubit = stubLibraryCubit(
      const LibraryState(
        albums: [
          AlbumsTableData(
            id: 1,
            title: 'Alpha Album',
            artist: 'Artist',
            songCount: 3,
            year: 2010,
          ),
          AlbumsTableData(
            id: 2,
            title: 'Beta Album',
            artist: 'Artist',
            songCount: 15,
            year: 2023,
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      libraryHarness(
        libraryCubit: cubit,
        child: const LibraryScreen(initialTabName: 'albums'),
      ),
    );
    await tester.pumpAndSettle();

    final sortFinder = find.byIcon(Icons.sort_rounded);
    expect(sortFinder, findsOneWidget);

    await tester.tap(sortFinder);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Songs').last);
    await tester.pumpAndSettle();

    final alphaDy = tester.getTopLeft(find.text('Alpha Album')).dy;
    final betaDy = tester.getTopLeft(find.text('Beta Album')).dy;
    expect(betaDy, lessThan(alphaDy));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('library_sort_albums_by'), 'songCount');
    expect(prefs.getBool('library_sort_albums_asc'), isFalse);
  });
}
