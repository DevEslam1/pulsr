// LandscapeSidebar interaction coverage: nav item taps + selection guard,
// badge counts (incl. the 99+ clamp), the compact/icon-only peek lifecycle,
// the now-playing bottom tile (expanded + collapsed), the side-inspector
// shortcut and the collapse/expand triggers.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/widgets/cached_artwork.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/shell/presentation/widgets/landscape_sidebar.dart';
import 'package:pulsr/l10n/generated/app_localizations.dart';

class MockPlayerCubit extends Mock implements PlayerCubit {}

const SongsTableData _song = SongsTableData(
  id: 42,
  title: 'Sidebar Song',
  artist: 'Sidebar Artist',
  album: 'Sidebar Album',
  durationMs: 180000,
  path: '/music/sidebar.mp3',
  isFavorite: false,
  isMissing: false,
  playCount: 0,
  lastPositionMs: 0,
  source: 'local',
  isDownloaded: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockPlayerCubit player;

  setUp(() {
    player = MockPlayerCubit();
    when(() => player.state).thenReturn(const PlayerState());
    when(() => player.stream).thenAnswer((_) => const Stream.empty());
  });

  Widget build({
    required Size size,
    int currentIndex = 0,
    bool isExtended = false,
    SidebarRailMode? modeOverride,
    Map<int, int>? badgeCounts,
    VoidCallback? onOpenNowPlaying,
    VoidCallback? onToggleSideInspector,
    bool isSideInspectorOpen = false,
    bool showNowPlayingTile = false,
    PlayerState? playerState,
    ValueChanged<int>? onSelect,
    VoidCallback? onToggleExtended,
  }) {
    if (playerState != null) {
      when(() => player.state).thenReturn(playerState);
    }
    return BlocProvider<PlayerCubit>.value(
      value: player,
      child: MediaQuery(
        data: MediaQueryData(size: size),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: LandscapeSidebar(
              currentIndex: currentIndex,
              onDestinationSelected: onSelect ?? (_) {},
              isExtended: isExtended,
              onToggleExtended: onToggleExtended ?? () {},
              modeOverride: modeOverride,
              badgeCounts: badgeCounts,
              onOpenNowPlaying: onOpenNowPlaying,
              onToggleSideInspector: onToggleSideInspector,
              isSideInspectorOpen: isSideInspectorOpen,
              showNowPlayingTile: showNowPlayingTile,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('expanded sidebar taps a non-selected destination only',
      (tester) async {
    final selected = <int>[];
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(build(
      size: const Size(1200, 900),
      isExtended: true,
      currentIndex: 0,
      onSelect: selected.add,
    ));
    await tester.pumpAndSettle();

    // Current destination (Home) is a no-op.
    await tester.tap(find.text('Home'));
    await tester.pump();
    expect(selected, isEmpty);

    // Library (index 1) fires the callback.
    await tester.tap(find.text('Library'));
    await tester.pump();
    expect(selected, [1]);
  });

  testWidgets('expanded sidebar clamps large badge counts to 99+',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(build(
      size: const Size(1200, 900),
      isExtended: true,
      badgeCounts: const {1: 150, 2: 3},
    ));
    await tester.pumpAndSettle();

    expect(find.text('99+'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('compact sidebar peeks then auto-collapses after the timer',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // 1000x700 landscape resolves to compact without an override.
    await tester.pumpWidget(build(size: const Size(1000, 700)));
    await tester.pumpAndSettle();

    final state =
        tester.state<LandscapeSidebarState>(find.byType(LandscapeSidebar));
    expect(state.isPeeking, isFalse);

    state.triggerPeek();
    await tester.pump();
    expect(state.isPeeking, isTrue);
    // Peeking promotes compact to expanded chrome.
    expect(find.text('PULSR'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(state.isPeeking, isFalse);
  });

  testWidgets('changing modeOverride while peeking clears the peek',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Widget host(SidebarRailMode mode) => build(
          size: const Size(1000, 700),
          modeOverride: mode,
        );

    await tester.pumpWidget(host(SidebarRailMode.compact));
    await tester.pumpAndSettle();
    final state =
        tester.state<LandscapeSidebarState>(find.byType(LandscapeSidebar));
    state.triggerPeek();
    await tester.pump();
    expect(state.isPeeking, isTrue);

    await tester.pumpWidget(host(SidebarRailMode.iconOnly));
    await tester.pump();
    expect(state.isPeeking, isFalse);
  });

  testWidgets('side-inspector shortcut reflects open state and toggles',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var toggles = 0;
    await tester.pumpWidget(build(
      size: const Size(1200, 900),
      isExtended: true,
      onToggleSideInspector: () => toggles++,
      isSideInspectorOpen: true,
    ));
    await tester.pumpAndSettle();

    expect(find.text('ON'), findsOneWidget);
    await tester.tap(find.text('Side Panel'));
    await tester.pump();
    expect(toggles, 1);
  });

  testWidgets('expanded now-playing tile shows the track and opens it',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var opened = 0;
    await tester.pumpWidget(build(
      size: const Size(1200, 900),
      isExtended: true,
      showNowPlayingTile: true,
      onOpenNowPlaying: () => opened++,
      playerState: const PlayerState(
        playback: PlaybackSlice(currentSong: _song, isPlaying: true),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Sidebar Song'), findsOneWidget);
    expect(find.text('Sidebar Artist'), findsOneWidget);
    // Equalizer glyph is only painted while playing.
    expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);

    await tester.tap(find.text('Sidebar Song'));
    await tester.pump();
    expect(opened, 1);
  });

  testWidgets('collapsed now-playing tile and expand trigger fire callbacks',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var opened = 0;
    var toggles = 0;
    await tester.pumpWidget(build(
      size: const Size(1000, 700),
      modeOverride: SidebarRailMode.iconOnly,
      showNowPlayingTile: true,
      onOpenNowPlaying: () => opened++,
      onToggleExtended: () => toggles++,
      playerState: const PlayerState(
        playback: PlaybackSlice(currentSong: _song, isPlaying: false),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(CachedArtwork).first);
    await tester.pump();
    expect(opened, 1);

    // Collapsed bottom expand trigger.
    await tester.tap(find.byIcon(Icons.keyboard_double_arrow_right_rounded));
    await tester.pump();
    expect(toggles, greaterThanOrEqualTo(1));
  });

  testWidgets('expanded brand header collapse button fires the toggle',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var toggles = 0;
    await tester.pumpWidget(build(
      size: const Size(1200, 900),
      isExtended: true,
      onToggleExtended: () => toggles++,
    ));
    await tester.pumpAndSettle();

    expect(find.text('PULSR'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.keyboard_double_arrow_left_rounded));
    await tester.pump();
    expect(toggles, 1);
  });
}
