// test/features/player/milkdrop_player_theme_test.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/domain/models/milkdrop_preset.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/themes/milkdrop_player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/player_theme.dart';
import 'package:pulsr/features/player/presentation/themes/theme_registry.dart';
import 'package:pulsr/features/player/presentation/widgets/audio_visualizer.dart';
import 'package:pulsr/features/player/presentation/widgets/visualizer/milkdrop_renderer.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';
import '../../helpers/test_song_factory.dart';

class _MockPlayerCubit extends Mock implements PlayerCubit {}

class _MockSettingsCubit extends Mock implements SettingsCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockPlayerCubit playerCubit;
  late _MockSettingsCubit settingsCubit;

  final testSong = createTestSong(id: 101, title: 'Cosmic Journey', artist: 'Pulsr Dreamer');

  setUp(() {
    AudioVisualizer.isTestingOverride = true;
    playerCubit = _MockPlayerCubit();
    settingsCubit = _MockSettingsCubit();

    when(() => playerCubit.state).thenReturn(
      PlayerState(
        playback: PlaybackSlice(
          currentSong: testSong,
          isPlaying: true,
          position: const Duration(seconds: 45),
          duration: const Duration(seconds: 240),
        ),
      ),
    );
    when(() => playerCubit.stream).thenAnswer((_) => const Stream.empty());

    when(() => settingsCubit.state).thenReturn(
      const SettingsState(
        playerThemeMode: PlayerThemeMode.milkdrop,
      ),
    );
    when(() => settingsCubit.stream).thenAnswer((_) => const Stream.empty());
  });

  tearDown(() {
    AudioVisualizer.isTestingOverride = null;
  });

  Widget createHost({
    Size size = const Size(390, 844),
    Widget? child,
  }) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<PlayerCubit>.value(value: playerCubit),
        BlocProvider<SettingsCubit>.value(value: settingsCubit),
      ],
      child: MaterialApp(
        theme: AuraTheme.darkTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(size: size),
          child: Scaffold(
            body: child ??
                ThemeRegistry.build(
                  PlayerThemeMode.milkdrop,
                  PlayerThemeProps(
                    state: playerCubit.state,
                    cubit: playerCubit,
                    activeColor: const Color(0xFF9C27B0),
                    bgColor: const Color(0xFF121212),
                  ),
                ),
          ),
        ),
      ),
    );
  }

  group('MilkdropPlayerTheme Tests', () {
    testWidgets('renders full-screen Milkdrop visualizer behind artwork',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(createHost());
      await tester.pump();

      expect(find.byType(MilkdropPlayerTheme), findsOneWidget);

      final visualizerFinder = find.byType(AudioVisualizer);
      expect(visualizerFinder, findsOneWidget);

      final visualizerWidget =
          tester.widget<AudioVisualizer>(visualizerFinder);
      expect(visualizerWidget.style, equals(VisualizerStyle.milkdrop));
      expect(visualizerWidget.color, equals(Colors.white));
      expect(visualizerWidget.transparentBackground, isTrue);

      expect(find.byKey(const ValueKey('artwork_view_milkdrop')), findsOneWidget);
      expect(find.text('MILKDROP'), findsOneWidget);
    });

    testWidgets('renders properly in landscape mode across screen',
        (tester) async {
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        createHost(size: const Size(844, 390)),
      );
      await tester.pump();

      expect(find.byType(MilkdropPlayerTheme), findsOneWidget);
      expect(find.byType(AudioVisualizer), findsOneWidget);
    });

    testWidgets('MilkdropCanvasPainter paints transparent background properly',
        (tester) async {
      final painter = MilkdropCanvasPainter(
        data: const [0.2, 0.4, 0.8, 0.6, 0.3, 0.5],
        color: Colors.white,
        preset: MilkdropPresetLibrary.defaultPreset,
        transparentBackground: true,
      );

      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      const size = Size(400, 800);

      expect(() => painter.paint(canvas, size), returnsNormally);
      expect(painter.shouldRepaint(painter), isTrue);
    });
  });
}
