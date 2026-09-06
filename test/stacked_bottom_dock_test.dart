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
import 'package:pulsr/features/shell/presentation/bottom_nav_bar.dart';
import 'package:pulsr/features/shell/presentation/widgets/stacked_bottom_dock.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}
class MockSettingsCubit extends Mock implements SettingsCubit {}

void main() {
  late MockPlayerCubit playerCubit;
  late MockSettingsCubit settingsCubit;

  final testSong = SongsTableData(
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
  );

  setUp(() {
    playerCubit = MockPlayerCubit();
    settingsCubit = MockSettingsCubit();

    when(() => settingsCubit.state).thenReturn(const SettingsState());
    when(() => settingsCubit.stream)
        .thenAnswer((_) => const Stream<SettingsState>.empty());
  });

  Widget buildTestWidget({
    required DockStackMode mode,
    required ValueChanged<DockStackMode> onModeChanged,
    required bool hasSong,
  }) {
    when(() => playerCubit.state).thenReturn(
      PlayerState(
        currentSong: hasSong ? testSong : null,
        isPlaying: true,
        duration: const Duration(minutes: 3),
      ),
    );
    when(() => playerCubit.stream).thenAnswer(
      (_) => Stream.value(
        PlayerState(
          currentSong: hasSong ? testSong : null,
          isPlaying: true,
          duration: const Duration(minutes: 3),
        ),
      ),
    );

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
          body: StatefulBuilder(
            builder: (context, setState) {
              return Stack(
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: StackedBottomDock(
                      currentIndex: 0,
                      onTapNav: (_) {},
                      onOpenNowPlaying: () {},
                      mode: mode,
                      onModeChanged: onModeChanged,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  testWidgets('StackedBottomDock renders only PulsrBottomNavBar when no song is playing',
      (tester) async {
    await tester.pumpWidget(
      buildTestWidget(
        mode: DockStackMode.defaultLayout,
        onModeChanged: (_) {},
        hasSong: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PulsrBottomNavBar), findsOneWidget);
    expect(find.text('Test Track'), findsNothing);
  });

  testWidgets('StackedBottomDock gestures: swipe down stacks, swipe down again swaps, swipe up restores',
      (tester) async {
    DockStackMode currentMode = DockStackMode.defaultLayout;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          return buildTestWidget(
            mode: currentMode,
            onModeChanged: (newMode) {
              setState(() => currentMode = newMode);
            },
            hasSong: true,
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    // In default layout, song title is displayed and bottom nav bar is displayed
    expect(find.text('Test Track'), findsOneWidget);
    expect(find.byType(PulsrBottomNavBar), findsOneWidget);
    expect(currentMode, equals(DockStackMode.defaultLayout));

    // 1. Swipe down -> should transition to miniPlayerOnTop
    await tester.drag(find.text('Test Track'), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(currentMode, equals(DockStackMode.miniPlayerOnTop));

    // 2. Swipe down again -> should transition to navBarOnTop (replaces stack order)
    await tester.drag(find.byType(PulsrBottomNavBar), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(currentMode, equals(DockStackMode.navBarOnTop));

    // 3. Swipe down again -> should swap back to miniPlayerOnTop
    await tester.drag(find.byType(PulsrBottomNavBar), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(currentMode, equals(DockStackMode.miniPlayerOnTop));

    // 4. Swipe up -> should restore defaultLayout
    await tester.drag(find.text('Test Track'), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(currentMode, equals(DockStackMode.defaultLayout));
  });
}
