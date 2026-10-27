// TEMPORARY audit harness — screens + stress cases.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/auth/cubit/auth_cubit.dart';
import 'package:pulsr/features/auth/cubit/auth_state.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/themes/player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/theme_registry.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/features/settings/presentation/settings_screen.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import 'helpers/screen_harness.dart';
import 'helpers/test_song_factory.dart';

class _MockSettings extends Mock implements SettingsCubit {}

class _MockAuth extends Mock implements AuthCubit {}

Widget _app(Widget home, {double textScale = 1.0}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [GoRoute(path: '/', builder: (_, __) => home)],
  );
  return MediaQuery(
    data: MediaQueryData(
      size: const Size(390, 844),
      textScaler: TextScaler.linear(textScale),
    ),
    child: MaterialApp.router(
      theme: AuraTheme.darkTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
}

void main() {
  setUpAll(() async {
    final manrope = File('assets/fonts/Manrope-VariableFont_wght.ttf');
    if (manrope.existsSync()) {
      final loader = FontLoader('Manrope')
        ..addFont(Future.value(manrope.readAsBytesSync().buffer.asByteData()));
      await loader.load();
    }
    final flutterRoot = Platform.environment['FLUTTER_ROOT'] ??
        r'D:\Courses\work\dev\flutter';
    final icons = File(
        '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      final loader = FontLoader('MaterialIcons')
        ..addFont(Future.value(icons.readAsBytesSync().buffer.asByteData()));
      await loader.load();
    }
  });
  final settings = _MockSettings();
  final auth = _MockAuth();
  setUp(() {
    when(() => auth.state).thenReturn(const AuthState());
    when(() => auth.stream)
        .thenAnswer((_) => const Stream<AuthState>.empty());
    when(() => settings.state).thenReturn(const SettingsState());
    when(() => settings.stream)
        .thenAnswer((_) => const Stream<SettingsState>.empty());
    when(() => settings.clearError()).thenReturn(null);
  });

  testWidgets('settings screen', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiBlocProvider(
      providers: <BlocProvider>[
        BlocProvider<SettingsCubit>.value(value: settings),
        BlocProvider<AuthCubit>.value(value: auth),
      ],
      child: _app(const SettingsScreen()),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('../audit/shots/screen_settings.png'));
  });

  for (final entry in {
    'phone_320': const Size(320, 568),
    'text_200': const Size(390, 844),
  }.entries) {
    testWidgets('classic ${entry.key}', (tester) async {
      tester.view.physicalSize = entry.value;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final state = PlayerState(
        playback: PlaybackSlice(
          currentSong: createTestSong(
            title: 'A Very Long Track Title That Should Truncate Gracefully',
            artist: 'The Extremely Long Artist Name Collective',
            album: 'An Album With A Rather Long Name Too',
          ),
          isPlaying: true,
          position: const Duration(minutes: 2, seconds: 14),
          duration: const Duration(minutes: 4, seconds: 38),
        ),
      );
      final cubit = stubPlayerCubit(state);
      await tester.pumpWidget(MultiBlocProvider(
        providers: <BlocProvider>[
          BlocProvider<SettingsCubit>.value(value: settings),
          BlocProvider<PlayerCubit>.value(value: cubit),
        ],
        child: _app(
          Scaffold(
            body: ThemeRegistry.build(
              PlayerThemeMode.classic,
              PlayerThemeProps(
                state: state,
                cubit: cubit,
                activeColor: const Color(0xFF7C4DFF),
                bgColor: const Color(0xFF0A0C12),
              ),
            ),
          ),
          textScale: entry.key == 'text_200' ? 2.0 : 1.0,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('../audit/shots/classic_${entry.key}.png'));
    });
  }
}
