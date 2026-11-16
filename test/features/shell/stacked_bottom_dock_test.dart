import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/responsive/layout_delegate.dart';
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

  final testSong = const SongsTableData(
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
    ShellLayoutMode? layoutMode,
  }) {
    when(() => playerCubit.state).thenReturn(
      PlayerState(
        playback: PlaybackSlice(
          currentSong: hasSong ? testSong : null,
          isPlaying: true,
          duration: const Duration(minutes: 3),
        ),
      ),
    );
    when(() => playerCubit.stream).thenAnswer(
      (_) => Stream.value(
        PlayerState(
          playback: PlaybackSlice(
            currentSong: hasSong ? testSong : null,
            isPlaying: true,
            duration: const Duration(minutes: 3),
          ),
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
                      layoutMode: layoutMode,
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

  testWidgets(
      'StackedBottomDock renders only PulsrBottomNavBar when no song is playing',
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

  testWidgets(
      'swipe down opens the dock style picker instead of silently restacking',
      (tester) async {
    DockStackMode currentMode = DockStackMode.defaultLayout;
    var changes = 0;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          return buildTestWidget(
            mode: currentMode,
            onModeChanged: (newMode) {
              changes++;
              setState(() => currentMode = newMode);
            },
            hasSong: true,
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(currentMode, equals(DockStackMode.defaultLayout));

    await tester.fling(find.text('Test Track'), const Offset(0, 300), 1000.0);
    await tester.pumpAndSettle();

    // The gesture is a request, not a mutation: the picker opens and the
    // layout stays exactly where the user left it.
    expect(changes, equals(0),
        reason:
            'a downward swipe must never change the dock layout on its own');
    expect(find.text('Dock style'), findsOneWidget);

    Navigator.of(tester.element(find.text('Dock style'))).pop();
    await tester.pumpAndSettle();
    expect(currentMode, equals(DockStackMode.defaultLayout));
  });

  testWidgets('swipe up un-stacks a stacked dock back to the resting layout',
      (tester) async {
    DockStackMode currentMode = DockStackMode.navBarOnTop;

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

    await tester.fling(
      find.byType(PulsrBottomNavBar),
      const Offset(0, -300),
      1000.0,
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(currentMode, equals(DockStackMode.defaultLayout));
  });

  testWidgets('Tapping peeking card behind brings it to the front',
      (tester) async {
    DockStackMode currentMode = DockStackMode.miniPlayerOnTop;

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

    // In miniPlayerOnTop, the nav bar is behind and peeking at top.
    // Tapping the peeking region of the nav bar brings it to the front (navBarOnTop).
    final navBarRect = tester.getRect(find.byType(PulsrBottomNavBar));
    await tester.tapAt(Offset(navBarRect.center.dx, navBarRect.top + 4));
    await tester.pumpAndSettle();
    expect(currentMode, equals(DockStackMode.navBarOnTop));
  });

  testWidgets(
      'bottomNavWide dock renders embedded nav bar without overflow with active song',
      (tester) async {
    tester.view.physicalSize = const Size(850, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      buildTestWidget(
        mode: DockStackMode.defaultLayout,
        onModeChanged: (_) {},
        hasSong: true,
        layoutMode: ShellLayoutMode.bottomNavWide,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final navBar = tester.widget<PulsrBottomNavBar>(
      find.byType(PulsrBottomNavBar),
    );
    expect(navBar.embedded, isTrue);
    expect(navBar.iconOnly, isTrue);
  });

  testWidgets(
      'bottomNavWide dock renders embedded nav bar without overflow when no song is playing',
      (tester) async {
    tester.view.physicalSize = const Size(850, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      buildTestWidget(
        mode: DockStackMode.defaultLayout,
        onModeChanged: (_) {},
        hasSong: false,
        layoutMode: ShellLayoutMode.bottomNavWide,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final navBar = tester.widget<PulsrBottomNavBar>(
      find.byType(PulsrBottomNavBar),
    );
    expect(navBar.embedded, isTrue);
    expect(navBar.iconOnly, isFalse);
  });
}
