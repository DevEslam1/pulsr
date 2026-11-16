// test/golden/mini_player_golden_test.dart
//
// Golden images are generated locally (`flutter test test/golden
// --update-goldens`) and are gitignored, so a clean checkout has no master
// images. Skip rather than fail when the reference is absent.
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/responsive/pulsr_layout_metrics.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
import 'package:pulsr/core/widgets/pulsr_dock_tracker.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/features/shell/presentation/widgets/stacked_bottom_dock.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}

class MockSettingsCubit extends Mock implements SettingsCubit {}

const _song = SongsTableData(
  id: 1,
  title: 'Test Track',
  artist: 'Test Artist',
  album: 'Test Album',
  durationMs: 180000,
  path: '/path/to/song.mp3',
  dateAdded: 0,
  playCount: 0,
  lastPositionMs: 0,
  isFavorite: false,
  isMissing: false,
  source: 'local',
  isDownloaded: true,
);

Widget _harness({
  required DockStackMode mode,
  double textScale = 1.0,
}) {
  final playerCubit = MockPlayerCubit();
  final settingsCubit = MockSettingsCubit();

  when(() => settingsCubit.state).thenReturn(const SettingsState());
  when(() => settingsCubit.stream)
      .thenAnswer((_) => const Stream<SettingsState>.empty());

  const state = PlayerState(
    playback: PlaybackSlice(
      currentSong: _song,
      isPlaying: true,
      duration: Duration(minutes: 3),
    ),
  );
  when(() => playerCubit.state).thenReturn(state);
  when(() => playerCubit.stream)
      .thenAnswer((_) => const Stream<PlayerState>.empty());

  final theme = AuraTheme.customTheme(
    const Color(0xFF00E5FF),
    brightness: Brightness.dark,
  );

  return MultiBlocProvider(
    providers: [
      BlocProvider<PlayerCubit>.value(value: playerCubit),
      BlocProvider<SettingsCubit>.value(value: settingsCubit),
    ],
    child: MaterialApp(
      theme: theme,
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(
            size: const Size(390, 844),
            textScaler: TextScaler.linear(textScale),
            disableAnimations: true,
          ),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: RepaintBoundary(
                  child: StackedBottomDock(
                    currentIndex: 0,
                    onTapNav: (_) {},
                    onOpenNowPlaying: () {},
                    mode: mode,
                    onModeChanged: (_) {},
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  bool goldenExists(String name) =>
      File('test/golden/goldens/$name').existsSync();

  const textScales = [1.0, 1.5, 2.0];

  for (final mode in DockStackMode.values) {
    for (final scale in textScales) {
      testWidgets('MiniPlayer dock height sync: ${mode.name} @ ${scale}x',
          (tester) async {
        await tester.pumpWidget(_harness(mode: mode, textScale: scale));
        await tester.pumpAndSettle();

        final dockCtx = tester.element(find.byType(StackedBottomDock));
        final expectedDockHeight = StackedBottomDock.computeDockHeight(
          hasSong: true,
          mode: mode,
          navBarTotalHeight: PulsrLayoutMetrics.navBarTotalHeight(dockCtx),
          miniPlayerHeight: StackedBottomDock.scaledMiniPlayerHeight(dockCtx),
        );
        expect(
          tester.getSize(find.byType(StackedBottomDock)).height,
          closeTo(expectedDockHeight, 0.01),
        );
        expect(
          PulsrDockTracker.dockHeight.value,
          closeTo(expectedDockHeight, 0.01),
        );
      });

      final scaleTag = scale.toStringAsFixed(1).replaceAll('.', '_');
      final fileName = scale == 1.0
          ? 'mini_player_${mode.name}.png'
          : 'mini_player_${mode.name}_ts_$scaleTag.png';

      testWidgets('MiniPlayer dock golden: ${mode.name} @ ${scale}x',
          skip: !autoUpdateGoldenFiles && !goldenExists(fileName),
          (tester) async {
        await tester.pumpWidget(_harness(mode: mode, textScale: scale));
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(StackedBottomDock),
          matchesGoldenFile('goldens/$fileName'),
        );
      });
    }
  }
}
