// ArtistDetailScreen widget + logic suite.
//
// Drives the real screen against stubbed GetArtistsUseCase streams: header
// rendering (name + track count), the horizontal album discography, the top
// tracks list, empty state and the per-section error/retry paths.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/core/services/artist_bio_service.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/song_tile.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/usecases/get_artists_usecase.dart';
import 'package:pulsr/features/artist_detail/presentation/artist_detail_screen.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/detail_screen_harness.dart';
import '../../helpers/test_song_factory.dart';

class _Artists extends Mock implements GetArtistsUseCase {}

/// Never performs a network call, so the widget tests stay deterministic and
/// the FutureBuilder resolves to the empty bio state.
class _FakeBioService extends ArtistBioService {
  _FakeBioService();

  @override
  Future<ArtistInfo?> getArtistInfo(String artistName) async => null;

  @override
  void dispose() {}
}

const _artist = ArtistsTableData(
  id: 7,
  name: 'Test Artist',
  songCount: 3,
  albumCount: 2,
);

const _albumA = AlbumsTableData(
  id: 10,
  title: 'First Album',
  artist: 'Test Artist',
  artistId: 7,
  songCount: 2,
);

const _albumB = AlbumsTableData(
  id: 11,
  title: 'Second Album',
  artist: 'Test Artist',
  artistId: 7,
  songCount: 1,
);

SongsTableData _song(int id, String title) =>
    createTestSong(id: id, title: title, artist: 'Test Artist');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Artists useCase;

  setUpAll(() {
    registerFallbackValue(createTestSong());
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      // Pre-mark the song-tile swipe hint as seen so GestureHintOverlay does
      // not leave a pending auto-dismiss timer during the test.
      'pulsr_hint_song_tile_swipe': true,
    });
    useCase = _Artists();
    if (getIt.isRegistered<ArtistBioService>()) {
      getIt.unregister<ArtistBioService>();
    }
    getIt.registerSingleton<ArtistBioService>(_FakeBioService());
  });

  tearDown(() async {
    await getIt.reset();
  });

  Widget build({
    required Stream<Result<List<AlbumsTableData>>> albums,
    required Stream<Result<List<SongsTableData>>> songs,
    PlayerCubit? playerCubit,
  }) {
    when(() => useCase.watchArtistAlbums(any())).thenAnswer((_) => albums);
    when(() => useCase.watchArtistSongs(any())).thenAnswer((_) => songs);
    return _wrap(
      playerCubit: playerCubit,
      child: ArtistDetailScreen(artist: _artist, getArtistsUseCase: useCase),
    );
  }

  testWidgets('renders artist name and track count in the header',
      (tester) async {
    await tester.pumpWidget(build(
      albums: Stream.value(const Right([])),
      songs: Stream.value(const Right([])),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Test Artist'), findsWidgets);
    expect(find.text('3 tracks'), findsOneWidget);
  });

  testWidgets('renders every top track as a SongTile', (tester) async {
    await tester.pumpWidget(build(
      albums: Stream.value(const Right([])),
      songs: Stream.value(Right([
        _song(1, 'Alpha'),
        _song(2, 'Beta'),
        _song(3, 'Gamma'),
      ])),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(SongTile), findsNWidgets(3));
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('TOP TRACKS'), findsOneWidget);
  });

  testWidgets('renders the album discography section', (tester) async {
    await tester.pumpWidget(build(
      albums: Stream.value(const Right([_albumA, _albumB])),
      songs: Stream.value(const Right([])),
    ));
    await tester.pumpAndSettle();

    expect(find.text('ALBUMS'), findsOneWidget);
    expect(find.text('First Album'), findsOneWidget);
    expect(find.text('Second Album'), findsOneWidget);
  });

  testWidgets('collapses the album section when the list is empty',
      (tester) async {
    await tester.pumpWidget(build(
      albums: Stream.value(const Right([])),
      songs: Stream.value(Right([_song(1, 'Alpha')])),
    ));
    await tester.pumpAndSettle();

    expect(find.text('ALBUMS'), findsNothing);
    expect(find.byType(SongTile), findsOneWidget);
  });

  testWidgets('renders the scaffold while both streams are pending',
      (tester) async {
    await tester.pumpWidget(build(
      albums: const Stream.empty(),
      songs: const Stream.empty(),
    ));
    await tester.pump();

    expect(find.byType(ArtistDetailScreen), findsOneWidget);
    expect(find.byType(SongTile), findsNothing);
  });

  testWidgets('shows the album error section and retries', (tester) async {
    final controller = StreamController<Result<List<AlbumsTableData>>>();
    await tester.pumpWidget(build(
      albums: controller.stream,
      songs: Stream.value(const Right([])),
    ));
    await tester.pump();
    controller.add(Left(const DatabaseFailure('boom')));
    await tester.pumpAndSettle();

    expect(find.text('Could not load albums.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await controller.close();
  });

  testWidgets('shows the top-tracks error section and retries', (tester) async {
    final controller = StreamController<Result<List<SongsTableData>>>();
    await tester.pumpWidget(build(
      albums: Stream.value(const Right([_albumA])),
      songs: controller.stream,
    ));
    await tester.pump();
    controller.add(Left(const DatabaseFailure('boom')));
    await tester.pumpAndSettle();

    expect(find.text('Could not load top tracks.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await controller.close();
  });

  testWidgets('reports the track count from the artist row', (tester) async {
    await tester.pumpWidget(build(
      albums: Stream.value(const Right([])),
      songs: Stream.value(Right([_song(1, 'Only')])),
    ));
    await tester.pumpAndSettle();

    // The header count comes from ArtistsTableData.songCount, not the list.
    expect(find.text('3 tracks'), findsOneWidget);
  });

  testWidgets('tapping a top track routes playback through PlayerCubit',
      (tester) async {
    final player = stubPlayerCubit();
    when(() => player.playSong(any(), queue: any(named: 'queue')))
        .thenAnswer((_) async {});
    await tester.pumpWidget(build(
      albums: Stream.value(const Right([])),
      songs: Stream.value(Right([_song(1, 'Alpha')])),
      playerCubit: player,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SongTile).first);
    await tester.pump();

    verify(() => player.playSong(any(), queue: any(named: 'queue'))).called(1);
  });

  testWidgets('tapping an album navigates to the album route',
      (tester) async {
    await tester.pumpWidget(build(
      albums: Stream.value(const Right([_albumA])),
      songs: Stream.value(const Right([])),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('First Album'));
    await tester.pumpAndSettle();

    expect(find.text('Album Page'), findsOneWidget);
  });

  testWidgets('shows the bio fallback when the service returns null',
      (tester) async {
    await tester.pumpWidget(build(
      albums: Stream.value(const Right([])),
      songs: Stream.value(const Right([])),
    ));
    await tester.pumpAndSettle();

    // A null ArtistInfo is classified as empty by AsyncStateBuilder, so the
    // bio card area collapses rather than erroring.
    expect(find.text('Bio unavailable'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Widget _wrap({required Widget child, PlayerCubit? playerCubit}) {
  final router = GoRouter(
    initialLocation: '/artist',
    routes: [
      GoRoute(path: '/artist', builder: (context, state) => child),
      GoRoute(
        path: '/album',
        builder: (context, state) => const Scaffold(body: Text('Album Page')),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(body: Text('Home')),
      ),
    ],
  );
  return MaterialApp.router(
    theme: AuraTheme.darkTheme,
    routerConfig: router,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, routedChild) {
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: BlocProvider<PlayerCubit>.value(
          value: playerCubit ?? stubPlayerCubit(),
          child: routedChild!,
        ),
      );
    },
  );
}
