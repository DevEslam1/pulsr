// PlaylistCubit online-fetch coalescing and liked-songs empty-state suite.
//
// The live YTM entry points are compile-time gated in this build, so these
// tests drive the @visibleForTesting wrappers that bypass the flag.
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/network/connectivity_guard.dart';
import 'package:pulsr/core/services/ytm_account_service.dart';
import 'package:pulsr/domain/models/ytm_track.dart';
import 'package:pulsr/domain/usecases/playlist_usecases.dart';
import 'package:pulsr/features/playlists/cubit/playlist_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PlaylistUseCases extends Mock implements PlaylistUseCases {}

class _Account extends Mock implements YtmAccountService {}

class _Connectivity extends Mock implements Connectivity {}

const _track = YtmTrack(
    videoId: 'v1', title: 'T', artist: 'A', duration: Duration(seconds: 1));

const _details = YtmPlaylistDetails(
  id: 'PL1',
  title: 'Mix',
  author: 'A',
  tracks: [_track],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _PlaylistUseCases useCases;
  late _Account account;

  setUpAll(() {
    registerFallbackValue('');
    registerFallbackValue(<int>[]);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({'smart_playlists_seeded': true});
    useCases = _PlaylistUseCases();
    when(() => useCases.watchPlaylists())
        .thenAnswer((_) => const Stream.empty());
    when(() => useCases.watchPlaylistSongs(any()))
        .thenAnswer((_) => const Stream.empty());

    account = _Account();
    when(() => account.isLoggedIn).thenReturn(true);
    getIt.registerSingleton<YtmAccountService>(account);

    final connectivity = _Connectivity();
    when(() => connectivity.checkConnectivity())
        .thenAnswer((_) async => [ConnectivityResult.wifi]);
    ConnectivityGuard.setMockConnectivity(connectivity);
  });

  tearDown(() async {
    await getIt.reset();
  });

  PlaylistCubit create() => PlaylistCubit(playlistUseCases: useCases);

  test('an empty liked-songs result is a done state, not an error', () async {
    when(() => account.fetchLikedSongs())
        .thenAnswer((_) async => const <YtmTrack>[]);
    final cubit = create();

    await cubit.fetchLikedSongsPlaylistForTesting();

    expect(cubit.onlineState.likedStatus, YtmFetchStatus.done);
    expect(cubit.onlineState.likedError, isNull);
    expect(cubit.onlineState.likedTracks, isEmpty);
    await cubit.close();
  });

  test('concurrent auto-fetch calls coalesce into a single run', () async {
    final completer = Completer<List<YtmTrack>>();
    when(() => account.fetchLikedSongs()).thenAnswer((_) => completer.future);
    when(() => account.fetchAccountPlaylists())
        .thenAnswer((_) async => const <YtmAccountPlaylist>[]);
    final cubit = create();

    final first = cubit.autoFetchOnlineLibraryForTesting(force: true);
    final second = cubit.autoFetchOnlineLibraryForTesting(force: true);
    completer.complete(const [_track]);
    await Future.wait([first, second]);

    verify(() => account.fetchLikedSongs()).called(1);
    await cubit.close();
  });

  test('rapid identical custom-playlist submits fetch once', () async {
    final completer = Completer<YtmPlaylistDetails?>();
    when(() => account.fetchPlaylistDetails(any(),
            maxTracks: any(named: 'maxTracks')))
        .thenAnswer((_) => completer.future);
    final cubit = create();

    final first = cubit.fetchOnlinePlaylistByUrlForTesting('PL1');
    final second = cubit.fetchOnlinePlaylistByUrlForTesting('PL1');
    completer.complete(_details);
    await Future.wait([first, second]);

    verify(() => account.fetchPlaylistDetails('PL1',
        maxTracks: any(named: 'maxTracks'))).called(1);
    expect(cubit.onlineState.customPlaylists, hasLength(1));
    await cubit.close();
  });

  test('a custom playlist restored mid-fetch is not duplicated', () async {
    final completer = Completer<YtmPlaylistDetails?>();
    when(() => account.fetchPlaylistDetails(any(),
            maxTracks: any(named: 'maxTracks')))
        .thenAnswer((_) => completer.future);
    final cubit = create();

    final fetch = cubit.fetchOnlinePlaylistByUrlForTesting('PL1');
    cubit.restoreCustomPlaylist(const OnlinePlaylistEntry(
        id: 'PL1', title: 'Existing', uploader: 'A', tracks: []));
    completer.complete(_details);
    await fetch;

    final matches =
        cubit.onlineState.customPlaylists.where((p) => p.id == 'PL1');
    expect(matches, hasLength(1));
    await cubit.close();
  });
}
