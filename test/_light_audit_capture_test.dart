// TEMPORARY light-mode audit capture (not part of the suite).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';
import 'package:pulsr/features/auth/cubit/auth_cubit.dart';
import 'package:pulsr/features/auth/cubit/auth_state.dart';
import 'package:pulsr/features/library/cubit/library_cubit.dart';
import 'package:pulsr/features/library/cubit/library_state.dart';
import 'package:pulsr/features/library/presentation/library_screen.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/themes/player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/theme_registry.dart';
import 'package:pulsr/features/player/presentation/responsive_player_layout.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/features/settings/presentation/settings_screen.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'features/library/library_test_harness.dart' as lib;

class MockScanner extends Mock implements MediaScannerService {}
class MockAuthCubit extends Mock implements AuthCubit {}

Widget _wrap(Widget child, ThemeData theme, Size size) => MediaQuery(
      data: MediaQueryData(size: size, disableAnimations: true),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    );

void main() {
  final light = AuraTheme.lightTheme;

  setUpAll(() async {
    lib.registerLibraryFallbacks();
    await (FontLoader('Manrope')
          ..addFont(rootBundle.load('assets/fonts/Manrope-VariableFont_wght.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });

  setUp(() {
    for (final c in [
      PulsrChannels.hiresDac,
      PulsrChannels.audioEffects,
      PulsrChannels.hiresDacEvents,
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(c), (call) async => null);
    }
  });

  SongsTableData song(int id, String t, String a, String al, {bool fav = false}) =>
      lib.testSong(
        id: id,
        title: t,
        artist: a,
        album: al,
        isFavorite: fav,
        path: '/music/$al/$t.flac',
        albumId: id,
      );

  testWidgets('light settings dashboard', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({'settings_last_selected_category': 'all'});
    SettingsScreenController.resetSessionCategory();

    final player = lib.stubPlayerCubit();
    final auth = MockAuthCubit();
    when(() => auth.state).thenReturn(const AuthState());
    when(() => auth.stream).thenAnswer((_) => const Stream.empty());
    final settings = SettingsCubit(scannerService: MockScanner());

    await tester.pumpWidget(RepaintBoundary(
      key: const ValueKey('cap'),
      child: MultiBlocProvider(
        providers: [
          BlocProvider<SettingsCubit>.value(value: settings),
          BlocProvider<PlayerCubit>.value(value: player),
          BlocProvider<AuthCubit>.value(value: auth),
        ],
        child: _wrap(const SettingsScreen(), light, const Size(390, 1400)),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await expectLater(find.byKey(const ValueKey('cap')),
        matchesGoldenFile('light_captures/settings.png'));
    await tester.pumpWidget(const SizedBox.shrink());
    await settings.close();
  });

  testWidgets('light library', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final songs = [
      song(1, 'Midnight Drive', 'Aura Soundworks', 'Neon Nights', fav: true),
      song(2, 'Glass Horizon', 'Kite & Co.', 'Paper Skies'),
      song(3, 'Slow Motion', 'Marisol Vega', 'Saltwater'),
      song(4, 'Afterglow', 'The Lantern Club', 'Static Bloom', fav: true),
      song(5, 'Northbound', 'Yuki Sato', 'Transit'),
      song(6, 'Hollow Sun', 'Aura Soundworks', 'Neon Nights'),
    ];
    final cubit = lib.stubLibraryCubit(
        LibraryState(songs: songs, favorites: songs.where((s) => s.isFavorite).toList()));

    await tester.pumpWidget(RepaintBoundary(
      key: const ValueKey('cap'),
      child: MultiBlocProvider(
        providers: [
          BlocProvider<LibraryCubit>.value(value: cubit),
          BlocProvider<PlayerCubit>.value(value: lib.stubPlayerCubit()),
          BlocProvider<SettingsCubit>.value(value: lib.stubSettingsCubit()),
        ],
        child: _wrap(const LibraryScreen(), light, const Size(390, 844)),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await expectLater(find.byKey(const ValueKey('cap')),
        matchesGoldenFile('light_captures/library.png'));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('light now playing', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = song(7, 'Midnight Drive', 'Aura Soundworks', 'Neon Nights', fav: true);
    final player = lib.stubPlayerCubit(
      PlayerState(
        playback: PlaybackSlice(
          currentSong: s,
          isPlaying: true,
          position: const Duration(seconds: 96),
          duration: const Duration(minutes: 3, seconds: 56),
        ),
      ),
    );
    final props = PlayerThemeProps(
      state: player.state,
      cubit: player,
      activeColor: const Color(0xFF3B5BDB),
      bgColor: Colors.white,
    );

    await tester.pumpWidget(RepaintBoundary(
      key: const ValueKey('cap'),
      child: MultiBlocProvider(
        providers: [
          BlocProvider<PlayerCubit>.value(value: player),
          BlocProvider<SettingsCubit>.value(value: lib.stubSettingsCubit()),
        ],
        child: _wrap(
          Scaffold(
            body: ResponsivePlayerLayout(
              state: props.state,
              cubit: props.cubit,
              themeWidget: ThemeRegistry.build(PlayerThemeMode.classic, props),
              activeColor: const Color(0xFF3B5BDB),
              bgColor: Colors.white,
            ),
          ),
          light,
          const Size(390, 844),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await expectLater(find.byKey(const ValueKey('cap')),
        matchesGoldenFile('light_captures/now_playing.png'));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

