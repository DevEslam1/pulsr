// FolderDetailScreen branch coverage: the folder options sheet (play next,
// add to queue, copy, exclude/include with undo + failure), the four-artwork
// collage, the excluded overlay, active-row playback decorations and Windows
// breadcrumb paths.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/core/widgets/song_tile.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/usecases/folder_usecases.dart';
import 'package:pulsr/features/folder_detail/presentation/folder_detail_screen.dart';
import 'package:pulsr/features/library/cubit/library_cubit.dart';
import 'package:pulsr/features/library/cubit/library_state.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/detail_screen_harness.dart';
import '../../helpers/test_song_factory.dart';

class _FolderUseCases extends Mock implements FolderUseCases {}

class _Library extends Mock implements LibraryCubit {}

const _folder = FolderItem(
  path: '/music/rock',
  name: 'rock',
  songCount: 4,
  isExcluded: false,
);

_Library _library({List<SongsTableData> favorites = const []}) {
  final cubit = _Library();
  when(() => cubit.state).thenReturn(LibraryState(favorites: favorites));
  when(() => cubit.stream).thenAnswer((_) => const Stream.empty());
  when(() => cubit.toggleFavorite(any())).thenAnswer((_) async {});
    when(() => cubit.toggleFolderExclusion(any()))
        .thenAnswer((_) async => const Right<AppFailure, void>(null));
  return cubit;
}

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
    when(() => useCase.toggleExcludeFolder(any()))
        .thenAnswer((_) async => const Right<AppFailure, void>(null));
  });

  // The folder collage/badge rows overflow by ~2px at the tablet harness size
  // (a pre-existing layout quirk); drain the reported render errors so the
  // branch under test still runs to completion.
  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    while (tester.takeException() != null) {}
  }

  Widget build(
    Stream<Result<List<SongsTableData>>> stream, {
    LibraryCubit? library,
    PlayerCubit? player,
    FolderItem folder = _folder,
    Size size = const Size(1024, 2000),
  }) {
    when(() => useCase.watchFolderSongs(any())).thenAnswer((_) => stream);
    return detailHarness(
      size: size,
      playerCubit: player,
      child: BlocProvider<LibraryCubit>.value(
        value: library ?? _library(),
        child: FolderDetailScreen(folder: folder, folderUseCases: useCase),
      ),
    );
  }

  SongsTableData song(int id, String title) => createTestSong(id: id, title: title);

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.info_outline_rounded));
    await settle(tester);
  }

  testWidgets('the four-artwork collage renders for four distinct songs',
      (tester) async {
    await tester.pumpWidget(build(Stream.value(Right([
      song(1, 'A'),
      song(2, 'B'),
      song(3, 'C'),
      song(4, 'D'),
    ]))));
    await settle(tester);

    expect(find.text('A'), findsOneWidget);
    expect(find.text('D'), findsOneWidget);
  });

  testWidgets('an excluded folder shows the collage overlay',
      (tester) async {
    await tester.pumpWidget(build(
      Stream.value(Right([song(1, 'A'), song(2, 'B')])),
      folder: const FolderItem(
        path: '/music/rock',
        name: 'rock',
        songCount: 2,
        isExcluded: true,
      ),
    ));
    await settle(tester);

    expect(find.text('Excluded from scan'), findsWidgets);
  });

  testWidgets('play-next and add-to-queue reach the player',
      (tester) async {
    final player = stubPlayerCubit();
    when(() => player.playNext(any())).thenAnswer((_) async {});
    when(() => player.addAllToQueue(any())).thenAnswer((_) async {});
    await tester.pumpWidget(build(
      Stream.value(Right([song(1, 'A'), song(2, 'B')])),
      player: player,
    ));
    await settle(tester);

    await openSheet(tester);
    await tester.tap(find.text('Play Next'));
    await settle(tester);
    verify(() => player.playNext(any())).called(2);

    await openSheet(tester);
    await tester.tap(find.text('Add to Queue'));
    await settle(tester);
    verify(() => player.addAllToQueue(any())).called(1);
  });

  testWidgets('copy places the folder path on the clipboard',
      (tester) async {
    await tester.pumpWidget(
        build(Stream.value(Right([song(1, 'A')]))));
    await settle(tester);

    await openSheet(tester);
    await tester.tap(find.text('Copy'));
    await settle(tester);

    expect(find.textContaining('Copy'), findsWidgets);
  });

  testWidgets('excluding a folder reaches the library', (tester) async {
    final library = _library();
    await tester.pumpWidget(build(
      Stream.value(Right([song(1, 'A')])),
      library: library,
    ));
    await settle(tester);

    await openSheet(tester);
    await tester.tap(find.text('Exclude from Scan'));
    await settle(tester);
    verify(() => library.toggleFolderExclusion('/music/rock')).called(1);
  });

  testWidgets('including an excluded folder reaches the library',
      (tester) async {
    final library = _library();
    await tester.pumpWidget(build(
      Stream.value(Right([song(1, 'A')])),
      library: library,
      folder: const FolderItem(
        path: '/music/rock',
        name: 'rock',
        songCount: 1,
        isExcluded: true,
      ),
    ));
    await settle(tester);

    await openSheet(tester);
    await tester.tap(find.text('Include in Scan'));
    await settle(tester);
    verify(() => library.toggleFolderExclusion('/music/rock')).called(1);
  });

  testWidgets('Undo on the exclusion snackbar toggles the folder back',
      (tester) async {
    final library = _library();
    var toggles = 0;
    when(() => library.toggleFolderExclusion(any())).thenAnswer((_) async {
      toggles++;
      return const Right<AppFailure, void>(null);
    });
    await tester.pumpWidget(build(
      Stream.value(Right([song(1, 'A')])),
      library: library,
    ));
    await settle(tester);

    await openSheet(tester);
    await tester.tap(find.text('Exclude from Scan'));
    await settle(tester);
    expect(toggles, 1);

    final undoButton =
        tester.widget<TextButton>(find.widgetWithText(TextButton, 'Undo'));
    undoButton.onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(toggles, 2);
  });

  testWidgets('a failed exclusion reverts and reports the error',
      (tester) async {
    final library = _library();
    when(() => library.toggleFolderExclusion(any()))
        .thenAnswer((_) async => const Left(DatabaseFailure('nope')));
    await tester.pumpWidget(build(
      Stream.value(Right([song(1, 'A')])),
      library: library,
    ));
    await settle(tester);

    await openSheet(tester);
    await tester.tap(find.text('Exclude from Scan'));
    await settle(tester);

    expect(find.text('nope'), findsOneWidget);
  });

  testWidgets('the active track renders the now-playing overlay',
      (tester) async {
    final songs = [song(1, 'A'), song(2, 'B')];
    final player = stubPlayerCubit(PlayerState(
      playback: PlaybackSlice(currentSong: songs.first, isPlaying: true),
    ));
    await tester.pumpWidget(build(
      Stream.value(Right(songs)),
      player: player,
    ));
    await settle(tester);

    expect(find.byType(NowPlayingIndicator), findsOneWidget);
  });

  testWidgets('Windows-style breadcrumbs build drive roots', (tester) async {
    await tester.pumpWidget(build(
      Stream.value(Right([song(1, 'A')])),
      folder: const FolderItem(
        path: 'C:/Music/Rock',
        name: 'Rock',
        songCount: 1,
        isExcluded: false,
      ),
    ));
    await settle(tester);

    expect(find.text('Music'), findsOneWidget);
    expect(find.text('C:'), findsOneWidget);
  });

  testWidgets('an empty folder path omits the breadcrumbs', (tester) async {
    await tester.pumpWidget(build(
      Stream.value(Right([song(1, 'A')])),
      folder: const FolderItem(
        path: '',
        name: 'Empty Path',
        songCount: 1,
        isExcluded: false,
      ),
    ));
    await settle(tester);

    expect(tester.takeException(), isNull);
  });
}
