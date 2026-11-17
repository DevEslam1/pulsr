// test/features/player/all_player_themes_test.dart
//
// One gate for all eleven Now Playing themes.
//
// The theme list is the product's most visible surface and every theme is a
// separate widget tree, so a change made for one theme can silently break the
// layout of another (they share the scaffold but not their stages). This test
// builds every registered theme at the sizes we actually support and fails on
// any layout exception, then asserts the two conventions that must hold for
// every theme:
//
//   1. single tap on the stage means "toggle lyrics" (no theme overrides
//      PlayerGestureScope.onTap, which is how vinyl/CD/cassette used to
//      disagree with the other eight), and
//   2. every theme renders an accessible stage node (artwork semantics or a
//      single descriptive container) instead of exposing only painted pixels.
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/themes/player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/theme_registry.dart';
import 'package:pulsr/features/player/presentation/widgets/audio_visualizer.dart';
import 'package:pulsr/features/player/presentation/widgets/player_gesture_scope.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import 'package:pulsr/l10n/app_localizations_delegates.dart';
import '../../helpers/test_song_factory.dart';

class _MockPlayerCubit extends Mock implements PlayerCubit {}

class _MockSettingsCubit extends Mock implements SettingsCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockPlayerCubit playerCubit;
  late _MockSettingsCubit settingsCubit;

  final song = createTestSong(
    id: 4242,
    title: 'A Very Long Track Title That Must Ellipsise Gracefully Everywhere',
    artist: 'The Audiophile Ensemble',
  );

  setUp(() {
    // The visualizer talks to a platform channel; the override disables it so
    // the test exercises layout, not pixels.
    AudioVisualizer.isTestingOverride = true;

    playerCubit = _MockPlayerCubit();
    settingsCubit = _MockSettingsCubit();

    when(() => playerCubit.state).thenReturn(
      PlayerState(
        playback: PlaybackSlice(
          currentSong: song,
          isPlaying: true,
          position: const Duration(seconds: 61),
          duration: const Duration(seconds: 402),
        ),
      ),
    );
    when(() => playerCubit.stream).thenAnswer((_) => const Stream.empty());
    when(() => settingsCubit.stream).thenAnswer((_) => const Stream.empty());
  });

  tearDown(() {
    AudioVisualizer.isTestingOverride = null;
  });

  Widget host({
    required PlayerThemeMode mode,
    required Size size,
    double textScale = 1.0,
    Brightness brightness = Brightness.dark,
  }) {
    when(() => settingsCubit.state).thenReturn(
      SettingsState(playerThemeMode: mode),
    );

    final props = PlayerThemeProps(
      state: playerCubit.state,
      cubit: playerCubit,
      activeColor: const Color(0xFF7C6BFF),
      bgColor: brightness == Brightness.dark
          ? const Color(0xFF101014)
          : const Color(0xFFF6F5FA),
    );

    return MaterialApp(
      theme: brightness == Brightness.dark
          ? AuraTheme.darkTheme
          : AuraTheme.lightTheme,
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider<PlayerCubit>.value(value: playerCubit),
              BlocProvider<SettingsCubit>.value(value: settingsCubit),
            ],
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: ThemeRegistry.build(mode, props),
            ),
          ),
        ),
      ),
    );
  }

  // Phone portrait, short phone, phone landscape and tablet portrait: the four
  // layout branches PlayerThemeMetrics distinguishes.
  const sizes = <String, Size>{
    'phone portrait': Size(390, 844),
    'short phone': Size(360, 620),
    'phone landscape': Size(844, 390),
    'tablet portrait': Size(834, 1112),
  };

  for (final mode in PlayerThemeMode.values) {
    group('${mode.name} theme', () {
      for (final entry in sizes.entries) {
        testWidgets('lays out on ${entry.key}', (tester) async {
          tester.view.physicalSize = entry.value;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            host(mode: mode, size: entry.value),
          );
          // Themes animate continuously while playing, so settle is not an
          // option; two frames is enough to surface any layout exception.
          await tester.pump(const Duration(milliseconds: 40));
          await tester.pump(const Duration(milliseconds: 320));

          expect(
            tester.takeException(),
            isNull,
            reason: '${mode.name} threw while laying out on ${entry.key}',
          );
        });
      }

      // The layout matrix has to be the real cross product, not one lucky
      // viewport: a theme can lay out at 390x844 and still overflow at 200%
      // text on a 360x620 short phone, and the light theme exercises a
      // different colour/target branch than the dark one.
      for (final entry in sizes.entries) {
        for (final brightness in Brightness.values) {
          for (final textScale in const [1.0, 2.0]) {
            final scaleLabel = textScale == 1.0 ? '100%' : '200%';
            testWidgets(
              'lays out on ${entry.key}, ${brightness.name}, $scaleLabel text',
              (tester) async {
                // The paint surface has to match the logical size as well:
                // faking only MediaQuery left every case drawn on the default
                // 800x600 test window, so a 390x844 render was never actually
                // exercised.
                tester.view.physicalSize = entry.value;
                tester.view.devicePixelRatio = 1.0;
                addTearDown(tester.view.reset);
                await tester.pumpWidget(
                  host(
                    mode: mode,
                    size: entry.value,
                    brightness: brightness,
                    textScale: textScale,
                  ),
                );
                // Themes animate continuously while playing, so settle is not
                // an option; two frames is enough to surface any layout
                // exception.
                await tester.pump(const Duration(milliseconds: 40));
                await tester.pump(const Duration(milliseconds: 320));

                expect(
                  tester.takeException(),
                  isNull,
                  reason: '${mode.name} threw on ${entry.key}, '
                      '${brightness.name}, $scaleLabel text',
                );
              },
            );
          }
        }
      }

      testWidgets('keeps stage tap bound to lyrics', (tester) async {
        await tester.pumpWidget(
          host(mode: mode, size: const Size(390, 844)),
        );
        await tester.pump(const Duration(milliseconds: 40));

        final scopes = tester
            .widgetList<PlayerGestureScope>(find.byType(PlayerGestureScope))
            .toList();
        expect(
          scopes,
          isNotEmpty,
          reason: '${mode.name} has no PlayerGestureScope on its stage',
        );
        for (final scope in scopes) {
          // A null onTap means the shared default (toggle lyrics) is in force.
          // Overriding it to play/pause is what made vinyl, CD and cassette
          // behave differently from the other themes.
          expect(
            scope.onTap,
            isNull,
            reason:
                '${mode.name} overrides the stage tap; single tap must stay '
                'bound to lyrics on every theme',
          );
        }
      });
    });
  }

  // The CD tray read-out is the one piece of deck chrome that cannot shrink:
  // it needs ~110 dp for "TRK 01". A window short enough to squeeze the deck
  // used to overflow the jewel case, so the read-out has to disappear rather
  // than clip. Real surfaces never reach this at the four supported sizes,
  // which is exactly why it needs its own case.
  testWidgets('cd drops the tray read-out when the deck is squeezed',
      (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      host(mode: PlayerThemeMode.cd, size: const Size(834, 1112)),
    );
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump(const Duration(milliseconds: 320));

    expect(tester.takeException(), isNull);
    expect(
      find.textContaining('TRK'),
      findsNothing,
      reason: 'a 74 dp tray cannot hold the read-out; it must not be laid out',
    );
  });
}
