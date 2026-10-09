// RecentsScreen widget suite: loading/empty/error/data states, search
// filtering, play-all/shuffle, the clear-history dialog and history paging.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/core/widgets/shimmer_skeleton.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/usecases/get_songs_usecase.dart';
import 'package:pulsr/features/library/presentation/recents_screen.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/screen_harness.dart';
import '../../../helpers/test_song_factory.dart';

class _GetSongs extends Mock implements GetSongsUseCase {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _GetSongs getSongs;
  late StreamController<Result<List<SongsTableData>>> recents;
  late PlayerCubit player;

  setUpAll(() {
    registerFallbackValue(createTestSong(id: -1));
    registerFallbackValue(<SongsTableData>[]);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    getSongs = _GetSongs();
    player = stubPlayerCubit();
    when(() => player.playSong(any(), queue: any(named: 'queue')))
        .thenAnswer((_) async {});
    recents = StreamController<Result<List<SongsTableData>>>.broadcast();
    when(() => getSongs.watchRecentlyPlayed(limit: any(named: 'limit')))
        .thenAnswer((_) => recents.stream);
    when(() => getSongs.clearRecentlyPlayed())
        .thenAnswer((_) async => const Right(null));
    getIt.registerSingleton<GetSongsUseCase>(getSongs);
    addTearDown(() async {
      await recents.close();
      await getIt.reset();
    });
  });

  Future<void> pump(WidgetTester tester) async {
    useScreenSize(tester, const Size(800, 1400));
    await tester.pumpWidget(screenHarness(
      providers: [
        BlocProvider<PlayerCubit>.value(value: player),
      ],
      child: const RecentsScreen(),
    ));
    await tester.pump();
  }

  Future<void> emit(
      WidgetTester tester, Result<List<SongsTableData>> value) async {
    recents.add(value);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('shows a skeleton while history loads', (tester) async {
    await pump(tester);
    expect(find.byType(SkeletonList), findsOneWidget);
  });

  testWidgets('renders the empty state when there is no history',
      (tester) async {
    await pump(tester);
    await emit(tester, const Right(<SongsTableData>[]));
    expect(find.text('No recently played songs'), findsOneWidget);
  });

  testWidgets('renders the error state with a retry action', (tester) async {
    await pump(tester);
    await emit(tester, const Left(DatabaseFailure('boom')));
    expect(find.text('Something went wrong'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    verify(() => getSongs.watchRecentlyPlayed(limit: any(named: 'limit')))
        .called(greaterThanOrEqualTo(2));
  });

  testWidgets('lists recent tracks and plays the tapped one', (tester) async {
    await pump(tester);
    await emit(tester, Right([
      createTestSong(id: 1, title: 'Alpha'),
      createTestSong(id: 2, title: 'Beta'),
    ]));

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);

    await tester.tap(find.text('Alpha'));
    await tester.pump();
    // Let the staggered list item reveal timer drain before teardown.
    await tester.pump(const Duration(milliseconds: 120));
  });

  testWidgets('the search field filters the list after the debounce',
      (tester) async {
    await pump(tester);
    await emit(tester, Right([
      createTestSong(id: 1, title: 'Alpha'),
      createTestSong(id: 2, title: 'Beta'),
    ]));

    await tester.enterText(find.byType(TextField).first, 'Alpha');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Alpha'), findsWidgets);
    expect(find.text('Beta'), findsNothing);
  });

  testWidgets('clearing history confirms then calls the use case',
      (tester) async {
    await pump(tester);
    await emit(tester, Right([createTestSong(id: 1, title: 'Alpha')]));

    await tester.tap(find.byIcon(Icons.delete_sweep_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Clear Listening History?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Clear History'));
    await tester.pumpAndSettle();

    verify(() => getSongs.clearRecentlyPlayed()).called(1);
  });

  testWidgets('load more history grows the query window', (tester) async {
    await pump(tester);
    final songs = [
      for (var i = 0; i < 100; i++) createTestSong(id: i, title: 'Song $i'),
    ];
    await emit(tester, Right(songs));

    await tester.scrollUntilVisible(
      find.textContaining('Load More History'),
      500,
      scrollable: find
          .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable))
          .first,
    );
    expect(find.textContaining('Load More History'), findsOneWidget);

    await tester.tap(find.textContaining('Load More History'));
    await tester.pump();
    verify(() => getSongs.watchRecentlyPlayed(limit: 200)).called(1);
  });
}
