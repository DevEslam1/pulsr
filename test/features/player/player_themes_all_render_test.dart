// test/features/player/player_themes_all_render_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/themes/player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/player_theme_scaffold.dart';
import 'package:pulsr/features/player/presentation/themes/theme_registry.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import '../../helpers/test_song_factory.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}

class MockSettingsCubit extends Mock implements SettingsCubit {}

void main() {
  late MockPlayerCubit mockPlayerCubit;
  late MockSettingsCubit mockSettingsCubit;

  final testSong = createTestSong(
    id: 1,
    title: 'Solar Resonance',
    artist: 'Pulsr Ensemble',
    album: 'Audiophile Sessions',
    durationMs: 240000,
    path: '/music/solar.flac',
    bitrateKbps: 960,
  );

  setUp(() {
    mockPlayerCubit = MockPlayerCubit();
    mockSettingsCubit = MockSettingsCubit();

    when(() => mockPlayerCubit.state).thenReturn(PlayerState(
      playback: PlaybackSlice(
        currentSong: testSong,
        isPlaying: true,
        duration: const Duration(minutes: 4),
        position: const Duration(minutes: 1),
      ),
    ));
    when(() => mockPlayerCubit.stream).thenAnswer((_) => const Stream.empty());

    when(() => mockSettingsCubit.state).thenReturn(const SettingsState());
    when(() => mockSettingsCubit.stream).thenAnswer((_) => const Stream.empty());
  });

  Widget buildThemeHarness({
    required Size size,
    required Widget child,
    bool isInSplitView = false,
  }) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider<PlayerCubit>.value(value: mockPlayerCubit),
              BlocProvider<SettingsCubit>.value(value: mockSettingsCubit),
            ],
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: PlayerSplitViewScope(
                isInSplitView: isInSplitView,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }

  const scaffoldThemes = [
    PlayerThemeMode.classic,
    PlayerThemeMode.card,
    PlayerThemeMode.circle,
    PlayerThemeMode.minimal,
    PlayerThemeMode.vinyl,
    PlayerThemeMode.cd,
    PlayerThemeMode.cassette,
    PlayerThemeMode.waveform,
    PlayerThemeMode.lyricsFocus,
    PlayerThemeMode.milkdrop,
  ];

  group('All 10 PlayerThemeScaffold Themes Multi-Form-Factor Rendering Tests', () {
    for (final themeMode in scaffoldThemes) {
      testWidgets('$themeMode renders without exception in Portrait (390x844)', (tester) async {
        final props = PlayerThemeProps(
          state: mockPlayerCubit.state,
          cubit: mockPlayerCubit,
          activeColor: const Color(0xFF6750A4),
          bgColor: const Color(0xFF1C1B1F),
        );

        await tester.pumpWidget(
          buildThemeHarness(
            size: const Size(390, 844),
            child: ThemeRegistry.build(themeMode, props),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.byType(PlayerThemeScaffold), findsOneWidget);
      });

      testWidgets('$themeMode renders without exception in Landscape (844x390)', (tester) async {
        final props = PlayerThemeProps(
          state: mockPlayerCubit.state,
          cubit: mockPlayerCubit,
          activeColor: const Color(0xFF6750A4),
          bgColor: const Color(0xFF1C1B1F),
        );

        await tester.pumpWidget(
          buildThemeHarness(
            size: const Size(844, 390),
            child: ThemeRegistry.build(themeMode, props),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.byType(PlayerThemeScaffold), findsOneWidget);
      });

      testWidgets('$themeMode renders without exception in Short Screen (360x540)', (tester) async {
        final props = PlayerThemeProps(
          state: mockPlayerCubit.state,
          cubit: mockPlayerCubit,
          activeColor: const Color(0xFF6750A4),
          bgColor: const Color(0xFF1C1B1F),
        );

        await tester.pumpWidget(
          buildThemeHarness(
            size: const Size(360, 540),
            child: ThemeRegistry.build(themeMode, props),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.byType(PlayerThemeScaffold), findsOneWidget);
      });

      testWidgets('$themeMode renders without exception in Split-View', (tester) async {
        final props = PlayerThemeProps(
          state: mockPlayerCubit.state,
          cubit: mockPlayerCubit,
          activeColor: const Color(0xFF6750A4),
          bgColor: const Color(0xFF1C1B1F),
        );

        await tester.pumpWidget(
          buildThemeHarness(
            size: const Size(400, 600),
            isInSplitView: true,
            child: ThemeRegistry.build(themeMode, props),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.byType(PlayerThemeScaffold), findsOneWidget);
      });
    }
  });
}
