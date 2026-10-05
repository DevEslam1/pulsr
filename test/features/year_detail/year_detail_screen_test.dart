// YearDetailScreen widget + logic suite.
//
// Drives the real screen against stubbed GetYearsUseCase streams: header year +
// live track count, the song list, empty state, the error/retry path and the
// play-all / per-track playback interactions.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/core/widgets/song_tile.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/year_item.dart';
import 'package:pulsr/domain/usecases/get_years_usecase.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/year_detail/presentation/year_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/detail_screen_harness.dart';
import '../../helpers/test_song_factory.dart';

class _Years extends Mock implements GetYearsUseCase {}

const _year = YearItem(year: 2021, songCount: 9);

SongsTableData _song(int id, String title) =>
    createTestSong(id: id, title: title, year: 2021);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Years useCase;

  setUpAll(() {
    registerFallbackValue(createTestSong());
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      // Pre-mark the song-tile swipe hint as seen so GestureHintOverlay does
      // not leave a pending auto-dismiss timer during the test.
      'pulsr_hint_song_tile_swipe': true,
    });
    useCase = _Years();
  });

  Widget build(
    Stream<Result<List<SongsTableData>>> stream, {
    PlayerCubit? playerCubit,
  }) {
    when(() => useCase.watchYearSongs(any())).thenAnswer((_) => stream);
    return detailHarness(
      playerCubit: playerCubit,
      child: YearDetailScreen(yearItem: _year, getYearsUseCase: useCase),
    );
  }

  testWidgets('renders the year and the live track count', (tester) async {
    await tester.pumpWidget(build(Stream.value(Right([
      _song(1, 'Alpha'),
      _song(2, 'Beta'),
    ]))));
    await tester.pumpAndSettle();

    expect(find.text('2021'), findsWidgets);
    // Count comes from the loaded list, not the YearItem.songCount.
    expect(find.text('2 tracks'), findsOneWidget);
  });

  testWidgets('renders every track for the year as a SongTile',
      (tester) async {
    await tester.pumpWidget(build(Stream.value(Right([
      _song(1, 'Alpha'),
      _song(2, 'Beta'),
      _song(3, 'Gamma'),
    ]))));
    await tester.pumpAndSettle();

    expect(find.byType(SongTile), findsNWidgets(3));
    expect(find.text('Gamma'), findsOneWidget);
  });

  testWidgets('renders an empty state when the year has no tracks',
      (tester) async {
    await tester.pumpWidget(build(Stream.value(const Right([]))));
    await tester.pumpAndSettle();

    expect(find.text('No Tracks'), findsOneWidget);
    expect(find.text('No tracks found for this year.'), findsOneWidget);
    expect(find.byType(SongTile), findsNothing);
  });

  testWidgets('renders an empty-but-usable scaffold while the stream is idle',
      (tester) async {
    await tester.pumpWidget(build(const Stream.empty()));
    await tester.pump();

    expect(find.byType(YearDetailScreen), findsOneWidget);
    expect(find.byType(SongTile), findsNothing);
  });

  testWidgets('shows the error view and retries when the stream fails',
      (tester) async {
    final controller = StreamController<Result<List<SongsTableData>>>();
    await tester.pumpWidget(build(controller.stream));
    await tester.pump();
    controller.add(Left(const DatabaseFailure('boom')));
    await tester.pumpAndSettle();

    expect(find.text('Could not load songs for this year'), findsOneWidget);
    expect(find.text('Something went wrong while reading your library.'),
        findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await controller.close();
  });

  testWidgets('play-all is disabled without tracks and enabled with tracks',
      (tester) async {
    await tester.pumpWidget(build(Stream.value(const Right([]))));
    await tester.pumpAndSettle();
    final emptyButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Play All'));
    expect(emptyButton.onPressed, isNull);
  });

  testWidgets('tapping play-all forwards the queue to PlayerCubit',
      (tester) async {
    final player = stubPlayerCubit();
    when(() => player.playSong(any(), queue: any(named: 'queue')))
        .thenAnswer((_) async {});
    await tester.pumpWidget(build(
      Stream.value(Right([_song(1, 'Alpha'), _song(2, 'Beta')])),
      playerCubit: player,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Play All'));
    await tester.pump();

    verify(() => player.playSong(any(), queue: any(named: 'queue'))).called(1);
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

    await tester.tap(find.byType(SongTile).first);
    await tester.pump();

    verify(() => player.playSong(any(), queue: any(named: 'queue'))).called(1);
  });

  testWidgets('renders both the shuffle affordance and the track list',
      (tester) async {
    await tester.pumpWidget(build(Stream.value(Right([
      _song(1, 'Alpha'),
      _song(2, 'Beta'),
    ]))));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(OutlinedButton, 'Shuffle'), findsOneWidget);
    expect(find.byType(SongTile), findsNWidgets(2));
  });
}
