// test/golden/mini_player_golden_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/theme/aura_theme.dart';
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

Widget _harness({required DockStackMode mode}) {
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
          data: const MediaQueryData(
            size: Size(390, 844),
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
  for (final mode in DockStackMode.values) {
    testWidgets('MiniPlayer dock golden: ${mode.name}', (tester) async {
      await tester.pumpWidget(_harness(mode: mode));
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(StackedBottomDock),
        matchesGoldenFile('goldens/mini_player_${mode.name}.png'),
      );
    });
  }
}
