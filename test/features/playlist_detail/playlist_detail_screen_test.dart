// PlaylistDetailScreen widget + logic suite.
//
// Drives the real screen against stubbed PlaylistUseCases streams: the header
// and actions, the song list, empty state, the error/retry path, per-track
// removal, the overflow menu and the smart-playlist branch.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/core/widgets/song_tile.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/smart_playlist_criteria.dart';
import 'package:pulsr/domain/usecases/playlist_usecases.dart';
import 'package:pulsr/features/playlist_detail/presentation/playlist_detail_screen.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/detail_screen_harness.dart';
import '../../helpers/test_song_factory.dart';

class _Playlists extends Mock implements PlaylistUseCases {}

final _playlist = PlaylistsTableData(
  id: 1,
  name: 'My List',
  createdAt: DateTime(2024, 1, 1),
  updatedAt: DateTime(2024, 1, 2),
  isSmart: false,
);

final _smartCriteria = const SmartCriteria(
  rules: [
    SmartRule(
      field: SmartRuleField.playCount,
      operator: SmartOperator.greaterThan,
      value: '0',
    ),
  ],
);

final _smartPlaylist = PlaylistsTableData(
  id: 2,
  name: 'Hot Rotation',
  createdAt: DateTime(2024, 1, 1),
  updatedAt: DateTime(2024, 1, 2),
  isSmart: true,
  smartCriteria: _smartCriteria.toJsonString(),
);

SongsTableData _song(int id, String title) =>
    createTestSong(id: id, title: title);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Playlists useCase;

  setUpAll(() {
    registerFallbackValue(const SmartCriteria());
    registerFallbackValue(createTestSong());
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      // Pre-mark the song-tile swipe hint as seen so GestureHintOverlay does
      // not leave a pending auto-dismiss timer during the test.
      'pulsr_hint_song_tile_swipe': true,
    });
    useCase = _Playlists();
  });

  Widget build(
    Stream<Result<List<SongsTableData>>> Function() stream, {
    PlayerCubit? playerCubit,
  }) {
    when(() => useCase.watchPlaylistSongs(any())).thenAnswer((_) => stream());
    return detailHarness(
      playerCubit: playerCubit,
      child: PlaylistDetailScreen(
        playlist: _playlist,
        playlistUseCases: useCase,
      ),
    );
  }

  testWidgets('renders the playlist header and every track', (tester) async {
    await tester.pumpWidget(build(() => Stream.value(Right([
          _song(1, 'Alpha'),
          _song(2, 'Beta'),
        ]))));
    await tester.pumpAndSettle();

    expect(find.text('My List'), findsOneWidget);
    expect(find.byType(SongTile), findsNWidgets(2));
    expect(find.widgetWithText(FilledButton, 'Play All'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Shuffle'), findsOneWidget);
  });

  testWidgets('renders an empty state when the playlist has no tracks',
      (tester) async {
    await tester.pumpWidget(build(() => Stream.value(const Right([]))));
    await tester.pumpAndSettle();

    expect(find.text('No Tracks'), findsOneWidget);
    expect(find.text('No tracks in this playlist.'), findsOneWidget);
    expect(find.byType(SongTile), findsNothing);
  });

  testWidgets('renders an empty-but-usable scaffold while the stream is idle',
      (tester) async {
    await tester.pumpWidget(build(() => const Stream.empty()));
    await tester.pump();

    expect(find.byType(PlaylistDetailScreen), findsOneWidget);
    expect(find.byType(SongTile), findsNothing);
  });

  testWidgets('shows the error view and retries when the load fails',
      (tester) async {
    await tester.pumpWidget(
        build(() => Stream.value(const Left(DatabaseFailure('boom')))));
    await tester.pumpAndSettle();

    expect(find.text('Failed to load playlist.'), findsOneWidget);
    expect(find.text('boom'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    // Retry clears the memoized stream and resubscribes.
    verify(() => useCase.watchPlaylistSongs(1)).called(2);
  });

  testWidgets('tapping play-all forwards the queue to PlayerCubit',
      (tester) async {
    final player = stubPlayerCubit();
    when(() => player.playSong(any(), queue: any(named: 'queue')))
        .thenAnswer((_) async {});
    await tester.pumpWidget(build(
      () => Stream.value(Right([_song(1, 'Alpha'), _song(2, 'Beta')])),
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
      () => Stream.value(Right([_song(1, 'Alpha')])),
      playerCubit: player,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SongTile).first);
    await tester.pump();

    verify(() => player.playSong(any(), queue: any(named: 'queue'))).called(1);
  });

  testWidgets('removes a song from a non-smart playlist and offers undo',
      (tester) async {
    when(() => useCase.removeSongFromPlaylist(any(), any()))
        .thenAnswer((_) async => const Right(null));
    await tester.pumpWidget(build(() => Stream.value(Right([
          _song(7, 'Alpha'),
          _song(8, 'Beta'),
        ]))));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Remove').first);
    await tester.pumpAndSettle();

    verify(() => useCase.removeSongFromPlaylist(1, 7)).called(1);
    expect(find.textContaining('removed from'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);

    // Let the snack bar auto-dismiss so no timer is left pending.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('opens the overflow menu with export/share/delete actions',
      (tester) async {
    await tester.pumpWidget(
        build(() => Stream.value(Right([_song(1, 'Alpha')]))));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Manage Songs'), findsWidgets);
    expect(find.text('Export as M3U'), findsOneWidget);
    expect(find.text('Share Playlist'), findsOneWidget);
    expect(find.text('Delete Playlist'), findsOneWidget);
  });

  testWidgets('smart playlist uses the smart engine and hides remove actions',
      (tester) async {
    when(() => useCase.watchSmartPlaylistSongs(any()))
        .thenAnswer((_) => Stream.value([_song(1, 'Alpha')]));
    await tester.pumpWidget(detailHarness(
      child: PlaylistDetailScreen(
        playlist: _smartPlaylist,
        playlistUseCases: useCase,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(SongTile), findsOneWidget);
    expect(find.byTooltip('Edit'), findsOneWidget);
    expect(find.byTooltip('Remove'), findsNothing);
  });

  testWidgets('smart playlist empty state mentions the smart rules',
      (tester) async {
    when(() => useCase.watchSmartPlaylistSongs(any()))
        .thenAnswer((_) => Stream.value(const []));
    await tester.pumpWidget(detailHarness(
      child: PlaylistDetailScreen(
        playlist: _smartPlaylist,
        playlistUseCases: useCase,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('No Tracks'), findsOneWidget);
    expect(
      find.text('No tracks match the rules for this smart playlist.'),
      findsOneWidget,
    );
  });
}
