import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/services/yt_download_service.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/pulsr_back_button.dart';
import 'package:pulsr/core/widgets/source_scope_switcher.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/download_task.dart';
import 'package:pulsr/domain/models/ytm_track.dart';
import 'package:pulsr/features/downloads/cubit/downloads_cubit.dart';
import 'package:pulsr/features/downloads/cubit/downloads_state.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/search/cubit/search_cubit.dart';
import 'package:pulsr/features/search/cubit/search_state.dart';
import 'package:pulsr/features/search/presentation/search_screen.dart';
import 'package:pulsr/features/search/presentation/widgets/highlighted_song_tile.dart';
import 'package:pulsr/features/ytm_search/cubit/ytm_download_cubit.dart';
import 'package:pulsr/features/ytm_search/cubit/ytm_search_cubit.dart';
import 'package:pulsr/features/ytm_search/presentation/ytm_search_screen.dart';
import 'package:pulsr/l10n/app_localizations_delegates.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/screen_harness.dart';
import '../../../helpers/test_song_factory.dart';

class _MockSearchCubit extends Mock implements SearchCubit {}

class _MockYtmService extends Mock implements YtmService {}

class _MockYtDownloadService extends Mock implements YtDownloadService {}

class _MockDownloadsCubit extends Mock implements DownloadsCubit {}

