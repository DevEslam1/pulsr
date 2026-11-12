import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/themes/cassette_player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/player_theme.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import '../../helpers/screen_harness.dart';
import '../../helpers/test_song_factory.dart';

class _MockSettings extends Mock implements SettingsCubit {}

void main() {
  final settings = _MockSettings();
  setUp(() {
    when(() => settings.state).thenReturn(const SettingsState());
    when(() => settings.stream)
        .thenAnswer((_) => const Stream<SettingsState>.empty());
  });

  testWidgets(
      'Cassette: toggle reduce-motion while playing, then change playbackSpeed — no assertion crash, spool stops cleanly',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final cubit = stubPlayerCubit(
      PlayerState(
        playback: PlaybackSlice(
          currentSong: createTestSong(),
          isPlaying: true,
          playbackSpeed: 1.0,
          position: const Duration(minutes: 1),
          duration: const Duration(minutes: 4),
        ),
      ),
    );

    Widget buildApp({required bool reduceMotion, required double speed}) {
      final state = PlayerState(
        playback: PlaybackSlice(
          currentSong: createTestSong(),
          isPlaying: true,
          playbackSpeed: speed,
          position: const Duration(minutes: 1),
          duration: const Duration(minutes: 4),
        ),
      );

      return MultiBlocProvider(
        providers: <BlocProvider>[
          BlocProvider<PlayerCubit>.value(value: cubit),
          BlocProvider<SettingsCubit>.value(value: settings),
        ],
        child: MaterialApp(
          theme: AuraTheme.darkTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(390, 844),
              disableAnimations: reduceMotion,
            ),
            child: Scaffold(
              body: CassettePlayerTheme(
                props: PlayerThemeProps(
                  state: state,
                  cubit: cubit,
                  activeColor: const Color(0xFF7C4DFF),
                  bgColor: const Color(0xFF0A0C12),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // 1. Start with animations enabled
    await tester.pumpWidget(buildApp(reduceMotion: false, speed: 1.0));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    dynamic cassetteState = tester.state(find.byType(CassettePlayerTheme));
    expect(cassetteState.isSpoolAnimating, isTrue,
        reason: 'Spool should be animating when motion is enabled and playing');

    // 2. Toggle reduce motion ON while playing
    await tester.pumpWidget(buildApp(reduceMotion: true, speed: 1.0));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    cassetteState = tester.state(find.byType(CassettePlayerTheme));
    expect(cassetteState.isSpoolAnimating, isFalse,
        reason: 'Spool animation must be stopped when reduce-motion is active');

    // 3. Change playback speed while reduce motion is active
    // Previously, this called _spoolController.repeat() with duration zero -> assertion crash
    await tester.pumpWidget(buildApp(reduceMotion: true, speed: 1.5));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    cassetteState = tester.state(find.byType(CassettePlayerTheme));
    expect(cassetteState.isSpoolAnimating, isFalse,
        reason: 'Spool must remain stopped and not throw any exception');

    // 4. Toggle reduce motion back OFF -> spool restarts cleanly
    await tester.pumpWidget(buildApp(reduceMotion: false, speed: 1.5));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    cassetteState = tester.state(find.byType(CassettePlayerTheme));
    expect(cassetteState.isSpoolAnimating, isTrue,
        reason: 'Spool should resume animating when motion is re-enabled');
  });
}
