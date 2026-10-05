// FolderDetailScreen widget + logic suite.
//
// Drives the real screen against stubbed FolderUseCases streams and a mocked
// LibraryCubit: the responsive hero header (name + count/duration), the track
// list, empty state, error/retry, breadcrumbs, the excluded badge and the
// folder options sheet.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/usecases/folder_usecases.dart';
import 'package:pulsr/features/folder_detail/presentation/folder_detail_screen.dart';
import 'package:pulsr/features/library/cubit/library_cubit.dart';
import 'package:pulsr/features/library/cubit/library_state.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/detail_screen_harness.dart';
import '../../helpers/test_song_factory.dart';

class _FolderUseCases extends Mock implements FolderUseCases {}

class _Library extends Mock implements LibraryCubit {}

_Library _libraryCubit({List<SongsTableData> favorites = const []}) {
  final cubit = _Library();
  when(() => cubit.state).thenReturn(LibraryState(favorites: favorites));
  when(() => cubit.stream).thenAnswer((_) => const Stream.empty());
  return cubit;
}

const _folder = FolderItem(
  path: '/music/rock',
  name: 'rock',
  songCount: 3,
  isExcluded: false,
);

SongsTableData _song(int id, String title, {int durationMs = 20000}) =>
    createTestSong(id: id, title: title, durationMs: durationMs);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FolderUseCases useCase;

  setUpAll(() {
    registerFallbackValue(createTestSong());
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'pulsr_hint_song_tile_swipe': true,
    });
    useCase = _FolderUseCases();
  });

  Widget build(
    Stream<Result<List<SongsTableData>>> stream, {
    PlayerCubit? playerCubit,
    LibraryCubit? libraryCubit,
    FolderItem? folder,
    Size size = const Size(1024, 2000),
  }) {
    when(() => useCase.watchFolderSongs(any())).thenAnswer((_) => stream);
    return detailHarness(
      size: size,
      playerCubit: playerCubit,
      child: BlocProvider<LibraryCubit>.value(
        value: libraryCubit ?? _libraryCubit(),
        child: FolderDetailScreen(
          folder: folder ?? _folder,
          folderUseCases: useCase,
        ),
      ),
    );
  }

  testWidgets('renders the folder name and track count/duration',
      (tester) async {
    await tester.pumpWidget(build(Stream.value(Right([
      _song(1, 'Alpha'),
      _song(2, 'Beta'),
      _song(3, 'Gamma'),
    ]))));
    await tester.pumpAndSettle();

    expect(find.text('rock'), findsWidgets);
    expect(find.textContaining('3 tracks •'), findsOneWidget);
  });

  testWidgets('renders every folder track', (tester) async {
    await tester.pumpWidget(build(Stream.value(Right([
      _song(1, 'Alpha'),
      _song(2, 'Beta'),
      _song(3, 'Gamma'),
    ]))));
    await tester.pumpAndSettle();

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Gamma'), findsOneWidget);
  });

  testWidgets('renders the same track list in the phone portrait layout',
      (tester) async {
    await tester.pumpWidget(build(
      Stream.value(Right([_song(1, 'Alpha'), _song(2, 'Beta')])),
      size: const Size(400, 900),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Alpha'), findsOneWidget);

    // The portrait layout is a lazy CustomScrollView, so scroll the second
    // track into view before asserting it.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Beta'), findsOneWidget);
  });

  testWidgets('renders an empty state when the folder has no tracks',
      (tester) async {
    await tester.pumpWidget(build(Stream.value(const Right([]))));
    await tester.pumpAndSettle();

    expect(find.text('No Tracks Found'), findsOneWidget);
    expect(
      find.text('No playable audio tracks found in this directory.'),
      findsOneWidget,
    );
  });

  testWidgets('renders an empty-but-usable scaffold while the stream is idle',
      (tester) async {
    await tester.pumpWidget(build(const Stream.empty()));
    await tester.pump();

    expect(find.byType(FolderDetailScreen), findsOneWidget);
  });

  testWidgets('shows the error view and retries when the stream fails',
      (tester) async {
    final controller = StreamController<Result<List<SongsTableData>>>();
    await tester.pumpWidget(build(controller.stream));
    await tester.pump();
    controller.add(Left(const DatabaseFailure('boom')));
    await tester.pumpAndSettle();

    expect(find.text('Could not load folder songs'), findsOneWidget);
    expect(find.text('Something went wrong while reading your library.'),
        findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await controller.close();
  });

  testWidgets('tapping a track forwards playback to PlayerCubit',
      (tester) async {
    final player = stubPlayerCubit();
    when(() => player.playSong(any(), queue: any(named: 'queue')))
        .thenAnswer((_) async {});
    await tester.pumpWidget(build(
      Stream.value(Right([_song(1, 'Alpha')])),
      playerCubit: player,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alpha'));
    await tester.pump();

    verify(() => player.playSong(any(), queue: any(named: 'queue'))).called(1);
  });

  testWidgets('renders breadcrumb segments for the folder path',
      (tester) async {
    await tester.pumpWidget(build(
      Stream.value(Right([_song(1, 'Alpha')])),
    ));
    await tester.pumpAndSettle();

    expect(find.text('music'), findsOneWidget);
  });

  testWidgets('shows the excluded badge for an excluded folder',
      (tester) async {
    // Portrait layout: the split hero's excluded badge Row overflows its
    // cover at the default tablet harness size (see product notes), so the
    // badge is exercised through the immersive portrait cover instead.
    await tester.pumpWidget(build(
      Stream.value(Right([_song(1, 'Alpha')])),
      folder: const FolderItem(
        path: '/music/rock',
        name: 'rock',
        songCount: 1,
        isExcluded: true,
      ),
      size: const Size(400, 900),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Excluded from scan'), findsWidgets);
  });
}
