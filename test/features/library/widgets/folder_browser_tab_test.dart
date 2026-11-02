// test/features/library/widgets/folder_browser_tab_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/usecases/folder_usecases.dart';
import 'package:pulsr/features/library/cubit/library_state.dart';
import 'package:pulsr/features/library/presentation/widgets/folder_browser_tab.dart';

import '../library_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(registerLibraryFallbacks);

  const testFolders = [
    FolderItem(
      path: '/storage/emulated/0/Music',
      name: 'Music',
      songCount: 3,
      isExcluded: false,
      representativeSongId: 101,
    ),
    FolderItem(
      path: '/storage/emulated/0/Download',
      name: 'Download',
      songCount: 15,
      isExcluded: false,
      representativeSongId: 102,
    ),
  ];

  testWidgets('renders empty state when no folders exist', (tester) async {
    setSurface(tester);
    final cubit = stubLibraryCubit(const LibraryState(folders: []));

    await tester.pumpWidget(libraryHarness(
      libraryCubit: cubit,
      child: const Scaffold(body: FolderBrowserTab()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('No Folders Found'), findsOneWidget);
  });

  testWidgets(
      'renders folder list with formatted path, track count and actions',
      (tester) async {
    setSurface(tester);
    final player = stubPlayerCubit();
    final cubit = stubLibraryCubit(const LibraryState(folders: testFolders));

    await tester.pumpWidget(libraryHarness(
      libraryCubit: cubit,
      playerCubit: player,
      child: const Scaffold(body: FolderBrowserTab()),
    ));
    await tester.pumpAndSettle();

    // Verify folder names
    expect(find.text('Music'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);

    // Verify humanized path format (Internal › Music instead of /storage/emulated/0/Music)
    expect(find.text('Internal › Music'), findsOneWidget);

    // Verify download badge for download folder
    expect(find.text('DOWNLOADS'), findsOneWidget);

    // Verify quick play button exists
    expect(find.byIcon(Icons.play_arrow_rounded), findsWidgets);

    // Verify more options menu icon exists
    expect(find.byIcon(Icons.more_vert_rounded), findsWidgets);

    // Verify sort toolbar exists
    expect(find.text('Title'), findsOneWidget);

    // Verify storage helper card exists at the bottom
    expect(find.text('Excluded Folders'), findsOneWidget);
  });

  testWidgets('renders grid view when viewMode is grid', (tester) async {
    setSurface(tester);
    final cubit = stubLibraryCubit(const LibraryState(
      folders: testFolders,
      viewMode: LibraryViewMode.grid,
    ));

    await tester.pumpWidget(libraryHarness(
      libraryCubit: cubit,
      child: const Scaffold(body: FolderBrowserTab()),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(SliverGrid), findsOneWidget);
    expect(find.text('Music'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
  });

  testWidgets('tapping sort pill opens sort options sheet', (tester) async {
    setSurface(tester);
    final cubit = stubLibraryCubit(const LibraryState(folders: testFolders));

    await tester.pumpWidget(libraryHarness(
      libraryCubit: cubit,
      child: const Scaffold(body: FolderBrowserTab()),
    ));
    await tester.pumpAndSettle();

    // Tap sort pill
    await tester.tap(find.text('Title'));
    await tester.pumpAndSettle();

    // Verify bottom sheet opened with sorting options
    expect(find.text('Title (A → Z)'), findsOneWidget);
    expect(find.text('Title (Z → A)'), findsOneWidget);
    expect(find.text('Songs (High → Low)'), findsOneWidget);
    expect(find.text('Songs (Low → High)'), findsOneWidget);
  });
}
