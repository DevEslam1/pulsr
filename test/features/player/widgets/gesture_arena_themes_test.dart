import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/dynamic_theme_cubit.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/now_playing_screen.dart';
import 'package:pulsr/features/player/presentation/widgets/player_gesture_scope.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/screen_harness.dart';
import '../../../helpers/test_song_factory.dart';

import 'package:pulsr/l10n/app_localizations_delegates.dart';
class _MockSettingsCubit extends Mock implements SettingsCubit {}

class _MockDynamicThemeCubit extends Mock implements DynamicThemeCubit {}

class _CountingNavigatorObserver extends NavigatorObserver {
  int popCount = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popCount++;
    super.didPop(route, previousRoute);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    registerFallbackValue(Duration.zero);
  });

  const platterThemes = <PlayerThemeMode>{
    PlayerThemeMode.vinyl,
    PlayerThemeMode.cd,
    PlayerThemeMode.circle,
    PlayerThemeMode.waveform,
  };

  group('Gesture arena across all 11 player themes', () {
    for (final mode in PlayerThemeMode.values) {
      testWidgets(
        '${mode.name}: vertical dismiss vs platter pan vs horizontal swipe never double-fires',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          Future<
              ({
                PlayerCubit player,
                _CountingNavigatorObserver observer,
              })> pumpScreen() async {
            final song = createTestSong(id: 7, durationMs: 240000);
            final player = stubPlayerCubit(
              PlayerState(
                playback: PlaybackSlice(
                  currentSong: song,
                  isPlaying: true,
                  position: const Duration(seconds: 60),
                  duration: const Duration(minutes: 4),
                ),
                queueSlice: QueueSlice(
                  queue: [song, createTestSong(id: 8)],
                  currentIndex: 0,
                ),
              ),
            );
            when(() => player.next()).thenAnswer((_) async {});
            when(() => player.previous()).thenAnswer((_) async {});
            when(() => player.seek(any())).thenAnswer((_) async {});
            when(() => player.togglePlayPause()).thenAnswer((_) async {});
            when(() => player.toggleFavorite(any())).thenAnswer((_) async {});
            when(() => player.toggleLyricsVisibility()).thenReturn(null);
            when(() => player.resetOverlayViews()).thenReturn(null);

            final settings = _MockSettingsCubit();
            final settingsState = SettingsState(
              playerThemeMode: mode,
              themeColorSource: ThemeColorSource.custom,
            );
            when(() => settings.state).thenReturn(settingsState);
            when(() => settings.stream)
                .thenAnswer((_) => const Stream<SettingsState>.empty());

            final dynamicTheme = _MockDynamicThemeCubit();
            when(() => dynamicTheme.state)
                .thenReturn(const DynamicThemeState());
            when(() => dynamicTheme.stream)
                .thenAnswer((_) => const Stream<DynamicThemeState>.empty());

            final observer = _CountingNavigatorObserver();
            final navKey = GlobalKey<NavigatorState>();

            await tester.pumpWidget(
              MultiBlocProvider(
                providers: [
                  BlocProvider<PlayerCubit>.value(value: player),
                  BlocProvider<SettingsCubit>.value(value: settings),
                  BlocProvider<DynamicThemeCubit>.value(value: dynamicTheme),
                ],
                child: MaterialApp(
                  localizationsDelegates:
                      appLocalizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  navigatorKey: navKey,
                  navigatorObservers: [observer],
                  home: const Scaffold(body: Text('Root')),
                ),
              ),
            );

            navKey.currentState!.push(
              MaterialPageRoute<void>(
                builder: (_) => const NowPlayingScreen(),
              ),
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 350));

            return (player: player, observer: observer);
          }

          // 1. Vertical downward fling dismisses cleanly once without horizontal skip or seek.
          final verticalRun = await pumpScreen();
          await tester.fling(
            find.byType(NowPlayingScreen),
            const Offset(0, 260),
            900,
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 350));
          expect(verticalRun.observer.popCount, 1);
          verifyNever(() => verticalRun.player.next());
          verifyNever(() => verticalRun.player.previous());
          verifyNever(() => verticalRun.player.seek(any()));

          // 2. Horizontal swipe on stage/scope never triggers vertical dismiss or seek.
          final horizRun = await pumpScreen();
          final scopeFinder = find.byType(PlayerGestureScope);
          if (scopeFinder.evaluate().isNotEmpty) {
            final scopeRect = tester.getRect(scopeFinder.first);
            final swipePoint = Offset(
              scopeRect.left + 20,
              scopeRect.center.dy,
            );
            await tester.flingFrom(swipePoint, const Offset(-200, 0), 900);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 150));
            expect(horizRun.observer.popCount, 0);
            if (!platterThemes.contains(mode)) {
              verify(() => horizRun.player.next()).called(1);
            }
          }

          // 3. Platter / stage pan on platter themes never double-fires dismiss or track skip.
          if (platterThemes.contains(mode)) {
            final panRun = await pumpScreen();
            final targetFinder = scopeFinder.evaluate().isNotEmpty
                ? scopeFinder.first
                : find.byType(NowPlayingScreen);
            final center = tester.getCenter(targetFinder);
            final g =
                await tester.startGesture(Offset(center.dx + 40, center.dy));
            await g.moveBy(const Offset(0, 80));
            await g.moveBy(const Offset(-80, 0));
            await g.up();
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 150));

            expect(panRun.observer.popCount, 0);
            verifyNever(() => panRun.player.next());
            verifyNever(() => panRun.player.previous());
          }
        },
      );
    }
  });
}
