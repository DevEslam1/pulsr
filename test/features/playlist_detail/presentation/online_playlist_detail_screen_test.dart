// OnlinePlaylistDetailScreen widget suite.
//
// Uses pre-supplied initial tracks so no network is needed: the background
// refresh is stubbed to return nothing. Covers the populated hero + list, the
// in-playlist search, the empty/error state and Play All forwarding.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/core/widgets/song_tile.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/playlist_detail/presentation/online_playlist_detail_screen.dart';
import 'package:pulsr/domain/models/ytm_track.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/screen_harness.dart';
import '../../../helpers/test_song_factory.dart';

class _YtmService extends Mock implements YtmService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _YtmService ytm;

  const tracks = [
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

  setUpAll(() {
    registerFallbackValue('');
    registerFallbackValue(createTestSong());
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      // Pre-mark the swipe hint seen so no auto-dismiss timer leaks.
      'pulsr_hint_song_tile_swipe': true,
    });
    ytm = _YtmService();
    when(() => ytm.getPlaylistTracks(any(), limit: any(named: 'limit')))
        .thenAnswer((_) async => const <YtmTrack>[]);
    getIt.registerSingleton<YtmService>(ytm);
    addTearDown(() async {
      await getIt.reset();
    });
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    required String playlistId,
    String? title,
    List<YtmTrack>? initialTracks,
    PlayerCubit? player,
  }) async {
    useScreenSize(tester, const Size(800, 1600));
    await tester.pumpWidget(screenHarness(
      providers: [
        BlocProvider<PlayerCubit>.value(value: player ?? stubPlayerCubit()),
      ],
      child: OnlinePlaylistDetailScreen(
        args: OnlinePlaylistDetailArgs(
          playlistId: playlistId,
          title: title,
          initialTracks: initialTracks,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('renders the hero, actions and every initial track',
      (tester) async {
    await pumpScreen(
      tester,
      playlistId: 'PL1',
      title: 'Chill Mix',
      initialTracks: tracks,
    );

    expect(find.text('Chill Mix'), findsWidgets);
    expect(find.byType(SongTile), findsNWidgets(2));
    expect(find.text('Play All'), findsOneWidget);
    expect(find.text('Shuffle'), findsOneWidget);
    expect(find.text('Download All'), findsOneWidget);
    expect(find.text('Save to Pulsr'), findsOneWidget);
  });

  testWidgets('the in-playlist search filters the tracks', (tester) async {
    await pumpScreen(
      tester,
      playlistId: 'PL1',
      title: 'Chill Mix',
      initialTracks: tracks,
    );
    expect(find.byType(SongTile), findsNWidgets(2));

    await tester.enterText(find.byType(TextField), 'Second');
    await tester.pump();

    expect(find.byType(SongTile), findsOneWidget);
    expect(find.text('Second Track'), findsOneWidget);
  });

  testWidgets('shows the error state with retry when the fetch yields nothing',
      (tester) async {
    await pumpScreen(tester, playlistId: 'PL1', title: 'Empty Mix');

    expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('Play All forwards the queue to PlayerCubit', (tester) async {
    final player = stubPlayerCubit();
    when(() => player.playSong(any(), queue: any(named: 'queue')))
        .thenAnswer((_) async {});

    await pumpScreen(
      tester,
      playlistId: 'PL1',
      title: 'Chill Mix',
      initialTracks: tracks,
      player: player,
    );

    await tester.tap(find.text('Play All'));
    await tester.pump();

    verify(() => player.playSong(any(), queue: any(named: 'queue'))).called(1);
  });
}
