// TEMPORARY audit harness — renders player themes to PNG for visual review.
// Run explicitly with: flutter test test/_audit_visual.dart --update-goldens
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/themes/player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/theme_registry.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import 'helpers/screen_harness.dart';
import 'helpers/test_song_factory.dart';

void main() {
  setUpAll(() async {
    await _loadFonts();
  });

  final song = createTestSong(
    title: 'Midnight City Lights',
    artist: 'Aurora Vale',
    album: 'Neon Horizons',
  );

  final state = PlayerState(
    playback: PlaybackSlice(
      currentSong: song,
      isPlaying: true,
      position: const Duration(minutes: 2, seconds: 14),
      duration: const Duration(minutes: 4, seconds: 38),
      dominantColor: const Color(0xFF7C4DFF),
    ),
  );

  final cubit = stubPlayerCubit(state);
  final settings = _MockSettings();
  when(() => settings.state).thenReturn(const SettingsState());
  when(() => settings.stream)
      .thenAnswer((_) => const Stream<SettingsState>.empty());

  for (final mode in PlayerThemeMode.values) {
    testWidgets('render ${mode.name}', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(size: Size(390, 844)),
        child: MaterialApp(
          theme: AuraTheme.darkTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MultiBlocProvider(
            providers: [
              BlocProvider<SettingsCubit>.value(value: settings),
              BlocProvider<PlayerCubit>.value(value: cubit),
            ],
            child: Scaffold(
              body: ThemeRegistry.build(
                mode,
                PlayerThemeProps(
                  state: state,
                  cubit: cubit,
                  activeColor: const Color(0xFF7C4DFF),
                  bgColor: const Color(0xFF0A0C12),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../audit/shots/theme_${mode.name}.png'),
      );
    });
  }
}

class _MockSettings extends Mock implements SettingsCubit {}

Future<void> _loadFonts() async {
  final manrope = File('assets/fonts/Manrope-VariableFont_wght.ttf');
  if (manrope.existsSync()) {
    final loader = FontLoader('Manrope')
      ..addFont(Future.value(manrope.readAsBytesSync().buffer.asByteData()));
    await loader.load();
  }
  final root =
      Platform.environment['FLUTTER_ROOT'] ?? r'D:\Courses\work\dev\flutter';
  final icons = File(
      '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    final loader = FontLoader('MaterialIcons')
      ..addFont(Future.value(icons.readAsBytesSync().buffer.asByteData()));
    await loader.load();
  }
}
