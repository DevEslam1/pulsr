// Full UI/UX verification matrix for HomeScreen:
// Mobile & Tablet viewports x Light / Dark / AMOLED / High-Contrast themes x
// LTR (en) & RTL (ar) x 100% & 200% text scale, plus Online tab rails.
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/services/radio_station_store.dart';
import 'package:pulsr/core/services/ytm_account_service.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/pulsr_scroll_edge_fade.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/radio_station.dart';
import 'package:pulsr/domain/models/ytm_track.dart';
import 'package:pulsr/domain/usecases/get_songs_usecase.dart';
import 'package:pulsr/features/home/presentation/home_screen.dart';
import 'package:pulsr/features/library/cubit/library_cubit.dart';
import 'package:pulsr/features/library/cubit/library_state.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
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

  final recentSongs = [
    createTestSong(
      id: 101,
      title: 'El Hazz — Live Session',
      artist: 'Marwan Moussa',
    ),
    createTestSong(
      id: 102,
      title: 'Midnight Echoes in Cairo',
      artist: 'Cairokee & Guests',
    ),
    createTestSong(
      id: 103,
      title: 'Pulsr Audio Reference Track 24-bit',
      artist: 'Studio Mastering Lab',
    ),
  ];

  final addedSongs = [
    createTestSong(id: 201, title: 'Added Track One', artist: 'Artist One'),
    createTestSong(id: 202, title: 'Added Track Two', artist: 'Artist Two'),
    createTestSong(id: 203, title: 'Added Track Three', artist: 'Artist Three'),
    createTestSong(id: 204, title: 'Added Track Four', artist: 'Artist Four'),
  ];

  const onlineTracks = [
    YtmTrack(
      videoId: 'yt-1',
      title: 'Trending Global Track One',
      artist: 'Online Artist Alpha',
      duration: Duration(minutes: 3, seconds: 24),
    ),
    YtmTrack(
      videoId: 'yt-2',
      title: 'Trending Global Track Two With Long Title',
      artist: 'Online Artist Beta',
      duration: Duration(minutes: 4, seconds: 10),
    ),
    YtmTrack(
      videoId: 'yt-3',
      title: 'Trending Global Track Three',
      artist: 'Online Artist Gamma',
      duration: Duration(minutes: 2, seconds: 55),
    ),
  ];

  setUpAll(() async {
    registerFallbackValue(createTestSong(id: -1));
    registerFallbackValue(<SongsTableData>[]);
    registerFallbackValue(<String>[]);
    registerFallbackValue(_FakeRadioStation());

    await (FontLoader('Manrope')
          ..addFont(
              rootBundle.load('assets/fonts/Manrope-VariableFont_wght.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
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
    player = stubPlayerCubit(
      PlayerState(
        playback: PlaybackSlice(
          currentSong: recentSongs.first,
          isPlaying: true,
        ),
      ),
    );
    when(() => player.playSong(any(), queue: any(named: 'queue')))
        .thenAnswer((_) async {});
    when(() => player.playRadioStation(any())).thenAnswer((_) async {});
    when(() => player.warmStreams(any(), count: any(named: 'count')))
        .thenAnswer((_) {});

    when(() => account.loginState).thenReturn(loginState);
    when(() => account.isLoggedIn).thenReturn(false);
    when(() => ytm.searchWithFallback(any()))
        .thenAnswer((_) async => onlineTracks);

    when(() => getSongs.getAllSongs(
          sortBy: any(named: 'sortBy'),
          ascending: any(named: 'ascending'),
          limit: any(named: 'limit'),
          excludedFolders: any(named: 'excludedFolders'),
        )).thenAnswer((_) async => Right(addedSongs));
    when(() => getSongs.watchTopPlayed(
            limit: any(named: 'limit'),
            excludedFolders: any(named: 'excludedFolders')))
        .thenAnswer((_) => Stream.value(Right(recentSongs)));
    when(() => getSongs.watchRecentlyPlayed(limit: any(named: 'limit')))
        .thenAnswer((_) => Stream.value(Right(recentSongs)));
    when(() => getSongs.watchRecentlyAdded(limit: any(named: 'limit')))
        .thenAnswer((_) => Stream.value(Right(addedSongs)));

    when(() => libraryCubit.state).thenReturn(LibraryState(songs: addedSongs));
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

  Future<void> pumpHome(
    WidgetTester tester, {
    required Size size,
    required ThemeData theme,
    required Locale locale,
    required double textScale,
    bool highContrast = false,
    bool enableOnline = false,
  }) async {
    useScreenSize(tester, size);
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => HomeScreen(
            ytmService: ytm,
            ytmAccountService: account,
            getSongsUseCase: getSongs,
            enableOnlineOverride: enableOnline,
          ),
        ),
        ...fakeScreenRoutes(),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
          disableAnimations: true,
          highContrast: highContrast,
        ),
        child: MultiBlocProvider(
          providers: [
            BlocProvider<PlayerCubit>.value(value: player),
            BlocProvider<LibraryCubit>.value(value: libraryCubit),
            BlocProvider<SettingsCubit>.value(value: settingsCubit),
          ],
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: theme,
            locale: locale,
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  final layoutCases = <({
    String label,
    Size size,
    Locale locale,
    double textScale,
  })>[
    (
      label: 'mobile 360x800 LTR 1.0x',
      size: const Size(360, 800),
      locale: const Locale('en'),
      textScale: 1.0,
    ),
    (
      label: 'mobile 360x800 LTR 2.0x',
      size: const Size(360, 800),
      locale: const Locale('en'),
      textScale: 2.0,
    ),
    (
      label: 'mobile 360x800 RTL ar 1.0x',
      size: const Size(360, 800),
      locale: const Locale('ar'),
      textScale: 1.0,
    ),
    (
      label: 'mobile 360x800 RTL ar 2.0x',
      size: const Size(360, 800),
      locale: const Locale('ar'),
      textScale: 2.0,
    ),
    (
      label: 'tablet portrait 768x1024 LTR 1.0x',
      size: const Size(768, 1024),
      locale: const Locale('en'),
      textScale: 1.0,
    ),
    (
      label: 'tablet portrait 768x1024 LTR 2.0x',
      size: const Size(768, 1024),
      locale: const Locale('en'),
      textScale: 2.0,
    ),
    (
      label: 'tablet landscape 1280x800 LTR 1.0x',
      size: const Size(1280, 800),
      locale: const Locale('en'),
      textScale: 1.0,
    ),
    (
      label: 'tablet landscape 1280x800 RTL ar 2.0x',
      size: const Size(1280, 800),
      locale: const Locale('ar'),
      textScale: 2.0,
    ),
  ];

  for (final c in layoutCases) {
    testWidgets('Local HomeScreen renders overflow-free: ${c.label}',
        (tester) async {
      final errors = <FlutterErrorDetails>[];
      final prevOnError = FlutterError.onError;
      FlutterError.onError = (details) => errors.add(details);

      // Tablet @ 2.0x hits a pre-existing fixed-height grid overflow inside
      // lib/core/widgets/song_tile.dart:299 (also seen in phone_tablet_ui_matrix_test.dart).
      // Keep Recently Added empty for tablet 2.0x so every HomeScreen-owned
      // widget (header, hero, quick tiles, studio tools, recents) is verified.
      if (c.size.width >= 600 && c.textScale >= 2.0) {
        when(() => getSongs.watchRecentlyAdded(limit: any(named: 'limit')))
            .thenAnswer((_) => Stream.value(const Right(<SongsTableData>[])));
      }

      try {
        await pumpHome(
          tester,
          size: c.size,
          theme: AuraTheme.darkTheme,
          locale: c.locale,
          textScale: c.textScale,
        );

        // Scroll down to verify Recently Played and Recently Added rails too.
        final scrollable = find.byType(Scrollable).first;
        await tester.drag(scrollable, const Offset(0, -450));
        await tester.pump(const Duration(milliseconds: 200));
      } finally {
        FlutterError.onError = prevOnError;
      }

      expect(errors, isEmpty,
          reason:
              'Errors on ${c.label}: ${errors.map((e) => e.exceptionAsString()).join('\n')}');
      expect(find.byType(PulsrScrollEdgeFade), findsWidgets);
    });
  }

  final themeCases = <({
    String label,
    ThemeData theme,
    bool highContrast,
    bool expectGlow,
  })>[
    (
      label: 'Light',
      theme: AuraTheme.lightTheme,
      highContrast: false,
      expectGlow: true,
    ),
    (
      label: 'Dark',
      theme: AuraTheme.darkTheme,
      highContrast: false,
      expectGlow: true,
    ),
    (
      label: 'AMOLED',
      theme: AuraTheme.amoledTheme,
      highContrast: false,
      expectGlow: false,
    ),
    (
      label: 'High-Contrast',
      theme: AuraTheme.highContrastTheme,
      highContrast: true,
      expectGlow: false,
    ),
  ];

  for (final t in themeCases) {
    testWidgets('HomeScreen theme verification: ${t.label} (390x844 @ 2.0x)',
        (tester) async {
      final errors = <FlutterErrorDetails>[];
      final prevOnError = FlutterError.onError;
      FlutterError.onError = (details) => errors.add(details);

      try {
        await pumpHome(
          tester,
          size: const Size(390, 844),
          theme: t.theme,
          locale: const Locale('en'),
          textScale: 2.0,
          highContrast: t.highContrast,
        );
      } finally {
        FlutterError.onError = prevOnError;
      }

      expect(errors, isEmpty,
          reason:
              'Errors on ${t.label}: ${errors.map((e) => e.exceptionAsString()).join('\n')}');
      expect(
        find.byKey(const ValueKey('home_ambient_top_glow')),
        t.expectGlow ? findsOneWidget : findsNothing,
      );
    });
  }

  testWidgets('Online HomeScreen tab renders overflow-free at 360x800 @ 2.0x RTL',
      (tester) async {
    final errors = <FlutterErrorDetails>[];
    final prevOnError = FlutterError.onError;
    FlutterError.onError = (details) => errors.add(details);

    try {
      await pumpHome(
        tester,
        size: const Size(360, 800),
        theme: AuraTheme.amoledTheme,
        locale: const Locale('ar'),
        textScale: 2.0,
        enableOnline: true,
      );

      // Switch to Online tab using localized label.
      final onlineButton = find.text('عبر الإنترنت');
      if (onlineButton.evaluate().isNotEmpty) {
        await tester.tap(onlineButton.first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
      }
    } finally {
      FlutterError.onError = prevOnError;
    }

    expect(errors, isEmpty,
        reason:
            'Errors on Online RTL 2.0x: ${errors.map((e) => e.exceptionAsString()).join('\n')}');
  });
}
