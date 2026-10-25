// Reorder mode wiring for online playlists: selecting tracks and moving them
// together must persist the new video-id order in the offline cache.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/ytm_track.dart';
import 'package:pulsr/domain/usecases/playlist_usecases.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/playlist_detail/presentation/online_playlist_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/screen_harness.dart';
import '../../../helpers/test_song_factory.dart';

class _Playlists extends Mock implements PlaylistUseCases {}

class _YtmService extends Mock implements YtmService {}

const _tracks = [
  YtmTrack(
      videoId: 'v1',
      title: 'First Track',
      artist: 'Artist One',
      duration: Duration(minutes: 3)),
  YtmTrack(
      videoId: 'v2',
      title: 'Second Track',
      artist: 'Artist Two',
      duration: Duration(minutes: 4)),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Playlists useCases;
  late _YtmService ytm;

  setUpAll(() {
    registerFallbackValue(<String>[]);
    registerFallbackValue('');
    registerFallbackValue(createTestSong());
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'pulsr_hint_song_tile_swipe': true,
    });
    useCases = _Playlists();
    ytm = _YtmService();
    when(() => ytm.getPlaylistTracks(any(), limit: any(named: 'limit')))
        .thenAnswer((_) async => const <YtmTrack>[]);
    when(() => useCases.watchOnlinePlaylistTracks(any()))
        .thenAnswer((_) => const Stream.empty());
    when(() => useCases.getOnlinePlaylist(any()))
        .thenAnswer((_) async => const Right(null));
    when(() => useCases.getOnlinePlaylistTracks(any())).thenAnswer(
        (_) async => const Right<AppFailure, List<YtmTrack>>(_tracks));
    when(() => useCases.reorderOnlinePlaylistTracks(any(), any()))
        .thenAnswer((_) async => const Right<AppFailure, void>(null));
    getIt.registerSingleton<PlaylistUseCases>(useCases);
    getIt.registerSingleton<YtmService>(ytm);
  });

  tearDown(() async {
    await getIt.reset();
  });

  Future<void> pumpScreen(WidgetTester tester, {PlayerCubit? player}) async {
    useScreenSize(tester, const Size(800, 1600));
    await tester.pumpWidget(screenHarness(
      providers: [
        BlocProvider<PlayerCubit>.value(value: player ?? stubPlayerCubit()),
      ],
      child: const OnlinePlaylistDetailScreen(
        args: OnlinePlaylistDetailArgs(
          playlistId: 'PL1',
          title: 'Online Mix',
          initialTracks: _tracks,
          kind: OnlineLibraryKind.custom,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('moving a selected song to the top persists and plays it first',
      (tester) async {
    final player = stubPlayerCubit();
    when(() => player.playSong(any(), queue: any(named: 'queue')))
        .thenAnswer((_) async {});
    await pumpScreen(tester, player: player);

    await tester.tap(find.byIcon(Icons.swap_vert_rounded));
    await tester.pumpAndSettle();
    expect(
      find.text('Drag to reorder. Select tracks to move them in bulk.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Second Track'));
    await tester.pump();

    await tester.tap(find.text('Move to top'));
    await tester.pumpAndSettle();

    verify(() => useCases.reorderOnlinePlaylistTracks('PL1', ['v2', 'v1']))
        .called(1);

    // Leave reorder mode and start playback: the queue must follow the order
    // just set instead of the remote order.
    await tester.tap(find.text('Done').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play All'));
    await tester.pumpAndSettle();

    final queue = verify(
      () => player.playSong(any(), queue: captureAny(named: 'queue')),
    ).captured.single as List<SongsTableData>;
    expect(queue.map((song) => song.remoteId), ['v2', 'v1']);
  });

  testWidgets('renaming playlist updates title and persists through usecase',
      (tester) async {
    when(() => useCases.renameOnlinePlaylist(any(), any()))
        .thenAnswer((_) async => const Right<AppFailure, void>(null));

    await pumpScreen(tester);

    await tester.tap(find.byIcon(Icons.edit_rounded).first);
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNWidgets(2));
    await tester.enterText(
        find.byType(TextField).last, 'My New Holy Quran Playlist');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    verify(() => useCases.renameOnlinePlaylist(
        'PL1', 'My New Holy Quran Playlist')).called(1);
    expect(find.text('My New Holy Quran Playlist'), findsWidgets);
  });

  testWidgets(
      'moving track to specific position moves track and persists order',
      (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byIcon(Icons.swap_vert_rounded));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Second Track'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Move to position'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), '1');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    verify(() => useCases.reorderOnlinePlaylistTracks('PL1', ['v2', 'v1']))
        .called(1);
  });
}
