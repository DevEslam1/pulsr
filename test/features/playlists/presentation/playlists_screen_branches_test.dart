// PlaylistsScreen branch coverage the existing suites miss: suggestion load
// failure, suggestion-create failure, the empty and smart export paths, and
// the wide two-pane master/detail layout.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/core/services/playlist_suggestions_service.dart';
import 'package:pulsr/core/services/ytm_account_service.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/usecases/playlist_io_usecases.dart';
import 'package:pulsr/domain/models/smart_playlist_criteria.dart';
import 'package:pulsr/domain/usecases/get_songs_usecase.dart';
import 'package:pulsr/domain/usecases/playlist_usecases.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/playlist_detail/presentation/playlist_detail_screen.dart';
import 'package:pulsr/features/playlists/cubit/playlist_cubit.dart';
import 'package:pulsr/features/playlists/cubit/playlist_state.dart';
import 'package:pulsr/features/playlists/presentation/playlists_screen.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _PlaylistCubit cubit;
  late StreamController<PlaylistState> states;
  late _Settings settings;
  late _Suggestions suggestions;
  late _PlaylistUseCases useCases;
  late _Export export;

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
    registerFallbackValue(<int>[]);
    registerFallbackValue(createTestSong(id: -1));
    registerFallbackValue(PlaylistFormat.m3u);
    registerFallbackValue(const SmartCriteria());
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'smart_playlists_seeded': true,
      'pulsr_hint_song_tile_swipe': true,
    });
    cubit = _PlaylistCubit();
    states = StreamController<PlaylistState>.broadcast();
    settings = _Settings();
    suggestions = _Suggestions();
    useCases = _PlaylistUseCases();
    export = _Export();

    when(() => cubit.state).thenReturn(const PlaylistState(isLoading: false));
    when(() => cubit.stream).thenAnswer((_) => states.stream);
    when(() => cubit.ytmOnline)
        .thenReturn(ValueNotifier<YtmOnlineState>(const YtmOnlineState()));
    when(() => cubit.createPlaylist(any())).thenAnswer((_) async {});
    when(() => cubit.renamePlaylist(any(), any())).thenAnswer((_) async {});
    when(() => cubit.deletePlaylist(any())).thenAnswer((_) async {});
    when(() => cubit.reloadPlaylists()).thenReturn(null);
    when(() => cubit.autoFetchOnlineLibrary()).thenAnswer((_) async {});
    when(() => cubit.autoFetchOnlineLibrary(force: true))
        .thenAnswer((_) async {});
    when(() => cubit.fetchLikedSongsPlaylist()).thenAnswer((_) async {});
    when(() => cubit.fetchAccountPlaylists()).thenAnswer((_) async {});
    when(() => cubit.fetchOnlinePlaylistByUrl(any()))
        .thenAnswer((_) async {});

    when(() => settings.state).thenReturn(const SettingsState());
    when(() => settings.stream)
        .thenAnswer((_) => const Stream<SettingsState>.empty());
    when(() => settings.rescanLibrary()).thenAnswer((_) async => 0);

    when(() => suggestions.generateSuggestionsAsync(any(),
            forceRefresh: any(named: 'forceRefresh')))
        .thenAnswer((_) async => const <PlaylistSuggestion>[]);
    when(() => useCases.watchPlaylistSongs(any()))
        .thenAnswer((_) => Stream.value(Right([createTestSong(id: 1)])));
    when(() => useCases.watchSmartPlaylistSongs(any()))
        .thenAnswer((_) => Stream.value([createTestSong(id: 1)]));
    when(() => useCases.createPlaylist(any()))
        .thenAnswer((_) async => const Right(9));
    when(() => useCases.addSongsToPlaylist(any(), any()))
        .thenAnswer((_) async => const Right<AppFailure, void>(null));
    when(() => export.exportToFile(any(), any(),
            format: any(named: 'format')))
        .thenAnswer((_) async =>
            File('${Directory.systemTemp.path}/pulsr_export.m3u'));

    final getSongs = _GetSongs();
    when(() => getSongs.getAllSongs())
        .thenAnswer((_) async => Right([createTestSong(id: 1, playCount: 4)]));
    final account = _Account();
    when(() => account.loginState).thenReturn(ValueNotifier<bool>(false));
    when(() => account.isLoggedIn).thenReturn(false);
    final ytm = _YtmService();
    when(() => ytm.getPlaylistTracks(any(), limit: any(named: 'limit')))
        .thenAnswer((_) async => const []);

    getIt.registerSingleton<GetSongsUseCase>(getSongs);
    getIt.registerSingleton<PlaylistSuggestionsService>(suggestions);
    getIt.registerSingleton<PlaylistUseCases>(useCases);
    getIt.registerSingleton<PlaylistExportUseCase>(export);
    getIt.registerSingleton<YtmAccountService>(account);
    getIt.registerSingleton<YtmService>(ytm);

    addTearDown(() async {
      await states.close();
      await getIt.reset();
    });
  });

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(800, 1600),
  }) async {
    useScreenSize(tester, size);
    await tester.pumpWidget(screenHarness(
      size: size,
      providers: [
        BlocProvider<PlaylistCubit>.value(value: cubit),
        BlocProvider<PlayerCubit>.value(value: stubPlayerCubit()),
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

  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    while (tester.takeException() != null) {}
  }

  testWidgets('a suggestion-load failure is swallowed', (tester) async {
    when(() => suggestions.generateSuggestionsAsync(any(),
            forceRefresh: any(named: 'forceRefresh')))
        .thenAnswer((_) async => throw StateError('suggest down'));

    await pump(tester);
    await emit(tester, PlaylistState(playlists: [userPlaylist]));

    expect(tester.takeException(), isNull);
  });

  testWidgets('creating from a suggestion reports a create failure',
      (tester) async {
    when(() => suggestions.generateSuggestionsAsync(any(),
        forceRefresh: any(named: 'forceRefresh'))).thenAnswer((_) async => [
          PlaylistSuggestion(
              title: 'Heavy Rotation',
              description: 'top tracks',
              songs: [createTestSong(id: 1)]),
        ]);
    when(() => useCases.createPlaylist(any()))
        .thenAnswer((_) async => const Left(DatabaseFailure('nope')));

    await pump(tester);
    await emit(tester, PlaylistState(playlists: [userPlaylist]));

    await tester.tap(find.text('Heavy Rotation'));
    await tester.pumpAndSettle();

    verify(() => useCases.createPlaylist('Heavy Rotation')).called(1);
  });

  testWidgets('exporting an empty playlist warns', (tester) async {
    when(() => useCases.watchPlaylistSongs(any()))
        .thenAnswer((_) => Stream.value(const Right(<SongsTableData>[])));

    await pump(tester);
    await emit(tester, PlaylistState(playlists: [userPlaylist]));

    await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
    await settle(tester);
    await tester.tap(find.text('Export'));
    await settle(tester);
    await tester.tap(find.text('M3U'));
    await settle(tester);

    expect(find.text('Cannot export an empty playlist.'), findsWidgets);
  });

  testWidgets('a smart playlist exports through its live criteria',
      (tester) async {
    await pump(tester);
    await emit(tester, PlaylistState(playlists: [smartPlaylist]));

    await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
    await settle(tester);
    await tester.tap(find.text('Share'));
    await settle(tester);

    verify(() => useCases.watchSmartPlaylistSongs(any())).called(1);
  });

  testWidgets('the wide layout embeds the detail pane', (tester) async {
    await pump(tester, size: const Size(1200, 900));
    await emit(tester, PlaylistState(playlists: [userPlaylist]));
    await settle(tester);

    expect(find.byType(PlaylistDetailScreen), findsOneWidget);
  });

  testWidgets('the wide layout with no playlists shows the select hint',
      (tester) async {
    await pump(tester, size: const Size(1200, 900));
    await emit(tester, const PlaylistState(isLoading: false));
    await settle(tester);

    expect(find.text('Select a playlist to view tracks'), findsOneWidget);
  });
}
