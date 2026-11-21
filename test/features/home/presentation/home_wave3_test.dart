import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/core/services/radio_station_store.dart';
import 'package:pulsr/core/services/ytm_account_service.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/shimmer_skeleton.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/radio_station.dart';
import 'package:pulsr/domain/models/ytm_track.dart';
import 'package:pulsr/domain/usecases/get_songs_usecase.dart';
import 'package:pulsr/features/home/presentation/home_screen.dart';
import 'package:pulsr/features/library/cubit/library_cubit.dart';
import 'package:pulsr/features/library/cubit/library_state.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/search/presentation/search_screen.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/l10n/app_localizations_delegates.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/screen_harness.dart';
import '../../../helpers/test_song_factory.dart';

class _YtmService extends Mock implements YtmService {}

class _Account extends Mock implements YtmAccountService {}

class _GetSongs extends Mock implements GetSongsUseCase {}

class _LibraryCubit extends Mock implements LibraryCubit {}

class _SettingsCubit extends Mock implements SettingsCubit {}

class _FakeRadioStation extends Fake implements RadioStation {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _YtmService ytm;
  late _Account account;
  late _GetSongs getSongs;
  late _LibraryCubit libraryCubit;
  late _SettingsCubit settingsCubit;
  late ValueNotifier<bool> loginState;
  late PlayerCubit player;

  setUpAll(() {
    registerFallbackValue(createTestSong(id: -1));
    registerFallbackValue(<SongsTableData>[]);
    registerFallbackValue(<String>[]);
    registerFallbackValue(_FakeRadioStation());
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'pulsr_hint_song_tile_swipe': true,
    });
    RadioStationStore.resetForTesting();
    ytm = _YtmService();
    account = _Account();
    getSongs = _GetSongs();
    libraryCubit = _LibraryCubit();
    settingsCubit = _SettingsCubit();
    loginState = ValueNotifier<bool>(false);
    player = stubPlayerCubit();
    when(() => player.playSong(any(), queue: any(named: 'queue')))
        .thenAnswer((_) async {});
    when(() => player.playRadioStation(any())).thenAnswer((_) async {});
    when(() => player.warmStreams(any(), count: any(named: 'count')))
        .thenAnswer((_) {});

    when(() => account.loginState).thenReturn(loginState);
    when(() => account.isLoggedIn).thenReturn(false);
    when(() => ytm.searchWithFallback(any()))
        .thenAnswer((_) async => const <YtmTrack>[]);

    when(() => getSongs.getAllSongs(
          sortBy: any(named: 'sortBy'),
          ascending: any(named: 'ascending'),
          limit: any(named: 'limit'),
          excludedFolders: any(named: 'excludedFolders'),
        )).thenAnswer((_) async => const Right(<SongsTableData>[]));
    when(() => getSongs.watchTopPlayed(
            limit: any(named: 'limit'),
            excludedFolders: any(named: 'excludedFolders')))
        .thenAnswer((_) => Stream.value(const Right(<SongsTableData>[])));
    when(() => getSongs.watchRecentlyPlayed(limit: any(named: 'limit')))
        .thenAnswer((_) => Stream.value(Right([
              createTestSong(id: 1, title: 'Recent Track 1'),
              createTestSong(id: 2, title: 'Recent Track 2'),
            ])));
    when(() => getSongs.watchRecentlyAdded(limit: any(named: 'limit')))
        .thenAnswer((_) => Stream.value(Right([
              createTestSong(id: 3, title: 'Added Track 1'),
              createTestSong(id: 4, title: 'Added Track 2'),
            ])));

    when(() => libraryCubit.state).thenReturn(const LibraryState());
    when(() => libraryCubit.stream)
        .thenAnswer((_) => const Stream<LibraryState>.empty());

    when(() => settingsCubit.state).thenReturn(const SettingsState());
    when(() => settingsCubit.stream)
        .thenAnswer((_) => const Stream<SettingsState>.empty());
    when(() => settingsCubit.rescanLibrary()).thenAnswer((_) async => 0);

