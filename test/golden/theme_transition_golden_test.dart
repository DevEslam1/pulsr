// test/golden/theme_transition_golden_test.dart
import 'dart:io';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/themes/player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/theme_registry.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import 'package:pulsr/l10n/app_localizations_delegates.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}

class MockSettingsCubit extends Mock implements SettingsCubit {}

const _goldenSong = SongsTableData(
  id: 101,
  title: 'Golden Crossfade',
  artist: 'Pulsr Symphony',
  album: 'Transition Fidelity',
  durationMs: 240000,
  path: '/music/golden.flac',
  dateAdded: 0,
  playCount: 5,
  lastPositionMs: 30000,
  isFavorite: true,
  isMissing: false,
  source: 'local',
  isDownloaded: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  bool goldenExists(String name) =>
      File('test/golden/goldens/$name').existsSync();

  late MockPlayerCubit mockPlayerCubit;
  late MockSettingsCubit mockSettingsCubit;

  setUp(() {
    mockPlayerCubit = MockPlayerCubit();
    mockSettingsCubit = MockSettingsCubit();

    when(() => mockPlayerCubit.state).thenReturn(
      const PlayerState(
        playback: PlaybackSlice(
          currentSong: _goldenSong,
          isPlaying: true,
          duration: Duration(minutes: 4),
          position: Duration(seconds: 30),
        ),
      ),
    );
    when(() => mockPlayerCubit.stream)
        .thenAnswer((_) => const Stream<PlayerState>.empty());

    when(() => mockSettingsCubit.state).thenReturn(const SettingsState());
    when(() => mockSettingsCubit.stream)
        .thenAnswer((_) => const Stream<SettingsState>.empty());
  });

  testWidgets(
      'Theme switching crossfades smoothly mid-transition with continuity',
      (tester) async {
    final modeNotifier = ValueNotifier<PlayerThemeMode>(PlayerThemeMode.clean);

    final props = PlayerThemeProps(
      state: mockPlayerCubit.state,
      cubit: mockPlayerCubit,
      activeColor: const Color(0xFF00E5FF),
      bgColor: const Color(0xFF141414),
    );

    Widget buildTransitionHarness() {
      return MultiBlocProvider(
        providers: [
          BlocProvider<PlayerCubit>.value(value: mockPlayerCubit),
          BlocProvider<SettingsCubit>.value(value: mockSettingsCubit),
        ],
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData.dark().copyWith(
            extensions: [AuraTheme.defaultDark],
          ),
          home: Scaffold(
            body: ValueListenableBuilder<PlayerThemeMode>(
              valueListenable: modeNotifier,
              builder: (context, activeMode, _) {
                return RepaintBoundary(
                  key: const ValueKey('theme_transition_boundary'),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 380),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      final scale = Tween<double>(
                        begin: 0.965,
                        end: 1.0,
                      ).animate(animation);
                      return FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: scale,
                          child: child,
                        ),
                      );
                    },
                    child: KeyedSubtree(
                      key: ValueKey(activeMode),
                      child: ThemeRegistry.build(activeMode, props),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(buildTransitionHarness());
    await tester.pumpAndSettle();

    // Verify initial theme (clean) rendered
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Hero && w.tag == nowPlayingArtHeroTag(PlayerThemeMode.clean),
      ),
      findsOneWidget,
    );

    // Switch theme to card mode
    modeNotifier.value = PlayerThemeMode.card;
    await tester.pump();

    // Step halfway through the transition: 190ms of 380ms
    await tester.pump(const Duration(milliseconds: 190));

    // Mid-transition: both outgoing and incoming theme trees coexist in AnimatedSwitcher
    // without hero tag collisions (because tags are per-theme unique)
    final cleanHero = find.byWidgetPredicate(
      (w) => w is Hero && w.tag == nowPlayingArtHeroTag(PlayerThemeMode.clean),
    );
    final cardHero = find.byWidgetPredicate(
      (w) => w is Hero && w.tag == nowPlayingArtHeroTag(PlayerThemeMode.card),
    );

    expect(cleanHero, findsOneWidget);
    expect(cardHero, findsOneWidget);

    // If golden image exists, assert pixel match for mid-transition frame
    const goldenName = 'theme_switch_mid_transition.png';
    if (goldenExists(goldenName)) {
      await expectLater(
        find.byKey(const ValueKey('theme_transition_boundary')),
        matchesGoldenFile('goldens/$goldenName'),
      );
    }

    // Complete transition
    await tester.pumpAndSettle();

    // Outgoing theme removed; only card theme remains
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Hero && w.tag == nowPlayingArtHeroTag(PlayerThemeMode.clean),
      ),
      findsNothing,
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is Hero && w.tag == nowPlayingArtHeroTag(PlayerThemeMode.card),
      ),
      findsOneWidget,
    );
  });
}
