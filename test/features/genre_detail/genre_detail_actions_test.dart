// GenreDetailScreen action coverage: the shuffle button (as opposed to the
// play-all path already covered) and the per-track overflow that opens
// SongInfoSheet.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/core/widgets/song_tile.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/genre_item.dart';
import 'package:pulsr/domain/usecases/get_genres_usecase.dart';
import 'package:pulsr/features/genre_detail/presentation/genre_detail_screen.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/detail_screen_harness.dart';
import '../../helpers/test_song_factory.dart';

class _Genres extends Mock implements GetGenresUseCase {}

const _genre = GenreItem(name: 'Rock', songCount: 2);

SongsTableData _song(int id, String title) =>
    createTestSong(id: id, title: title, genre: 'Rock');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Genres useCase;

  setUpAll(() {
    registerFallbackValue(createTestSong());
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'pulsr_hint_song_tile_swipe': true,
    });
    useCase = _Genres();
  });

  Future<void> pump(
    WidgetTester tester,
    Stream<Result<List<SongsTableData>>> stream, {
    PlayerCubit? playerCubit,
  }) async {
    when(() => useCase.watchGenreSongs(any())).thenAnswer((_) => stream);
    await tester.pumpWidget(detailHarness(
      playerCubit: playerCubit,
      child: GenreDetailScreen(genreItem: _genre, getGenresUseCase: useCase),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('the shuffle button starts a shuffled queue', (tester) async {
    final player = stubPlayerCubit();
    when(() => player.playSong(any(), queue: any(named: 'queue')))
        .thenAnswer((_) async {});

    await pump(
      tester,
      Stream.value(Right([_song(1, 'Alpha'), _song(2, 'Beta')])),
      playerCubit: player,
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Shuffle'));
    await tester.pump();

    verify(() => player.playSong(any(), queue: any(named: 'queue'))).called(1);
  });

  testWidgets('the shuffle button is disabled without tracks', (tester) async {
    await pump(tester, Stream.value(const Right([])));

    final shuffle = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Shuffle'));
    expect(shuffle.onPressed, isNull);
  });

  testWidgets('each track wires an overflow callback for the info sheet',
      (tester) async {
    await pump(tester, Stream.value(Right([_song(1, 'Alpha')])));

    final tile = tester.widget<SongTile>(find.byType(SongTile));
    expect(tile.onMorePressed, isNotNull);
    expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);
  });
}

