import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/widgets/pulsr_dock_tracker.dart';
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

  const testSong = SongsTableData(
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
    source: SongSource.local,
    isDownloaded: true,
  );

  setUp(() {
    playerCubit = MockPlayerCubit();
    settingsCubit = MockSettingsCubit();

    when(() => settingsCubit.state).thenReturn(const SettingsState());
    when(() => settingsCubit.stream)
        .thenAnswer((_) => const Stream<SettingsState>.empty());
    when(() => playerCubit.state).thenReturn(
      const PlayerState(
        playback: PlaybackSlice(
          currentSong: testSong,
          isPlaying: true,
          duration: Duration(minutes: 3),
        ),
      ),
    );
    when(() => playerCubit.stream).thenAnswer(
      (_) => Stream.value(
        const PlayerState(
          playback: PlaybackSlice(
            currentSong: testSong,
            isPlaying: true,
            duration: Duration(minutes: 3),
          ),
        ),
      ),
    );
  });

  group('[M-13] StackedBottomDock computeDockHeight keyboard visibility', () {
    test('computeDockHeight returns 0.0 when keyboard is visible or inset > 0',
        () {
      const navBarTotalHeight = 74.0;

      // Normal state with song
      final normalHeight = StackedBottomDock.computeDockHeight(
        hasSong: true,
        mode: DockStackMode.defaultLayout,
        navBarTotalHeight: navBarTotalHeight,
      );
      expect(normalHeight, greaterThan(0.0));

      // With isKeyboardVisible = true
      final keyboardVisibleHeight = StackedBottomDock.computeDockHeight(
        hasSong: true,
        mode: DockStackMode.defaultLayout,
        navBarTotalHeight: navBarTotalHeight,
        isKeyboardVisible: true,
      );
      expect(keyboardVisibleHeight, equals(0.0));

      // With keyboardInset > 0
      final keyboardInsetHeight = StackedBottomDock.computeDockHeight(
        hasSong: true,
        mode: DockStackMode.defaultLayout,
        navBarTotalHeight: navBarTotalHeight,
        keyboardInset: 320.0,
      );
      expect(keyboardInsetHeight, equals(0.0));
    });

    testWidgets(
        'StackedBottomDock updates PulsrDockTracker height to 0.0 when keyboard is open',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      Widget buildWithInsets(double bottomInset) {
        return MultiBlocProvider(
          providers: [
            BlocProvider<PlayerCubit>.value(value: playerCubit),
            BlocProvider<SettingsCubit>.value(value: settingsCubit),
          ],
          child: MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                  viewInsets: EdgeInsets.only(bottom: bottomInset)),
              child: Scaffold(
                resizeToAvoidBottomInset: false,
                body: StackedBottomDock(
                  currentIndex: 0,
                  onTapNav: (_) {},
                  onOpenNowPlaying: () {},
                  mode: DockStackMode.defaultLayout,
                  onModeChanged: (_) {},
                ),
              ),
            ),
          ),
        );
      }

      await tester.pumpWidget(buildWithInsets(0.0));
      await tester.pumpAndSettle();

      // Initially keyboard is closed, dock reports positive height
      expect(PulsrDockTracker.dockHeight.value, greaterThan(0.0));

      // Simulate software keyboard opening with 300px bottom inset
      await tester.pumpWidget(buildWithInsets(300.0));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      // Dock tracker is updated to 0.0 when keyboard is open
      expect(PulsrDockTracker.dockHeight.value, equals(0.0));
    });
  });
}
