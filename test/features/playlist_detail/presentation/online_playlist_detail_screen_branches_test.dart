// OnlinePlaylistDetailScreen branch coverage: account-details fetch (success,
// timeout, generic failure), the local save flow (success + failure), shuffle,
// download-all reporting, and the in-playlist search clear/no-match states.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/core/services/ytm_account_service.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/ytm_track.dart';
import 'package:pulsr/domain/usecases/playlist_usecases.dart';
import 'package:pulsr/features/library/cubit/library_cubit.dart';
import 'package:pulsr/features/library/cubit/library_state.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/playlist_detail/presentation/online_playlist_detail_screen.dart';
import 'package:pulsr/features/ytm_search/cubit/ytm_download_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/screen_harness.dart';
import '../../../helpers/test_song_factory.dart';

class _YtmService extends Mock implements YtmService {}

class _Account extends Mock implements YtmAccountService {}

class _Download extends Mock implements YtmDownloadCubit {}

class _Playlists extends Mock implements PlaylistUseCases {}

class _Library extends Mock implements LibraryCubit {}

const _tracks = [
  YtmTrack(
      videoId: 'v1',
      title: 'First Track',
      artist: 'Artist One',
      duration: Duration(minutes: 3)),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _YtmService ytm;
  late _Account account;
  late _Download download;
  late _Playlists playlists;
  late _Library library;

  setUpAll(() {
    registerFallbackValue('');
    registerFallbackValue(<SongsTableData>[]);
    registerFallbackValue(createTestSong());
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'pulsr_hint_song_tile_swipe': true,
    });
    ytm = _YtmService();
    account = _Account();
    download = _Download();
    playlists = _Playlists();
    library = _Library();
    when(() => ytm.getPlaylistTracks(any(), limit: any(named: 'limit')))
        .thenAnswer((_) async => const <YtmTrack>[]);
    when(() => library.state).thenReturn(const LibraryState());
    when(() => library.stream)
        .thenAnswer((_) => const Stream<LibraryState>.empty());
    when(() => library.importYtmTracksAsFavorites(any()))
        .thenAnswer((_) async => 0);
    when(() => playlists.createPlaylist(any()))
        .thenAnswer((_) async => const Right(9));
    when(() => playlists.addSongsToPlaylist(any(), any()))
        .thenAnswer((_) async => const Right<AppFailure, void>(null));
    when(() => download.downloadAllDetailed(any())).thenReturn(
        (queued: 1, skippedLocal: 1, alreadyActive: 0, capped: 1));
  });

  tearDown(() async {
    await getIt.reset();
  });

  Future<void> pump(
    WidgetTester tester, {
    List<YtmTrack>? initialTracks,
    String? title,
    PlayerCubit? player,
  }) async {
    useScreenSize(tester, const Size(800, 1600));
    await tester.pumpWidget(screenHarness(
      providers: [
        BlocProvider<PlayerCubit>.value(value: player ?? stubPlayerCubit()),
        BlocProvider<LibraryCubit>.value(value: library),
      ],
      child: OnlinePlaylistDetailScreen(
        args: OnlinePlaylistDetailArgs(
          playlistId: 'PL1',
          title: title,
          initialTracks: initialTracks,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('account details populate the title, author and tracks',
      (tester) async {
    when(() => account.fetchPlaylistDetails(any(),
            maxTracks: any(named: 'maxTracks')))
        .thenAnswer((_) async => YtmPlaylistDetails(
              id: 'PL1',
              title: 'Real Title',
              author: 'Real Author',
              tracks: _tracks,
            ));
    getIt.registerSingleton<YtmAccountService>(account);
    getIt.registerSingleton<YtmService>(ytm);

    await pump(tester, title: null);

    expect(find.text('Real Title'), findsWidgets);
    expect(find.text('Real Author'), findsWidgets);
  });

  testWidgets('a double timeout surfaces the offline error', (tester) async {
    when(() => account.fetchPlaylistDetails(any(),
            maxTracks: any(named: 'maxTracks')))
        .thenThrow(TimeoutException('slow'));
    when(() => ytm.getPlaylistTracks(any(), limit: any(named: 'limit')))
        .thenThrow(TimeoutException('slow'));
    getIt.registerSingleton<YtmAccountService>(account);
    getIt.registerSingleton<YtmService>(ytm);

    await pump(tester, title: 'Timed Out');

    expect(find.textContaining('Connection timed out'), findsOneWidget);
  });

  testWidgets('a generic fetch failure surfaces the load error',
      (tester) async {
    when(() => account.fetchPlaylistDetails(any(),
            maxTracks: any(named: 'maxTracks')))
        .thenAnswer((_) async => throw StateError('boom'));
    getIt.registerSingleton<YtmAccountService>(account);
    getIt.registerSingleton<YtmService>(ytm);

    await pump(tester, title: 'Broken');

    expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('shuffle plays a shuffled queue', (tester) async {
    final player = stubPlayerCubit();
    when(() => player.playSong(any(), queue: any(named: 'queue')))
        .thenAnswer((_) async {});

    await pump(tester, title: 'Mix', initialTracks: _tracks, player: player);
    await tester.tap(find.text('Shuffle'));
    await tester.pump();

    verify(() => player.playSong(any(), queue: any(named: 'queue'))).called(1);
  });

  testWidgets('download all reports queued, capped and skipped counts',
      (tester) async {
    getIt.registerSingleton<YtmDownloadCubit>(download);
    await pump(tester, title: 'Mix', initialTracks: _tracks);

    await tester.tap(find.text('Download All'));
    await tester.pumpAndSettle();

    expect(find.textContaining('beyond the batch limit'), findsWidgets);
    expect(find.textContaining('already on device'), findsWidgets);
  });

  testWidgets('save-to-pulsr creates a local playlist', (tester) async {
    getIt.registerSingleton<PlaylistUseCases>(playlists);
    await pump(tester, title: 'Saved Mix', initialTracks: _tracks);

    await tester.tap(find.text('Save to Pulsr'));
    await tester.pumpAndSettle();

    verify(() => library.importYtmTracksAsFavorites(any())).called(1);
    verify(() => playlists.createPlaylist('Saved Mix')).called(1);
    verify(() => playlists.addSongsToPlaylist(9, any())).called(1);
  });

  testWidgets('save-to-pulsr reports a create failure', (tester) async {
    when(() => playlists.createPlaylist(any()))
        .thenAnswer((_) async => const Left(DatabaseFailure('nope')));
    getIt.registerSingleton<PlaylistUseCases>(playlists);
    await pump(tester, title: 'Bad Mix', initialTracks: _tracks);

    await tester.tap(find.text('Save to Pulsr'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Save failed'), findsWidgets);
  });

  testWidgets('clearing the search restores every track', (tester) async {
    await pump(tester, title: 'Mix', initialTracks: _tracks);

    await tester.enterText(find.byType(TextField), 'First');
    await tester.pump();
    expect(find.byIcon(Icons.clear_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.clear_rounded));
    await tester.pump();

    expect(find.text('First Track'), findsOneWidget);
  });

  testWidgets('a search with no matches shows the empty hint',
      (tester) async {
    await pump(tester, title: 'Mix', initialTracks: _tracks);

    await tester.enterText(find.byType(TextField), 'zzzznomatch');
    await tester.pump();

    expect(find.textContaining('No songs match'), findsOneWidget);
  });
}