YtmTrack _track(String id, String title, [String artist = 'Daft Punk']) =>
    YtmTrack(
      videoId: id,
      title: title,
      artist: artist,
      duration: const Duration(minutes: 4),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final l10n = lookupAppLocalizations(const Locale('en'));

  late _MockSearchCubit localCubit;
  late StreamController<SearchState> localStates;
  late ValueNotifier<List<String>> savedSearches;
  late ValueNotifier<List<SongsTableData>> searchPlayedSongs;
  late ValueNotifier<bool> hasMoreResults;
  late _MockYtmService ytmService;
  late YtmDownloadCubit downloadCubit;
  late StreamController<DownloadsState> downloadsController;
  late PlayerCubit player;

  setUpAll(() {
    registerFallbackValue('');
    registerFallbackValue(<String>[]);
    registerFallbackValue(createTestSong(id: -1));
    registerFallbackValue(<SongsTableData>[]);
    registerFallbackValue(DownloadTask(
      id: 'fallback',
      videoId: 'fallback',
      title: 'Fallback',
      artist: 'Fallback',
      createdAt: DateTime(2026, 1, 1),
    ));
  });

  setUp(() async {
    await getIt.reset();
    SharedPreferences.setMockInitialValues({});

    localCubit = _MockSearchCubit();
    localStates = StreamController<SearchState>.broadcast();
    savedSearches = ValueNotifier<List<String>>(const []);
    searchPlayedSongs = ValueNotifier<List<SongsTableData>>(const []);
    hasMoreResults = ValueNotifier<bool>(false);

    when(() => localCubit.state).thenReturn(const SearchState());
    when(() => localCubit.stream).thenAnswer((_) => localStates.stream);
    when(() => localCubit.savedSearches).thenReturn(savedSearches);
    when(() => localCubit.searchPlayedSongs).thenReturn(searchPlayedSongs);
    when(() => localCubit.hasMoreResults).thenReturn(hasMoreResults);
    when(() => localCubit.isDebouncing).thenReturn(false);
    when(() => localCubit.isSaved(any(), any())).thenReturn(false);
    when(() => localCubit.onQueryChanged(any(),
        immediate: any(named: 'immediate'))).thenReturn(null);
    when(() => localCubit.commitQuery(any())).thenAnswer((_) async {});
    when(() => localCubit.clearQuery()).thenReturn(null);
    when(() => localCubit.setFilter(any())).thenReturn(null);
    when(() => localCubit.applySavedSearch(any(), any())).thenReturn(null);
    when(() => localCubit.recordPlayedSong(any())).thenAnswer((_) async {});
    when(() => localCubit.removeSearchPlayedSong(any()))
        .thenAnswer((_) async {});
    when(() => localCubit.clearSearchPlayedSongs()).thenAnswer((_) async {});
    when(() => localCubit.suggestionsFor(any()))
        .thenAnswer((_) async => const <String>[]);

    ytmService = _MockYtmService();
    when(() => ytmService.invalidatePoToken()).thenAnswer((_) async {});
    when(() => ytmService.ensurePoTokenReady()).thenAnswer((_) async => true);
    when(() => ytmService.isBotCoolingDown).thenReturn(false);
    when(() => ytmService.botCooldownNotifier)
        .thenReturn(ValueNotifier<bool>(false));
    when(() => ytmService.searchWithFallback(any()))
        .thenAnswer((_) async => [_track('vid1', 'Harder Better')]);

    final downloadsCubit = _MockDownloadsCubit();
    downloadsController = StreamController<DownloadsState>.broadcast();
    when(() => downloadsCubit.stream)
        .thenAnswer((_) => downloadsController.stream);
    when(() => downloadsCubit.queueDownload(any())).thenAnswer((_) async =>
        const Right(QueueDownloadResult(
            taskId: 'vid1', admission: DownloadAdmission.queued)));
    when(() => downloadsCubit.cancelDownload(any())).thenAnswer((_) async {});

    downloadCubit = YtmDownloadCubit(
      _MockYtDownloadService(),
      stubPlayerCubit(),
      downloadsCubit: downloadsCubit,
    );
    getIt.registerSingleton<YtmDownloadCubit>(downloadCubit);
    getIt.registerFactory<YtmSearchCubit>(
      () => YtmSearchCubit(service: ytmService),
    );

    player = stubPlayerCubit();
  });

  tearDown(() async {
    await localStates.close();
    savedSearches.dispose();
    searchPlayedSongs.dispose();
    hasMoreResults.dispose();
    await downloadsController.close();
    await downloadCubit.close();
    await getIt.reset();
  });

  test('routeLocation and parseScopeParam expose a stable route contract', () {
    expect(SearchScreen.routeLocation(), '/search');
    expect(
      SearchScreen.routeLocation(scope: SearchScope.online, autofocus: true),
      '/search?scope=online&autofocus=true',
    );
    expect(
      SearchScreen.routeLocation(
        query: 'Daft Punk',
        scope: SearchScope.online,
        autofocus: true,
      ),
      '/search?q=Daft+Punk&scope=online&autofocus=true',
    );

    expect(SearchScreen.parseScopeParam('online'), SearchScope.online);
    expect(SearchScreen.parseScopeParam('LOCAL'), SearchScope.local);
    expect(SearchScreen.parseScopeParam('all'), SearchScope.all);
    expect(SearchScreen.parseScopeParam('invalid'), isNull);
    expect(SearchScreen.parseScopeParam(null), isNull);
  });

  testWidgets(
      'SearchScreen(initialScope: SearchScope.online, autofocus: true) pins online scope even if local was persisted',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      SourceScopeSwitcher.storageKey('search'): 'local',
    });

    useScreenSize(tester, const Size(800, 1400));
    await tester.pumpWidget(
      screenHarness(
        providers: [
          BlocProvider<SearchCubit>.value(value: localCubit),
          BlocProvider<PlayerCubit>.value(value: player),
        ],
        child: const SearchScreen(
          initialScope: SearchScope.online,
          autofocus: true,
          enableOnlineOverride: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Online hint is active and autofocus focused the input.
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.autofocus, isTrue);
    expect(field.focusNode?.hasFocus, isTrue);
    expect(field.decoration?.hintText, l10n.searchOnline);

    // Online empty discovery state is shown (not clobbered by persisted 'local').
    expect(find.byIcon(Icons.travel_explore_rounded), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Daft Punk');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    verify(() => ytmService.searchWithFallback('Daft Punk')).called(1);
    expect(find.byType(HighlightedSongTile), findsOneWidget);
  });

  testWidgets(
      'GoRouter /search?scope=online&q=...&autofocus=true drives unified online search',
      (tester) async {
    useScreenSize(tester, const Size(800, 1400));
    final router = GoRouter(
      initialLocation: SearchScreen.routeLocation(
        query: 'Daft Punk',
        scope: SearchScope.online,
        autofocus: true,
      ),
      routes: [
        GoRoute(
          path: '/search',
          builder: (context, state) => SearchScreen(
            initialQuery: state.uri.queryParameters['q'],
            enableOnlineOverride: true,
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<SearchCubit>.value(value: localCubit),
          BlocProvider<PlayerCubit>.value(value: player),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData.dark().copyWith(extensions: [AuraTheme.defaultDark]),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration?.hintText, l10n.searchOnline);
    expect(field.focusNode?.hasFocus, isTrue);
    verify(() => ytmService.searchWithFallback('Daft Punk')).called(1);
    expect(find.byType(HighlightedSongTile), findsOneWidget);
  });

  testWidgets(
      'YtmSearchScreen is a thin wrapper over SearchScreen(online, autofocus, back button)',
      (tester) async {
    useScreenSize(tester, const Size(800, 1400));
    await tester.pumpWidget(
      screenHarness(
        providers: [
          BlocProvider<PlayerCubit>.value(value: player),
        ],
        child: const YtmSearchScreen(),
      ),
    );
    await tester.pumpAndSettle();

    final unified = tester.widget<SearchScreen>(find.byType(SearchScreen));
    expect(unified.initialScope, SearchScope.online);
    expect(unified.autofocus, isTrue);
    expect(unified.showBackButton, isTrue);
    expect(find.byType(PulsrBackButton), findsOneWidget);
  });

  testWidgets('SearchScreen exposes header semantics and >= 48dp targets',
      (tester) async {
    useScreenSize(tester, const Size(800, 1400));
    final semantics = tester.ensureSemantics();

    savedSearches.value = ['Ambient|Songs'];
    await tester.pumpWidget(
      screenHarness(
        providers: [
          BlocProvider<SearchCubit>.value(value: localCubit),
          BlocProvider<PlayerCubit>.value(value: player),
        ],
        child: const SearchScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // Saved searches section header is flagged as a semantic header.
    final savedHeader =
        tester.getSemantics(find.text(l10n.savedSearches.toUpperCase()));
    expect(savedHeader.flagsCollection.isHeader, isTrue);

    // Saved search remove button meets >= 48x48dp hit target.
    final removeBtn = find.widgetWithIcon(IconButton, Icons.close_rounded);
    expect(removeBtn, findsOneWidget);
    final removeSize = tester.getSize(removeBtn);
    expect(removeSize.width, greaterThanOrEqualTo(48.0));
    expect(removeSize.height, greaterThanOrEqualTo(48.0));

    semantics.dispose();
  });
}
