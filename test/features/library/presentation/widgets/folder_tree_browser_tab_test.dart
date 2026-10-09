// FolderTreeBrowserTab widget suite: empty library, folder derivation from
// song paths, breadcrumbs, subfolder navigation, artwork fallback and play.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/widgets/song_tile.dart';
import 'package:pulsr/domain/usecases/folder_usecases.dart';
import 'package:pulsr/features/library/cubit/library_state.dart';
import 'package:pulsr/features/library/presentation/widgets/folder_tree_browser_tab.dart';

import '../../library_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(registerLibraryFallbacks);



  testWidgets('shows the empty library message when no songs exist',
      (tester) async {
    setSurface(tester);
    final cubit = stubLibraryCubit(const LibraryState());

    await tester.pumpWidget(libraryHarness(
      libraryCubit: cubit,
      child: const Scaffold(body: FolderTreeBrowserTab()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('No music files indexed'), findsOneWidget);
  });

  testWidgets('derives folders from song paths and lists them',
      (tester) async {
    setSurface(tester);
    final player = stubPlayerCubit();
    final cubit = stubLibraryCubit(LibraryState(
      songs: [
        testSong(id: 1, title: 'Song One', path: '/music/AlbumA/s1.mp3'),
        testSong(id: 2, title: 'Song Two', path: '/music/AlbumA/s2.mp3'),
        testSong(id: 3, title: 'Deep', path: '/music/AlbumA/Sub/s3.mp3'),
        testSong(id: 4, title: 'Other', path: '/music/AlbumB/s4.mp3'),
      ],
      folders: const [
        FolderItem(
            path: '/music/AlbumA',
            name: 'AlbumA',
            songCount: 2,
            isExcluded: false,
            representativeSongId: 1),
      ],
    ));

    await tester.pumpWidget(libraryHarness(
      libraryCubit: cubit,
      playerCubit: player,
      child: const Scaffold(body: FolderTreeBrowserTab()),
    ));
    await tester.pumpAndSettle();

    // Breadcrumb shows the resolved root folder.
    expect(find.text('AlbumA'), findsWidgets);
    // Sub-folder tile.
    expect(find.text('Sub'), findsOneWidget);
    // Direct child songs.
    expect(find.text('Song One'), findsOneWidget);
    expect(find.text('Song Two'), findsOneWidget);
    // Song from another folder is not shown at this level.
    expect(find.text('Other'), findsNothing);
  });

  testWidgets('tapping a song plays it', (tester) async {
    setSurface(tester);
    final player = stubPlayerCubit();
    final cubit = stubLibraryCubit(LibraryState(songs: [
      testSong(id: 1, title: 'Song One', path: '/music/AlbumA/s1.mp3'),
    ]));

    await tester.pumpWidget(libraryHarness(
      libraryCubit: cubit,
      playerCubit: player,
      child: const Scaffold(body: FolderTreeBrowserTab()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SongTile).first);
    await tester.pump();

    verify(() => player.playSong(any(), queue: any(named: 'queue'))).called(1);
  });

  testWidgets('navigating into a subfolder updates breadcrumbs and content',
      (tester) async {
    setSurface(tester);
    final cubit = stubLibraryCubit(LibraryState(songs: [
      testSong(id: 1, title: 'Top Song', path: '/music/AlbumA/s1.mp3'),
      testSong(id: 2, title: 'Nested Song', path: '/music/AlbumA/Sub/s2.mp3'),
    ]));

    await tester.pumpWidget(libraryHarness(
      libraryCubit: cubit,
      child: const Scaffold(body: FolderTreeBrowserTab()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Top Song'), findsOneWidget);
    expect(find.text('Nested Song'), findsNothing);

    await tester.tap(find.text('Sub'));
    await tester.pumpAndSettle();

    // Inside the subfolder: nested song visible, parent-directory affordance.
    expect(find.text('Nested Song'), findsOneWidget);
    expect(find.text('Parent Directory'), findsOneWidget);
  });
}
