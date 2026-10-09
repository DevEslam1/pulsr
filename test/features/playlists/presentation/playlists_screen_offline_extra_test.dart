// PlaylistsScreen additional coverage: the user export-format sheet, smart
// playlist rename/delete menus, online liked/custom download paths (incl. the
// empty-custom toast) and the local pull-to-refresh rescan.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/services/playlist_suggestions_service.dart';
import 'package:pulsr/core/services/ytm_account_service.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/usecases/playlist_io_usecases.dart';
import 'package:pulsr/domain/models/ytm_track.dart';
import 'package:pulsr/domain/usecases/get_songs_usecase.dart';
import 'package:pulsr/domain/usecases/playlist_usecases.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/playlists/cubit/playlist_cubit.dart';
import 'package:pulsr/features/playlists/cubit/playlist_state.dart';
import 'package:pulsr/features/playlists/presentation/playlists_screen.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/features/ytm_search/cubit/ytm_download_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/screen_harness.dart';
import '../../../helpers/test_song_factory.dart';

class _PlaylistCubit extends Mock implements PlaylistCubit {}

class _GetSongs extends Mock implements GetSongsUseCase {}

class _Suggestions extends Mock implements PlaylistSuggestionsService {}

class _PlaylistUseCases extends Mock implements PlaylistUseCases {}

class _Export extends Mock implements PlaylistExportUseCase {}

class _Settings extends Mock implements SettingsCubit {}

class _Account extends Mock implements YtmAccountService {}

class _YtmService extends Mock implements YtmService {}

