import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/widgets/shimmer_skeleton.dart';
import 'package:pulsr/domain/usecases/folder_usecases.dart';
import 'package:pulsr/features/folder_detail/presentation/folder_detail_screen.dart';
import 'package:pulsr/features/library/cubit/library_cubit.dart';
import 'package:pulsr/features/library/cubit/library_state.dart';
import 'package:pulsr/features/library/presentation/library_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/detail_screen_harness.dart' hide stubPlayerCubit;
import '../../helpers/test_song_factory.dart';
import 'library_test_harness.dart';

class _FolderUseCases extends Mock implements FolderUseCases {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(registerLibraryFallbacks);

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'pulsr_hint_song_tile_swipe': true,
    });
  });

  testWidgets(
      'LibraryScreen AppBar is decluttered to Search + Sort/Filter pill + Overflow Menu and opens Sort & View sheet with Layout Toggle, Customize Tabs, and Select All',
      (tester) async {
    disableAnimations(tester);
    setSurface(tester);
    final songs = [
      testSong(id: 1, title: 'Alpha'),
      testSong(id: 2, title: 'Beta'),
    ];
    final cubit = stubLibraryCubit(LibraryState(songs: songs));

    await tester.pumpWidget(
      libraryHarness(
        libraryCubit: cubit,
        child: const LibraryScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // AppBar has Search, Sort/Filter pill, and Overflow Menu
    expect(find.byKey(const ValueKey('library_search_action')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('library_sort_filter_pill')), findsOneWidget);
    expect(find.byKey(const ValueKey('library_overflow_menu')), findsOneWidget);

    // Layout toggle and Customize Tabs are NOT cluttering the top AppBar directly
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.dashboard_customize_rounded),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.grid_view_rounded),
      ),
      findsNothing,
    );

    // Tapping the Sort/Filter pill opens the contextual Sort & View sheet
    await tester.tap(find.byKey(const ValueKey('library_sort_filter_pill')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('library_sort_and_view_sheet')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('library_sheet_layout_toggle')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('library_sheet_customize_tabs')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('library_sheet_select_all')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('library_sheet_settings')), findsOneWidget);

    // Tapping Select All inside the Sort & View sheet invokes selectAllSongs
    await tester.tap(find.byKey(const ValueKey('library_sheet_select_all')));
    await tester.pumpAndSettle();

    verify(() => cubit.selectAllSongs()).called(1);
  });

  testWidgets(
      'LibraryScreen loading state renders SkeletonList shimmer with zero CircularProgressIndicator',
      (tester) async {
    disableAnimations(tester);
    setSurface(tester);
    final cubit = stubLibraryCubit(const LibraryState(isLoading: true));

    await tester.pumpWidget(
      libraryHarness(
        libraryCubit: cubit,
        child: const LibraryScreen(),
      ),
    );
    await tester.pump();

    expect(find.byType(SkeletonList), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  for (final scale in const [1.3, 1.6]) {
    testWidgets(
        'LibraryScreen renders at ${scale}x text scale without overflow',
        (tester) async {
      disableAnimations(tester);
      setSurface(tester, size: const Size(390, 844));
      final songs = [
        testSong(
          id: 1,
          title: 'Long Song Title For Text Scale Verification',
          artist: 'Artist Name',
          path: '/music/track1.flac',
        ),
        testSong(
          id: 2,
          title: 'Second Track In Library',
          artist: 'Another Artist',
        ),
      ];
      final cubit = stubLibraryCubit(LibraryState(songs: songs));

      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(
        libraryHarness(
          libraryCubit: cubit,
          child: const LibraryScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'FolderDetailScreen renders at ${scale}x text scale in portrait and split layout without overflow',
        (tester) async {
      disableAnimations(tester);
      final useCase = _FolderUseCases();
      final songs = [
        createTestSong(id: 1, title: 'Alpha Track', durationMs: 185000),
        createTestSong(id: 2, title: 'Beta Track', durationMs: 210000),
      ];
      when(() => useCase.watchFolderSongs(any()))
          .thenAnswer((_) => Stream.value(Right(songs)));
      final libCubit = stubLibraryCubit(const LibraryState());

      for (final size in const [Size(390, 844), Size(900, 600)]) {
        setSurface(tester, size: size);
        await tester.pumpWidget(
          detailHarness(
            size: size,
            child: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(scale),
                disableAnimations: true,
              ),
              child: BlocProvider<LibraryCubit>.value(
                value: libCubit,
                child: FolderDetailScreen(
                  folder: const FolderItem(
                    path: '/storage/emulated/0/Music/Progressive Rock',
                    name: 'Progressive Rock Classics',
                    songCount: 2,
                    isExcluded: true,
                  ),
                  folderUseCases: useCase,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull,
            reason: 'FolderDetailScreen overflowed at $size @ ${scale}x');
      }
    });
  }
}
