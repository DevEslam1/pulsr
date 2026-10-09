// Additional PlaylistsScreen coverage: suggestion cards, rename/delete/undo,
// export format sheet, smart-playlist menu navigation and the online tab
// (signed-out banner, liked-music states, account and custom playlists).
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

  setUpAll(() {
    registerFallbackValue('');
    registerFallbackValue(0);
    registerFallbackValue(false);
    registerFallbackValue(<int>[]);
    registerFallbackValue(<String>[]);
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

    when(() => cubit.state)
        .thenReturn(const PlaylistState(isLoading: false));
    when(() => cubit.stream).thenAnswer((_) => states.stream);
    when(() => cubit.ytmOnline).thenReturn(online);
    when(() => cubit.createPlaylist(any())).thenAnswer((_) async {});
    when(() => cubit.renamePlaylist(any(), any())).thenAnswer((_) async {});
    when(() => cubit.deletePlaylist(any())).thenAnswer((_) async {});
    when(() => cubit.restorePlaylist(any(),
            isSmart: any(named: 'isSmart'),
            criteria: any(named: 'criteria'),
            songIds: any(named: 'songIds'))).thenAnswer((_) async => 1);
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
    final export = _Export();
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
    final download = _Download();
    when(() => download.downloadAll(any())).thenReturn(0);

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
    useScreenSize(tester, const Size(800, 1600));
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

  group('suggestion cards', () {
    testWidgets('renders a suggestion and creates a playlist from it',
        (tester) async {
      final suggestions = getIt<PlaylistSuggestionsService>() as _Suggestions;
      when(() => suggestions.generateSuggestionsAsync(any(),
          forceRefresh: any(named: 'forceRefresh'))).thenAnswer((_) async => [
            PlaylistSuggestion(
                title: 'Heavy Rotation Mix',
                description: 'your top tracks',
                songs: [createTestSong(id: 1)]),
          ]);

      await pumpScreen(tester);
      await emit(tester, PlaylistState(playlists: [userPlaylist]));

      expect(find.text('Heavy Rotation Mix'), findsOneWidget);
      await tester.tap(find.text('Heavy Rotation Mix'));
      await tester.pumpAndSettle();

      final useCases = getIt<PlaylistUseCases>();
      verify(() => useCases.createPlaylist('Heavy Rotation Mix')).called(1);
      verify(() => useCases.addSongsToPlaylist(9, [1])).called(1);
    });
  });

  group('local playlist menus', () {
    testWidgets('rename flow pushes the new name to the cubit',
        (tester) async {
      await pumpScreen(tester);
      await emit(tester, PlaylistState(playlists: [userPlaylist]));

      await openMenu(tester);
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Renamed Trip');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      verify(() => cubit.renamePlaylist(1, 'Renamed Trip')).called(1);
    });

    testWidgets('delete flow confirms and offers undo', (tester) async {
      await pumpScreen(tester);
      await emit(tester, PlaylistState(playlists: [userPlaylist]));

      await openMenu(tester);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      verify(() => cubit.deletePlaylist(1)).called(1);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      verify(() => cubit.restorePlaylist(any(),
          isSmart: any(named: 'isSmart'),
          criteria: any(named: 'criteria'),
          songIds: any(named: 'songIds'))).called(1);
    });

  });

  group('smart playlist menu', () {
    testWidgets('edit smart rules navigates to the builder',
        (tester) async {
      await pumpScreen(tester);
      await emit(tester, PlaylistState(playlists: [smartPlaylist]));

      await openMenu(tester);
      await tester.tap(find.text('Edit smart rules'));
      await tester.pumpAndSettle();

      expect(find.text('smart-playlist-builder-route'), findsOneWidget);
    });
  });

  group('online tab', () {
    testWidgets('signed-out shows the connect banner', (tester) async {
      await pumpScreen(tester);
      await emit(tester, PlaylistState(playlists: [userPlaylist]));

      await tester.tap(find.text('Online'));
      await tester.pumpAndSettle();

      expect(find.text('Connect YouTube Music'), findsOneWidget);
    });

    testWidgets('signed-in idle liked card fetches on tap', (tester) async {
      loginState.value = true;
      await pumpScreen(tester);
      await emit(tester, PlaylistState(playlists: [userPlaylist]));

      await tester.tap(find.text('Online'));
      await tester.pumpAndSettle();

      expect(find.text('Tap to sync from YouTube Music'), findsOneWidget);
      await tester.tap(find.text('Tap to sync from YouTube Music'));
      await tester.pump();
      verify(() => cubit.fetchLikedSongsPlaylist()).called(1);
    });

    testWidgets('signed-in done liked card opens the detail route',
        (tester) async {
      loginState.value = true;
      online.value = YtmOnlineState(
        likedStatus: YtmFetchStatus.done,
        likedTracks: const [
          YtmTrack(
              videoId: 'v1',
              title: 'T',
              artist: 'A',
              duration: Duration(seconds: 2)),
        ],
      );
      await pumpScreen(tester);
      await emit(tester, PlaylistState(playlists: [userPlaylist]));
      await tester.tap(find.text('Online'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Liked Music'));
      await tester.pumpAndSettle();
      expect(find.text('online-playlist-route'), findsOneWidget);
    });

    testWidgets('account playlists render and download', (tester) async {
      loginState.value = true;
      online.value = const YtmOnlineState(
        accountStatus: YtmFetchStatus.done,
        accountPlaylists: [
          YtmAccountPlaylist(
              playlistId: 'p1', title: 'My Playlist', subtitle: 'You'),
        ],
      );
      await pumpScreen(tester);
      await emit(tester, PlaylistState(playlists: [userPlaylist]));
      await tester.tap(find.text('Online'));
      await tester.pumpAndSettle();

      expect(find.text('My Playlist'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.download_rounded).last);
      await tester.pumpAndSettle();
      verify(() => getIt<YtmService>()
          .getPlaylistTracks('p1', limit: any(named: 'limit'))).called(1);
    });

    testWidgets('account playlists error state offers retry', (tester) async {
      loginState.value = true;
      online.value = const YtmOnlineState(
        accountStatus: YtmFetchStatus.error,
        accountError: 'nope',
      );
      await pumpScreen(tester);
      await emit(tester, PlaylistState(playlists: [userPlaylist]));
      await tester.tap(find.text('Online'));
      await tester.pumpAndSettle();

      expect(find.text('nope'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      verify(() => cubit.fetchAccountPlaylists()).called(1);
    });

    testWidgets('custom playlists render and removal is confirmed',
        (tester) async {
      loginState.value = true;
      online.value = const YtmOnlineState(
        customStatus: YtmFetchStatus.done,
        customPlaylists: [
          OnlinePlaylistEntry(
              id: 'c1', title: 'Added Mix', uploader: 'u', tracks: []),
        ],
      );
      await pumpScreen(tester);
      await emit(tester, PlaylistState(playlists: [userPlaylist]));
      await tester.tap(find.text('Online'));
      await tester.pumpAndSettle();

      expect(find.text('Added Mix'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded).last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      verify(() => cubit.removeCustomPlaylist('c1')).called(1);
    });

    testWidgets('add URL button opens the dialog and fetches', (tester) async {
      loginState.value = true;
      await pumpScreen(tester);
      await emit(tester, PlaylistState(playlists: [userPlaylist]));
      await tester.tap(find.text('Online'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add_link_rounded));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'https://y/list=abc');
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      verify(() => cubit.fetchOnlinePlaylistByUrl('https://y/list=abc'))
          .called(1);
    });
  });
}