class _Download extends Mock implements YtmDownloadCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _PlaylistCubit cubit;
  late StreamController<PlaylistState> states;
  late ValueNotifier<YtmOnlineState> online;
  late ValueNotifier<bool> loginState;
  late _Settings settings;
  late _Export export;
  late _Download download;

  final userPlaylist = PlaylistsTableData(
    id: 1,
    name: 'Road Trip',
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
    isSmart: false,
  );

  final smartPlaylist = PlaylistsTableData(
    id: 2,
    name: 'Smart Mix',
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
    isSmart: true,
    smartCriteria: '{"rules":[],"matchAll":true}',
  );

  const track = YtmTrack(
      videoId: 'v1', title: 'T', artist: 'A', duration: Duration(seconds: 3));

  setUpAll(() {
    registerFallbackValue('');
    registerFallbackValue(0);
    registerFallbackValue(false);
    registerFallbackValue(<int>[]);
    registerFallbackValue(<String>[]);
    registerFallbackValue(<SongsTableData>[]);
    registerFallbackValue(createTestSong(id: -1));
    registerFallbackValue(PlaylistFormat.m3u);
    registerFallbackValue(OnlinePlaylistEntry(
        id: 'x', title: 'x', uploader: 'x', tracks: const []));
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({'smart_playlists_seeded': true});
    cubit = _PlaylistCubit();
    states = StreamController<PlaylistState>.broadcast();
    online = ValueNotifier<YtmOnlineState>(const YtmOnlineState());
    loginState = ValueNotifier<bool>(false);
    settings = _Settings();

    when(() => cubit.state).thenReturn(const PlaylistState(isLoading: false));
    when(() => cubit.stream).thenAnswer((_) => states.stream);
    when(() => cubit.ytmOnline).thenReturn(online);
    when(() => cubit.createPlaylist(any())).thenAnswer((_) async {});
    when(() => cubit.renamePlaylist(any(), any())).thenAnswer((_) async {});
    when(() => cubit.deletePlaylist(any())).thenAnswer((_) async {});
    when(() => cubit.autoFetchOnlineLibrary()).thenAnswer((_) async {});
    when(() => cubit.autoFetchOnlineLibrary(force: true))
        .thenAnswer((_) async {});
    when(() => cubit.fetchLikedSongsPlaylist()).thenAnswer((_) async {});
    when(() => cubit.fetchAccountPlaylists()).thenAnswer((_) async {});
    when(() => cubit.fetchOnlinePlaylistByUrl(any()))
        .thenAnswer((_) async {});
    when(() => cubit.removeCustomPlaylist(any())).thenReturn(null);
    when(() => cubit.restoreCustomPlaylist(any())).thenReturn(null);

    when(() => settings.state).thenReturn(const SettingsState());
    when(() => settings.stream)
        .thenAnswer((_) => const Stream<SettingsState>.empty());
    when(() => settings.rescanLibrary()).thenAnswer((_) async => 0);

    final getSongs = _GetSongs();
    when(() => getSongs.getAllSongs())
        .thenAnswer((_) async => Right([createTestSong(id: 1, playCount: 4)]));
    final suggestions = _Suggestions();
    when(() => suggestions.generateSuggestionsAsync(any(),
            forceRefresh: any(named: 'forceRefresh')))
        .thenAnswer((_) async => const <PlaylistSuggestion>[]);
    final useCases = _PlaylistUseCases();
    when(() => useCases.watchPlaylistSongs(any()))
        .thenAnswer((_) => Stream.value(Right([createTestSong(id: 1)])));
    when(() => useCases.createPlaylist(any()))
        .thenAnswer((_) async => const Right(9));
    when(() => useCases.addSongsToPlaylist(any(), any()))
        .thenAnswer((_) async => const Right(null));
    export = _Export();
    when(() => export.exportToFile(any(), any(),
            format: any(named: 'format')))
        .thenAnswer((_) async =>
            File('${Directory.systemTemp.path}/pulsr_export.m3u'));
    final account = _Account();
    when(() => account.loginState).thenReturn(loginState);
    when(() => account.isLoggedIn).thenReturn(false);
    final ytm = _YtmService();
    when(() => ytm.getPlaylistTracks(any(), limit: any(named: 'limit')))
        .thenAnswer((_) async => const <YtmTrack>[]);
    download = _Download();
    when(() => download.downloadAll(any())).thenReturn(1);

    getIt.registerSingleton<GetSongsUseCase>(getSongs);
    getIt.registerSingleton<PlaylistSuggestionsService>(suggestions);
    getIt.registerSingleton<PlaylistUseCases>(useCases);
    getIt.registerSingleton<PlaylistExportUseCase>(export);
    getIt.registerSingleton<YtmAccountService>(account);
    getIt.registerSingleton<YtmService>(ytm);
    getIt.registerSingleton<YtmDownloadCubit>(download);

    addTearDown(() async {
      await states.close();
      online.dispose();
      loginState.dispose();
      await getIt.reset();
    });
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    useScreenSize(tester, const Size(800, 1800));
    final player = stubPlayerCubit();
    await tester.pumpWidget(screenHarness(
      providers: [
        BlocProvider<PlaylistCubit>.value(value: cubit),
        BlocProvider<PlayerCubit>.value(value: player),
        BlocProvider<SettingsCubit>.value(value: settings),
      ],
      child: const PlaylistsScreen(),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> emit(WidgetTester tester, PlaylistState state) async {
    states.add(state);
    await tester.pump();
    await tester.pump();
  }

  Future<void> openMenu(WidgetTester tester, {int index = 0}) async {
    await tester.tap(find.byIcon(Icons.more_vert_rounded).at(index));
    await tester.pumpAndSettle();
  }

  /// The small overlay download glyphs are hard to hit reliably; invoke the
  /// nearest tap handler directly.
  void invokeCardDownload(WidgetTester tester) {
    final gesture = find
        .ancestor(
          of: find.byIcon(Icons.download_rounded).first,
          matching: find.byType(GestureDetector),
        )
        .first;
    tester.widget<GestureDetector>(gesture).onTap!.call();
  }

  // The export-format chooser renders bare ListTiles inside the frosted sheet
  // container, which trips a debug-only ink-splash assertion.
  void ignoreInkSplashAssertion() {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details
          .exceptionAsString()
          .contains('ListTile background color or ink splashes')) {
        return;
      }
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);
  }

  testWidgets('a user playlist exports through the format sheet',
      (tester) async {
    ignoreInkSplashAssertion();
    await pumpScreen(tester);
    await emit(tester, PlaylistState(playlists: [userPlaylist]));

    await openMenu(tester);
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();

    expect(find.text('M3U'), findsOneWidget);
    await tester.tap(find.text('M3U'));
    await tester.pumpAndSettle();

    verify(() => export.exportToFile('Road Trip', any(),
        format: PlaylistFormat.m3u)).called(1);
  });

  testWidgets('a smart playlist can be renamed and deleted', (tester) async {
    await pumpScreen(tester);
    await emit(tester, PlaylistState(playlists: [smartPlaylist]));

    await openMenu(tester);
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Renamed Smart');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    verify(() => cubit.renamePlaylist(2, 'Renamed Smart')).called(1);

    await openMenu(tester);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    verify(() => cubit.deletePlaylist(2)).called(1);
  });

  testWidgets('liked music download queues every track', (tester) async {
    loginState.value = true;
    online.value = const YtmOnlineState(
      likedStatus: YtmFetchStatus.done,
      likedTracks: [track],
    );
    await pumpScreen(tester);
    await emit(tester, PlaylistState(playlists: [userPlaylist]));
    await tester.tap(find.text('Online'));
    await tester.pumpAndSettle();

    invokeCardDownload(tester);
    await tester.pumpAndSettle();

    verify(() => download.downloadAll(any())).called(1);
  });

  testWidgets('an empty custom playlist download warns instead of queueing',
      (tester) async {
    loginState.value = true;
    online.value = const YtmOnlineState(
      likedStatus: YtmFetchStatus.loading,
      customStatus: YtmFetchStatus.done,
      customPlaylists: [
        OnlinePlaylistEntry(id: 'c1', title: 'Added Mix', uploader: 'u', tracks: []),
      ],
    );
    await pumpScreen(tester);
    await emit(tester, PlaylistState(playlists: [userPlaylist]));
    await tester.tap(find.text('Online'));
    await tester.pumpAndSettle();

    expect(find.text('Added Mix'), findsOneWidget);
    invokeCardDownload(tester);
    await tester.pumpAndSettle();

    verifyNever(() => download.downloadAll(any()));
  });

  testWidgets('a populated custom playlist download queues its tracks',
      (tester) async {
    loginState.value = true;
    online.value = const YtmOnlineState(
      likedStatus: YtmFetchStatus.loading,
      customStatus: YtmFetchStatus.done,
      customPlaylists: [
        OnlinePlaylistEntry(
            id: 'c1', title: 'Added Mix', uploader: 'u', tracks: [track]),
      ],
    );
    await pumpScreen(tester);
    await emit(tester, PlaylistState(playlists: [userPlaylist]));
    await tester.tap(find.text('Online'));
    await tester.pumpAndSettle();

    invokeCardDownload(tester);
    await tester.pumpAndSettle();

    verify(() => download.downloadAll(any())).called(1);
  });

  testWidgets('the added-playlists error card renders the failure',
      (tester) async {
    loginState.value = true;
    online.value = const YtmOnlineState(
      customStatus: YtmFetchStatus.error,
      customError: 'custom boom',
    );
    await pumpScreen(tester);
    await emit(tester, PlaylistState(playlists: [userPlaylist]));
    await tester.tap(find.text('Online'));
    await tester.pumpAndSettle();

    expect(find.text('custom boom'), findsOneWidget);
  });

  testWidgets('pull-to-refresh on the local tab rescans the library',
      (tester) async {
    await pumpScreen(tester);
    await emit(tester, PlaylistState(playlists: [userPlaylist]));

    final indicator = tester.widget<RefreshIndicator>(
        find.byType(RefreshIndicator).first);
    await indicator.onRefresh();
    await tester.pumpAndSettle();

    verify(() => settings.rescanLibrary()).called(1);
  });
}
