// test/features/library/tabs/library_songs_tab_test.dart
//
// Exercises the Songs + Downloaded library tabs (mixins on LibraryScreen):
// empty/loading rendering, populated list + grid, tap-to-play, long-press
// selection, stream pre-warming and the A-Z quick-scroll rail.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/widgets/shimmer_skeleton.dart';
import 'package:pulsr/core/widgets/song_tile.dart';
import 'package:pulsr/features/library/cubit/library_state.dart';
import 'package:pulsr/features/library/presentation/library_screen.dart';
import 'package:pulsr/features/library/presentation/widgets/alphabet_quick_scroll.dart';
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

  testWidgets('empty songs tab renders its empty state', (tester) async {
    disableAnimations(tester);
    setSurface(tester);
    final cubit = stubLibraryCubit(const LibraryState());

    await tester.pumpWidget(libraryHarness(
      libraryCubit: cubit,
      child: const LibraryScreen(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('No Songs Found'), findsOneWidget);
    expect(find.byType(SongTile), findsNothing);
  });

  testWidgets('loading songs tab renders a skeleton list', (tester) async {
    disableAnimations(tester);
    setSurface(tester);
    final cubit = stubLibraryCubit(const LibraryState(isLoading: true));

    await tester.pumpWidget(libraryHarness(
      libraryCubit: cubit,
      child: const LibraryScreen(),
    ));
    await tester.pump();

    expect(find.byType(SkeletonList), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('populated songs tab renders a tile per song and plays on tap',
      (tester) async {
    disableAnimations(tester);
    setSurface(tester);
    final player = stubPlayerCubit();
    final cubit = stubLibraryCubit(LibraryState(songs: [
      testSong(id: 1, title: 'Alpha'),
      testSong(id: 2, title: 'Beta'),
      testSong(id: 3, title: 'Gamma'),
    ]));

    await tester.pumpWidget(libraryHarness(
      libraryCubit: cubit,
      playerCubit: player,
      child: const LibraryScreen(),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(SongTile), findsNWidgets(3));

    await tester.tap(find.byType(SongTile).first);
    await tester.pump();

    verify(() => player.playSong(any(), queue: any(named: 'queue'))).called(1);
  });

  testWidgets('long-press on a song enters multi-select', (tester) async {
    disableAnimations(tester);
    setSurface(tester);
    final cubit = stubLibraryCubit(LibraryState(songs: [
      testSong(id: 7, title: 'Alpha'),
    ]));

    await tester.pumpWidget(libraryHarness(
      libraryCubit: cubit,
      child: const LibraryScreen(),
    ));
    await tester.pumpAndSettle();

    await tester.longPress(find.byType(SongTile).first);
    await tester.pump();

    verify(() => cubit.toggleSongSelection(7)).called(1);
  });

  testWidgets('grid view mode renders the songs as a grid', (tester) async {
    disableAnimations(tester);
    setSurface(tester);
    final cubit = stubLibraryCubit(LibraryState(
      viewMode: LibraryViewMode.grid,
      songs: [
        testSong(id: 1, title: 'Alpha'),
        testSong(id: 2, title: 'Beta'),
      ],
    ));

    await tester.pumpWidget(libraryHarness(
      libraryCubit: cubit,
      child: const LibraryScreen(),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(GridView), findsOneWidget);
  });

  testWidgets('online songs are pre-warmed for streaming', (tester) async {
    disableAnimations(tester);
    setSurface(tester);
    final player = stubPlayerCubit();
    final cubit = stubLibraryCubit(LibraryState(songs: [
      testSong(id: 1, title: 'Local'),
      testOnlineSong(id: 2, title: 'Online'),
    ]));

    await tester.pumpWidget(libraryHarness(
      libraryCubit: cubit,
      playerCubit: player,
      child: const LibraryScreen(),
    ));
    await tester.pumpAndSettle();

    verify(() => player.warmStreams(any(), count: any(named: 'count')))
        .called(1);
  });

  testWidgets('A-Z rail appears for a long title-sorted song list',
      (tester) async {
    disableAnimations(tester);
    setSurface(tester, size: const Size(1000, 1600));
    final songs = List.generate(
      20,
      (i) => testSong(id: i + 1, title: 'Song ${i + 1}'),
    );
    final cubit = stubLibraryCubit(LibraryState(songs: songs));

    await tester.pumpWidget(libraryHarness(
      libraryCubit: cubit,
      child: const LibraryScreen(),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(AlphabetQuickScroll), findsOneWidget);
  });

  testWidgets('downloaded tab lists downloaded online tracks', (tester) async {
    disableAnimations(tester);
    setSurface(tester);
    final cubit = stubLibraryCubit(LibraryState(songs: [
      testSong(
        id: 1,
        title: 'Downloaded Track',
        source: 'local',
        path: '/storage/downloads/dl.mp3',
        isDownloaded: true,
      ),
      testSong(id: 2, title: 'Plain Local'),
    ]));

    await tester.pumpWidget(libraryHarness(
      libraryCubit: cubit,
      child: const LibraryScreen(initialTabName: 'downloaded'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Downloaded Track'), findsWidgets);
    expect(find.byType(SongTile), findsOneWidget);
  });

  testWidgets('downloaded tab shows an empty state when nothing is downloaded',
      (tester) async {
    disableAnimations(tester);
    setSurface(tester);
    final cubit = stubLibraryCubit(LibraryState(songs: [
      testSong(id: 1, title: 'Plain Local'),
    ]));

    await tester.pumpWidget(libraryHarness(
      libraryCubit: cubit,
      child: const LibraryScreen(initialTabName: 'downloaded'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('No Downloads Yet'), findsOneWidget);
  });
}
