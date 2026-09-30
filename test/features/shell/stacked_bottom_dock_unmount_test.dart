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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockPlayerCubit playerCubit;
  late MockSettingsCubit settingsCubit;

  const testSong1 = SongsTableData(
    id: 1,
    title: 'Track 1',
    artist: 'Artist 1',
    album: 'Album 1',
    durationMs: 180000,
    path: '/path/1.mp3',
    source: SongSource.local,
    isFavorite: false,
    isMissing: false,
    isDownloaded: true,
    playCount: 0,
    lastPositionMs: 0,
  );

  const testSong2 = SongsTableData(
    id: 2,
    title: 'Track 2',
    artist: 'Artist 2',
    album: 'Album 2',
    durationMs: 200000,
    path: '/path/2.mp3',
    source: SongSource.local,
    isFavorite: false,
    isMissing: false,
    isDownloaded: true,
    playCount: 0,
    lastPositionMs: 0,
  );

  setUp(() {
    playerCubit = MockPlayerCubit();
    settingsCubit = MockSettingsCubit();

    when(() => settingsCubit.state).thenReturn(const SettingsState());
    when(() => settingsCubit.stream).thenAnswer((_) => const Stream.empty());
  });

  testWidgets('H-14: _dockSyncDebounceTimer callback safely guards unmounted widget', (tester) async {
    when(() => playerCubit.state).thenReturn(
      const PlayerState(
        playback: PlaybackSlice(
          currentSong: testSong1,
          isPlaying: true,
        ),
      ),
    );
    when(() => playerCubit.stream).thenAnswer((_) => const Stream.empty());

    final theme = AuraTheme.customTheme(
      const Color(0xFF00E5FF),
      brightness: Brightness.dark,
    );

    bool showDock = true;

    StateSetter? setInnerState;

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<PlayerCubit>.value(value: playerCubit),
          BlocProvider<SettingsCubit>.value(value: settingsCubit),
        ],
        child: MaterialApp(
          theme: theme,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                setInnerState = setState;
                if (!showDock) return const SizedBox.shrink();
                return StackedBottomDock(
                  currentIndex: 0,
                  onTapNav: (_) {},
                  onOpenNowPlaying: () {},
                  mode: DockStackMode.defaultLayout,
                  onModeChanged: (_) {},
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Change song in PlayerCubit to trigger debounce timer
    when(() => playerCubit.state).thenReturn(
      const PlayerState(
        playback: PlaybackSlice(
          currentSong: testSong2,
          isPlaying: true,
        ),
      ),
    );

    // Rebuild to invoke didChangeDependencies
    await tester.pump();

    // 2. Immediately unmount the dock before the 50ms debounce timer expires
    setInnerState!(() => showDock = false);
    await tester.pump();

    // 3. Advance time by 100ms so the debounce timer fires while unmounted
    await tester.pump(const Duration(milliseconds: 100));

    // The test completes cleanly without unhandled exception or post-disposal assertion
    expect(find.byType(StackedBottomDock), findsNothing);
  });
}
