// Additional coverage for lib/features/album_detail/presentation/album_detail_screen.dart
//
// Complements album_detail_screen_test.dart with Play All / Shuffle actions,
// the duration sort and the album-level queue popup menu (add, play next,
// clear selection).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/core/widgets/song_tile.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/usecases/get_albums_usecase.dart';
import 'package:pulsr/features/album_detail/presentation/album_detail_screen.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/detail_screen_harness.dart';
import '../../helpers/test_song_factory.dart';

class _Albums extends Mock implements GetAlbumsUseCase {}

const _album = AlbumsTableData(
  id: 1,
  title: 'Test Album',
  artist: 'Test Artist',
  songCount: 2,
);

SongsTableData _song(
  int id,
  String title, {
  int durationMs = 1000,
  int? disc,
  int? track,
}) =>
    SongsTableData(
      id: id,
      title: title,
      artist: 'Test Artist',
      album: 'Test Album',
      durationMs: durationMs,
      path: '/path/$id.mp3',
      dateAdded: 0,
      isFavorite: false,
      isMissing: false,
      isDownloaded: false,
      playCount: 0,
      lastPositionMs: 0,
      source: 'local',
      discNumber: disc,
      trackNumber: track,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('en'));

  late _Albums useCase;

  setUpAll(() {
    registerFallbackValue(createTestSong());
    registerFallbackValue(<SongsTableData>[]);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'pulsr_hint_song_tile_swipe': true,
    });
    useCase = _Albums();
  });

  Widget build(
    Stream<Result<List<SongsTableData>>> stream, {
    PlayerCubit? playerCubit,
  }) {
    when(() => useCase.watchAlbumSongs(any())).thenAnswer((_) => stream);
    return detailHarness(
      playerCubit: playerCubit,
      child: AlbumDetailScreen(album: _album, getAlbumsUseCase: useCase),
    );
  }

  MockPlayerCubit stubPlayer() {
    final player = MockPlayerCubit();
    when(() => player.state).thenReturn(const PlayerState());
    when(() => player.stream)
        .thenAnswer((_) => const Stream<PlayerState>.empty());
    when(() => player.playSong(any(), queue: any(named: 'queue')))
        .thenAnswer((_) async {});
    when(() => player.addAllToQueue(any())).thenAnswer((_) async {});
    when(() => player.playNext(any())).thenAnswer((_) async {});
    return player;
  }

  testWidgets('Play All forwards the whole album to the player',
      (tester) async {
    final player = stubPlayer();
    await tester.pumpWidget(build(
      Stream.value(Right([_song(1, 'Alpha'), _song(2, 'Beta')])),
      playerCubit: player,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.playAll));
    await tester.pump();

    verify(() => player.playSong(any(), queue: any(named: 'queue'))).called(1);
  });

  testWidgets('Shuffle forwards a shuffled album to the player',
      (tester) async {
    final player = stubPlayer();
    await tester.pumpWidget(build(
      Stream.value(Right([_song(1, 'Alpha'), _song(2, 'Beta')])),
      playerCubit: player,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.shuffle));
    await tester.pump();

    verify(() => player.playSong(any(), queue: any(named: 'queue'))).called(1);
  });

  testWidgets('sorting by duration reorders the tracks', (tester) async {
    await tester.pumpWidget(build(Stream.value(Right([
      _song(1, 'Long', durationMs: 9000, track: 1),
      _song(2, 'Short', durationMs: 1000, track: 2),
    ]))));
    await tester.pumpAndSettle();

    final dropdown = find.byWidgetPredicate((w) => w is DropdownButton);
    await tester.ensureVisible(dropdown.first);
    await tester.pumpAndSettle();
    await tester.tap(dropdown.first, warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.sortDuration).last);
    await tester.pumpAndSettle();

    final titles = tester
        .widgetList<SongTile>(find.byType(SongTile))
        .map((t) => t.song.title)
        .toList();
    expect(titles, ['Short', 'Long']);
  });

  testWidgets('queue menu adds every track to the queue', (tester) async {
    final player = stubPlayer();
    await tester.pumpWidget(build(
      Stream.value(Right([_song(1, 'Alpha'), _song(2, 'Beta')])),
      playerCubit: player,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_horiz_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.addToQueue).last);
    await tester.pumpAndSettle();

    verify(() => player.addAllToQueue(any())).called(1);
  });

  testWidgets('queue menu plays tracks next', (tester) async {
    final player = stubPlayer();
    await tester.pumpWidget(build(
      Stream.value(Right([_song(1, 'Alpha'), _song(2, 'Beta')])),
      playerCubit: player,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_horiz_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.playNext).last);
    await tester.pumpAndSettle();

    verify(() => player.playNext(any())).called(2);
  });

  testWidgets('queue menu clears an active multi-selection', (tester) async {
    await tester.pumpWidget(build(Stream.value(Right([
      _song(1, 'Alpha', track: 1),
      _song(2, 'Beta', track: 2),
    ]))));
    await tester.pumpAndSettle();

    await tester.longPress(find.byType(SongTile).first);
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<SongTile>(find.byType(SongTile))
          .where((t) => t.selected),
      hasLength(1),
    );

    await tester.tap(find.byIcon(Icons.more_horiz_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining(l10n.clear).last);
    await tester.pumpAndSettle();

    expect(
      tester
          .widgetList<SongTile>(find.byType(SongTile))
          .where((t) => t.selected),
      isEmpty,
    );
  });
}
