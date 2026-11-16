// test/features/player/seek_bar_and_visualizer_all_themes_test.dart
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/widgets/pulsr_slider.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/themes/player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/theme_registry.dart';
import 'package:pulsr/features/player/presentation/widgets/audio_visualizer.dart';
import 'package:pulsr/features/player/presentation/widgets/player_seek_bar.dart';
import 'package:pulsr/features/player/presentation/widgets/waveform_seek_bar.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

import '../../helpers/test_song_factory.dart';

import 'package:pulsr/l10n/app_localizations_delegates.dart';
class MockPlayerCubit extends Mock implements PlayerCubit {}

class MockSettingsCubit extends Mock implements SettingsCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockPlayerCubit mockPlayerCubit;
  late MockSettingsCubit mockSettingsCubit;

  final testSong = createTestSong(
    id: 42,
    title: 'Visualizer Symphony',
    artist: 'Pulsr Acoustic',
    album: 'Audiophile Sessions',
    durationMs: 240000,
    path: '/music/symphony.flac',
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
    when(() => mockPlayerCubit.sponsorBlockSegments).thenReturn(const []);

    when(() => mockSettingsCubit.state).thenReturn(const SettingsState());
    when(() => mockSettingsCubit.stream)
        .thenAnswer((_) => const Stream.empty());

    // Provide instant mock waveform data so WaveformSeekBar builds synchronously
    PlayerSeekBar.waveformLoaderOverride = (songId, path) async =>
        List<double>.generate(100, (i) => (i % 10) / 10.0);
  });

  tearDown(() {
    PlayerSeekBar.waveformLoaderOverride = null;
  });

  Widget buildHarness({
    required Widget child,
    required SettingsState settings,
    Size size = const Size(390, 844),
  }) {
    when(() => mockSettingsCubit.state).thenReturn(settings);

    return MaterialApp(
      localizationsDelegates: appLocalizationsDelegates,
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
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  const allThemes = PlayerThemeMode.values;

  group('Seek Bar: All styles render cleanly across all 11 themes', () {
    const sliderStyles = [
      PlayerSliderStyle.normal,
      PlayerSliderStyle.wavy,
      PlayerSliderStyle.capsule,
      PlayerSliderStyle.minimal,
    ];

    for (final mode in allThemes) {
      for (final style in sliderStyles) {
        testWidgets('Theme $mode renders slider style $style', (tester) async {
          final props = PlayerThemeProps(
            state: mockPlayerCubit.state,
            cubit: mockPlayerCubit,
            activeColor: const Color(0xFF6750A4),
            bgColor: const Color(0xFF1C1B1F),
          );

          await tester.pumpWidget(buildHarness(
            settings: SettingsState(
              playerSliderStyle: style,
              waveformSeekBarEnabled: false,
            ),
            child: ThemeRegistry.build(mode, props),
          ));
          await tester.pump();

          expect(tester.takeException(), isNull);
          // PulsrSlider must be present for standard slider styles
          expect(find.byType(PulsrSlider), findsOneWidget);
        });
      }

      testWidgets('Theme $mode renders Waveform Seek Bar when enabled',
          (tester) async {
        final props = PlayerThemeProps(
          state: mockPlayerCubit.state,
          cubit: mockPlayerCubit,
          activeColor: const Color(0xFF6750A4),
          bgColor: const Color(0xFF1C1B1F),
        );

        await tester.pumpWidget(buildHarness(
          settings: const SettingsState(
            waveformSeekBarEnabled: true,
            playerSliderStyle: PlayerSliderStyle.normal,
          ),
          child: ThemeRegistry.build(mode, props),
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(tester.takeException(), isNull);
        expect(find.byType(WaveformSeekBar), findsOneWidget);
      });
    }
  });

  group('Audio Visualizer: All styles render cleanly across all 11 themes', () {
    const activeVisualizerStyles = [
      VisualizerStyle.bar,
      VisualizerStyle.wave,
      VisualizerStyle.circular,
      VisualizerStyle.particles,
      VisualizerStyle.terrain3D,
      VisualizerStyle.albumArtReactive,
      VisualizerStyle.custom,
      VisualizerStyle.milkdrop,
    ];

    for (final mode in allThemes) {
      for (final style in activeVisualizerStyles) {
        testWidgets('Theme $mode renders visualizer style $style',
            (tester) async {
          final props = PlayerThemeProps(
            state: mockPlayerCubit.state,
            cubit: mockPlayerCubit,
            activeColor: const Color(0xFF6750A4),
            bgColor: const Color(0xFF1C1B1F),
          );

          await tester.pumpWidget(buildHarness(
            settings: SettingsState(
              visualizerStyle: style,
              waveformSeekBarEnabled: false,
            ),
            child: ThemeRegistry.build(mode, props),
          ));
          await tester.pump();

          expect(tester.takeException(), isNull);
          // AudioVisualizer must be mounted and present in the widget tree
          expect(find.byType(AudioVisualizer), findsWidgets);
        });
      }

      testWidgets('Theme $mode respects VisualizerStyle.off', (tester) async {
        final props = PlayerThemeProps(
          state: mockPlayerCubit.state,
          cubit: mockPlayerCubit,
          activeColor: const Color(0xFF6750A4),
          bgColor: const Color(0xFF1C1B1F),
        );

        await tester.pumpWidget(buildHarness(
          settings: const SettingsState(
            visualizerStyle: VisualizerStyle.off,
            waveformSeekBarEnabled: false,
          ),
          child: ThemeRegistry.build(mode, props),
        ));
        await tester.pump();

        expect(tester.takeException(), isNull);
      });
    }
  });
}