    addTearDown(() {
      loginState.dispose();
      RadioStationStore.resetForTesting();
    });
  });

  testWidgets(
      'HomeScreen structures content into 3 calm visual beats in order (Beat 1 Hero, Studio Tools rail, Personal Rails)',
      (tester) async {
    useScreenSize(tester, const Size(900, 2200));
    await tester.pumpWidget(
      screenHarness(
        size: const Size(900, 2200),
        providers: [
          BlocProvider<PlayerCubit>.value(value: player),
          BlocProvider<LibraryCubit>.value(value: libraryCubit),
          BlocProvider<SettingsCubit>.value(value: settingsCubit),
        ],
        child: HomeScreen(
          ytmService: ytm,
          ytmAccountService: account,
          getSongsUseCase: getSongs,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final beat1 = find.byKey(const ValueKey('home_beat_1_immediate_resume'));
    final beat2 = find.byKey(const ValueKey('home_beat_2_personal_rails'));
    final beat3 = find.byKey(const ValueKey('home_beat_3_studio_tools'));
    final studioRail = find.byKey(const ValueKey('home_studio_tools_rail'));

    expect(beat1, findsOneWidget);
    expect(beat2, findsOneWidget);
    expect(beat3, findsOneWidget);
    expect(studioRail, findsOneWidget);

    final y1 = tester.getTopLeft(beat1).dy;
    final y2 = tester.getTopLeft(beat2).dy;
    final y3 = tester.getTopLeft(beat3).dy;

    expect(y1, lessThan(y3));
    expect(y3, lessThan(y2));
  });

  testWidgets(
      'HomeScreen online search banner navigates to unified online SearchScreen.routeLocation(scope: SearchScope.online, autofocus: true)',
      (tester) async {
    useScreenSize(tester, const Size(900, 1800));
    String? navigatedUri;
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => HomeScreen(
            ytmService: ytm,
            ytmAccountService: account,
            getSongsUseCase: getSongs,
            enableOnlineOverride: true,
          ),
        ),
        GoRoute(
          path: '/search',
          builder: (context, state) {
            navigatedUri = state.uri.toString();
            return Scaffold(body: Text('SEARCH_URI:$navigatedUri'));
          },
        ),
        GoRoute(
          path: '/settings',
          builder: (_, __) => const Scaffold(body: Text('SETTINGS_ROUTE')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(900, 1800),
          disableAnimations: true,
        ),
        child: MultiBlocProvider(
          providers: [
            BlocProvider<PlayerCubit>.value(value: player),
            BlocProvider<LibraryCubit>.value(value: libraryCubit),
            BlocProvider<SettingsCubit>.value(value: settingsCubit),
          ],
          child: MaterialApp.router(
            theme: AuraTheme.darkTheme,
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Switch to Online tab on HomeScreen
    await tester.tap(find.text('Online'));
    await tester.pumpAndSettle();

    // Tap the online search banner
    final banner = find.byKey(const ValueKey('home_online_search_banner'));
    expect(banner, findsOneWidget);
    await tester.tap(banner);
    await tester.pumpAndSettle();

    expect(
      navigatedUri,
      SearchScreen.routeLocation(scope: SearchScope.online, autofocus: true),
    );
    expect(navigatedUri, '/search?scope=online&autofocus=true');
  });

  testWidgets(
      'HomeScreen loading states render SkeletonShimmer with zero CircularProgressIndicator',
      (tester) async {
    final recentCtrl =
        StreamController<Result<List<SongsTableData>>>.broadcast();
    final addedCtrl =
        StreamController<Result<List<SongsTableData>>>.broadcast();
    addTearDown(() async {
      await recentCtrl.close();
      await addedCtrl.close();
    });

    when(() => getSongs.watchRecentlyPlayed(limit: any(named: 'limit')))
        .thenAnswer((_) => recentCtrl.stream);
    when(() => getSongs.watchRecentlyAdded(limit: any(named: 'limit')))
        .thenAnswer((_) => addedCtrl.stream);

    useScreenSize(tester, const Size(900, 1800));
    await tester.pumpWidget(
      screenHarness(
        size: const Size(900, 1800),
        providers: [
          BlocProvider<PlayerCubit>.value(value: player),
          BlocProvider<LibraryCubit>.value(value: libraryCubit),
          BlocProvider<SettingsCubit>.value(value: settingsCubit),
        ],
        child: HomeScreen(
          ytmService: ytm,
          ytmAccountService: account,
          getSongsUseCase: getSongs,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(SkeletonShimmer), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets(
      'QuranRadioHeroCarousel disables auto-scroll timers and animated page transitions when PulsrMotion.shouldAnimate is false',
      (tester) async {
    when(() => settingsCubit.state)
        .thenReturn(const SettingsState(reduceMotion: true));

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<PlayerCubit>.value(value: player),
          BlocProvider<SettingsCubit>.value(value: settingsCubit),
        ],
        child: MaterialApp(
          theme: AuraTheme.darkTheme,
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: QuranRadioHeroCarousel(
              playerCubit: player,
              autoScroll: true,
              autoScrollInterval: const Duration(seconds: 2),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('1/11'), findsOneWidget);

    // Advance 6 seconds (> 2s interval): auto-scroll must NOT fire under reduceMotion.
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('1/11'), findsOneWidget);

    // Tapping dot 3 / 11 jumps immediately in a single frame without animated transition.
    final dot3 = find.bySemanticsLabel('3 / 11');
    expect(dot3, findsOneWidget);
    await tester.tap(dot3);
    await tester.pump();
    expect(find.text('3/11'), findsOneWidget);
  });

  for (final scale in const [1.3, 1.6]) {
    testWidgets(
        'HomeScreen and QuranRadioHeroCarousel render at ${scale}x text scale without overflow',
        (tester) async {
      useScreenSize(tester, const Size(390, 844));
      await tester.pumpWidget(
        screenHarness(
          size: const Size(390, 844),
          providers: [
            BlocProvider<PlayerCubit>.value(value: player),
            BlocProvider<LibraryCubit>.value(value: libraryCubit),
            BlocProvider<SettingsCubit>.value(value: settingsCubit),
          ],
          child: MediaQuery(
            data: MediaQueryData(
              size: const Size(390, 844),
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: HomeScreen(
              ytmService: ytm,
              ytmAccountService: account,
              getSongsUseCase: getSongs,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  }
}
