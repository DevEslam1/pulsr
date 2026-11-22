// test/features/player/now_playing_wave2b_test.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/errors/app_error.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/theme/dynamic_theme_cubit.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/mini_player.dart';
import 'package:pulsr/features/player/presentation/now_playing_screen.dart';
import 'package:pulsr/features/player/presentation/themes/player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/theme_registry.dart';
import 'package:pulsr/features/player/presentation/widgets/audio_visualizer.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/l10n/app_localizations_delegates.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import '../../helpers/screen_harness.dart';
import '../../helpers/test_song_factory.dart';

class _MockSettingsCubit extends Mock implements SettingsCubit {}

class _MockDynamicThemeCubit extends Mock implements DynamicThemeCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockSettingsCubit settingsCubit;
  late _MockDynamicThemeCubit dynamicThemeCubit;

  final testSong = createTestSong(
    id: 777,
    title: 'Symphony No. 9 in D Minor — Extended Audiophile Edition',
    artist: 'The Philharmonic Orchestra & Studio Chorus',
    album: 'Master Reference Recordings Vol. IV',
    durationMs: 265000,
  );

  PlayerState playingState({AppError? error}) => PlayerState(
        playback: PlaybackSlice(
          currentSong: testSong,
          isPlaying: true,
          position: const Duration(minutes: 1, seconds: 12),
          duration: const Duration(minutes: 4, seconds: 25),
          error: error,
        ),
        queueSlice: QueueSlice(
          queue: [testSong],
          currentIndex: 0,
        ),
      );

  setUp(() {
    AudioVisualizer.isTestingOverride = true;
    settingsCubit = _MockSettingsCubit();
    dynamicThemeCubit = _MockDynamicThemeCubit();
    when(() => settingsCubit.state).thenReturn(const SettingsState());
    when(() => settingsCubit.stream)
        .thenAnswer((_) => const Stream<SettingsState>.empty());
    when(() => dynamicThemeCubit.state).thenReturn(const DynamicThemeState());
    when(() => dynamicThemeCubit.stream)
        .thenAnswer((_) => const Stream<DynamicThemeState>.empty());
    when(() => dynamicThemeCubit.updateFromSong(any()))
        .thenAnswer((_) async {});
  });

  tearDown(() {
    AudioVisualizer.isTestingOverride = null;
  });

  group('Reduced motion via PulsrMotion.shouldAnimate (in-app reduceMotion)',
      () {
    for (final mode in const [
      PlayerThemeMode.vinyl,
      PlayerThemeMode.cd,
      PlayerThemeMode.milkdrop,
    ]) {
      testWidgets(
        '${mode.name} halts tickers when SettingsState.reduceMotion is true',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          when(() => settingsCubit.state).thenReturn(
            SettingsState(
              playerThemeMode: mode,
              reduceMotion: true,
              visualizerStyle: VisualizerStyle.milkdrop,
            ),
          );

          final state = playingState();
          final playerCubit = stubPlayerCubit(state);

          await tester.pumpWidget(
            MultiBlocProvider(
              providers: [
                BlocProvider<PlayerCubit>.value(value: playerCubit),
                BlocProvider<SettingsCubit>.value(value: settingsCubit),
              ],
              child: MaterialApp(
                theme: AuraTheme.darkTheme,
                localizationsDelegates: appLocalizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: Scaffold(
                  body: ThemeRegistry.build(
                    mode,
                    PlayerThemeProps(
                      state: state,
                      cubit: playerCubit,
                      activeColor: const Color(0xFF7C6BFF),
                      bgColor: const Color(0xFF0E0E14),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 250));

          expect(tester.takeException(), isNull);
          expect(
            tester.binding.transientCallbackCount,
            0,
            reason:
                '${mode.name} kept animating despite SettingsState.reduceMotion=true',
          );
          if (mode == PlayerThemeMode.milkdrop) {
            expect(
              find.byType(AudioVisualizer),
              findsNothing,
              reason:
                  'Milkdrop must fall back to static ambient backdrop under reduced motion',
            );
          }
        },
      );
    }

    testWidgets(
      'MiniPlayer halts animations when SettingsState.reduceMotion is true',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        when(() => settingsCubit.state).thenReturn(
          const SettingsState(
            playerThemeMode: PlayerThemeMode.vinyl,
            reduceMotion: true,
          ),
        );

        final playerCubit = stubPlayerCubit(playingState());

        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<PlayerCubit>.value(value: playerCubit),
              BlocProvider<SettingsCubit>.value(value: settingsCubit),
            ],
            child: MaterialApp(
              theme: AuraTheme.darkTheme,
              localizationsDelegates: appLocalizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: MiniPlayer(onTap: () {}),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 250));

        expect(tester.takeException(), isNull);
        expect(tester.binding.transientCallbackCount, 0);
      },
    );
  });

  group('1.3x and 1.6x text scale zero-overflow on NowPlayingScreen & MiniPlayer',
      () {
    for (final textScale in const [1.3, 1.6]) {
      testWidgets(
        'NowPlayingScreen renders without overflow at ${textScale}x text scale',
        (tester) async {
          const size = Size(390, 844);
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          final playerCubit = stubPlayerCubit(playingState());

          for (final mode in const [
            PlayerThemeMode.clean,
            PlayerThemeMode.vinyl,
            PlayerThemeMode.cd,
            PlayerThemeMode.milkdrop,
          ]) {
            when(() => settingsCubit.state).thenReturn(
              SettingsState(
                playerThemeMode: mode,
                reduceMotion: true,
              ),
            );

            await tester.pumpWidget(
              MultiBlocProvider(
                providers: [
                  BlocProvider<PlayerCubit>.value(value: playerCubit),
                  BlocProvider<SettingsCubit>.value(value: settingsCubit),
                  BlocProvider<DynamicThemeCubit>.value(
                      value: dynamicThemeCubit),
                ],
                child: MaterialApp(
                  theme: AuraTheme.darkTheme,
                  localizationsDelegates: appLocalizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: MediaQuery(
                    data: MediaQueryData(
                      size: size,
                      textScaler: TextScaler.linear(textScale),
                    ),
                    child: const NowPlayingScreen(),
                  ),
                ),
              ),
            );
            await tester.pump(const Duration(milliseconds: 200));

            expect(
              tester.takeException(),
              isNull,
              reason:
                  'NowPlayingScreen (${mode.name}) overflowed at ${textScale}x text scale',
            );
          }
        },
      );

      testWidgets(
        'MiniPlayer compact, error bar, and horizontal render without overflow at ${textScale}x',
        (tester) async {
          const size = Size(390, 844);
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          final playerCubit = stubPlayerCubit(
            playingState(
              error: const AudioError(
                code: 'decode_failed',
                userMessage: 'Unable to decode stream — tap retry to reconnect',
              ),
            ),
          );
          when(() => settingsCubit.state).thenReturn(
            const SettingsState(reduceMotion: true),
          );

          await tester.pumpWidget(
            MultiBlocProvider(
              providers: [
                BlocProvider<PlayerCubit>.value(value: playerCubit),
                BlocProvider<SettingsCubit>.value(value: settingsCubit),
              ],
              child: MaterialApp(
                theme: AuraTheme.darkTheme,
                localizationsDelegates: appLocalizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: MediaQuery(
                  data: MediaQueryData(
                    size: size,
                    textScaler: TextScaler.linear(textScale),
                  ),
                  child: Scaffold(
                    body: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        MiniPlayerHorizontal(onTap: () {}),
                        const SizedBox(height: 16),
                        MiniPlayer(onTap: () {}),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 200));

          expect(
            tester.takeException(),
            isNull,
            reason: 'MiniPlayer overflowed at ${textScale}x text scale',
          );
          expect(find.byType(MiniPlayer), findsOneWidget);
          expect(find.byType(MiniPlayerHorizontal), findsOneWidget);
          expect(find.byType(MiniPlayerErrorBar), findsOneWidget);
        },
      );
    }
  });
}
