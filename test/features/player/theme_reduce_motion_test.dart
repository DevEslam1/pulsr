import 'package:flutter/material.dart';
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

import '../../helpers/screen_harness.dart';
import '../../helpers/test_song_factory.dart';

class _MockSettings extends Mock implements SettingsCubit {}

/// Reduce Motion is a promise, not a preference: every theme must snap to its
/// resting state and leave no ticker running. `transientCallbackCount` is the
/// number of scheduled frame callbacks, so zero means nothing is animating.
void main() {
  final settings = _MockSettings();
  setUp(() {
    when(() => settings.state).thenReturn(const SettingsState());
    when(() => settings.stream)
        .thenAnswer((_) => const Stream<SettingsState>.empty());
  });

  PlayerState buildState() => PlayerState(
        playback: PlaybackSlice(
          currentSong: createTestSong(),
          isPlaying: true,
          position: const Duration(minutes: 1),
          duration: const Duration(minutes: 4),
        ),
      );

  Future<void> pumpTheme(
    WidgetTester tester,
    PlayerThemeMode mode, {
    required bool reduceMotion,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final state = buildState();
    final cubit = stubPlayerCubit(state);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: <BlocProvider>[
          BlocProvider<PlayerCubit>.value(value: cubit),
          BlocProvider<SettingsCubit>.value(value: settings),
        ],
        child: MediaQuery(
          data: MediaQueryData(
            size: const Size(390, 844),
            disableAnimations: reduceMotion,
          ),
          child: MaterialApp(
            theme: AuraTheme.darkTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
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
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));
  }

  for (final mode in PlayerThemeMode.values) {
    testWidgets('${mode.name}: no ticker under Reduce Motion', (tester) async {
      await pumpTheme(tester, mode, reduceMotion: true);

      expect(tester.takeException(), isNull);
      expect(
        tester.binding.transientCallbackCount,
        0,
        reason: '${mode.name} keeps animating with Reduce Motion enabled',
      );
    });
  }

  testWidgets('control: vinyl does animate when motion is allowed',
      (tester) async {
    await pumpTheme(tester, PlayerThemeMode.vinyl, reduceMotion: false);
    expect(
      tester.binding.transientCallbackCount,
      greaterThan(0),
      reason: 'The test would be vacuous if no theme ever animates',
    );
  });
}
