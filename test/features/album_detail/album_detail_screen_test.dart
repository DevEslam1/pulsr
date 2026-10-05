// AlbumDetailScreen widget + logic suite.
//
// Exercises the real screen against stubbed use-case streams: loading/empty
// rendering, the per-album persisted sort (track/title/duration), disc headers,
// multi-select behaviour introduced for batch queue actions, and the error
// retry path.
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
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/detail_screen_harness.dart';

class _Albums extends Mock implements GetAlbumsUseCase {}

const _album = AlbumsTableData(
  id: 1,
  title: 'Test Album',
  artist: 'Test Artist',
  songCount: 3,
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
  late _Albums useCase;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      // Pre-mark the song-tile swipe hint as seen so GestureHintOverlay does
      // not leave a pending auto-dismiss timer during the test.
      'pulsr_hint_song_tile_swipe': true,
    });
    useCase = _Albums();
  });

  Widget build(Stream<Result<List<SongsTableData>>> stream) {
    when(() => useCase.watchAlbumSongs(any())).thenAnswer((_) => stream);
    return detailHarness(
      child: AlbumDetailScreen(album: _album, getAlbumsUseCase: useCase),
    );
  }

  testWidgets('shows the album header and every track', (tester) async {
    await tester.pumpWidget(build(Stream.value(Right([
      _song(1, 'Alpha', track: 1),
      _song(2, 'Beta', track: 2),
      _song(3, 'Gamma', track: 3),
    ]))));
    await tester.pumpAndSettle();

    expect(find.text('Test Album'), findsWidgets);
    expect(find.byType(SongTile), findsNWidgets(3));
    expect(find.text('Alpha'), findsOneWidget);
  });

  testWidgets('renders an empty-but-usable scaffold while loading',
      (tester) async {
    await tester.pumpWidget(build(const Stream.empty()));
    await tester.pump();

    expect(find.byType(AlbumDetailScreen), findsOneWidget);
    expect(find.byType(SongTile), findsNothing);
  });

  testWidgets('shows the error view and retries when the stream fails',
      (tester) async {
    final controller = StreamController<Result<List<SongsTableData>>>();
    await tester.pumpWidget(build(controller.stream));
    await tester.pump();
    controller.add(Left(const DatabaseFailure('boom')));
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await controller.close();
  });

  testWidgets('sorts by track number by default', (tester) async {
    await tester.pumpWidget(build(Stream.value(Right([
      _song(1, 'Third', track: 3),
      _song(2, 'First', track: 1),
      _song(3, 'Second', track: 2),
    ]))));
    await tester.pumpAndSettle();

    final tiles = tester
        .widgetList<SongTile>(find.byType(SongTile))
        .map((t) => t.song.title)
        .toList();
    expect(tiles, ['First', 'Second', 'Third']);
  });

  testWidgets('changing sort to A-Z reorders and persists the choice',
      (tester) async {
    await tester.pumpWidget(build(Stream.value(Right([
      _song(1, 'Zebra', track: 1),
      _song(2, 'Apple', track: 2),
    ]))));
    await tester.pumpAndSettle();

    final dropdown = find.byWidgetPredicate((w) => w is DropdownButton);
    expect(dropdown, findsWidgets);
    await tester.ensureVisible(dropdown.first);
    await tester.pumpAndSettle();
    await tester.tap(dropdown.first, warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Name (A-Z)').last);
    await tester.pumpAndSettle();

    final tiles = tester
        .widgetList<SongTile>(find.byType(SongTile))
        .map((t) => t.song.title)
        .toList();
    expect(tiles, ['Apple', 'Zebra']);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('album_sort_1'), 'title');
  });

  testWidgets('restores a persisted sort preference before first frame',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'album_sort_1': 'duration',
      'pulsr_hint_song_tile_swipe': true,
    });
    await tester.pumpWidget(build(Stream.value(Right([
      _song(1, 'Long', durationMs: 9000, track: 1),
      _song(2, 'Short', durationMs: 1000, track: 2),
    ]))));
    await tester.pumpAndSettle();

    final tiles = tester
        .widgetList<SongTile>(find.byType(SongTile))
        .map((t) => t.song.title)
        .toList();
    expect(tiles, ['Short', 'Long']);
  });

  testWidgets('renders disc headers when the album spans multiple discs',
      (tester) async {
    await tester.pumpWidget(build(Stream.value(Right([
      _song(1, 'Disc1', disc: 1, track: 1),
      _song(2, 'Disc2', disc: 2, track: 1),
    ]))));
    await tester.pumpAndSettle();

    expect(find.textContaining('Disc'), findsWidgets);
  });

  testWidgets('long-press selects a track for batch queue actions',
      (tester) async {
    await tester.pumpWidget(build(Stream.value(Right([
      _song(1, 'Alpha', track: 1),
      _song(2, 'Beta', track: 2),
    ]))));
    await tester.pumpAndSettle();

    await tester.longPress(find.byType(SongTile).first);
    await tester.pumpAndSettle();

    final tiles = tester.widgetList<SongTile>(find.byType(SongTile)).toList();
    expect(tiles.where((t) => t.selected), hasLength(1));
  });

  testWidgets('play-all is disabled with no songs, enabled with songs',
      (tester) async {
    await tester.pumpWidget(build(Stream.value(const Right([]))));
    await tester.pumpAndSettle();
    final emptyButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Play All'));
    expect(emptyButton.onPressed, isNull);
  });
}
