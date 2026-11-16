// test/features/player/mini_player_extended_test.dart
import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/mini_player.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';

import 'widgets/player_sheet_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(Duration.zero);
  });

  PlayerState playingState() => const PlayerState(
        playback: PlaybackSlice(
          currentSong: testSong,
          isPlaying: true,
          duration: Duration(minutes: 3),
          position: Duration(seconds: 30),
        ),
        queueSlice: QueueSlice(queue: [testSong, testSong], currentIndex: 0),
      );

  MockPlayerCubit stubTransport() {
    final cubit = stubPlayerCubit(state: playingState());
    when(() => cubit.togglePlayPause()).thenAnswer((_) async {});
    when(() => cubit.next()).thenAnswer((_) async {});
    when(() => cubit.previous()).thenAnswer((_) async {});
    when(() => cubit.adjustVolume(any())).thenAnswer((_) async {});
    when(() => cubit.seek(any())).thenAnswer((_) async {});
    when(() => cubit.skipToQueueItem(any())).thenAnswer((_) async {});
    return cubit;
  }

  testWidgets('play/pause, next and tap/vertical swipes drive the cubit',
      (tester) async {
    final cubit = stubTransport();
    var tapped = 0;
    var swipedDown = 0;
    var swipedUp = 0;

    await tester.pumpWidget(sheetHost(
      playerCubit: cubit,
      settingsCubit: stubSettingsCubit(),
      child: MiniPlayer(
        onTap: () => tapped++,
        onSwipeDown: () => swipedDown++,
        onSwipeUp: () => swipedUp++,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text(testSong.title), findsWidgets);

    // Tap the card.
    await tester.tap(find.text(testSong.title).first, warnIfMissed: false);
    await tester.pump();
    expect(tapped, 1);

    // Toggle play/pause via the control.
    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pump();
    verify(() => cubit.togglePlayPause()).called(1);

    // Skip next.
    await tester.tap(find.byIcon(Icons.skip_next_rounded));
    await tester.pump();
    verify(() => cubit.next()).called(1);

    // Vertical swipe up expands (falls back to onTap when onSwipeUp is null).
    await tester.drag(find.byType(MiniPlayer), const Offset(0, -60),
        warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 700));
    expect(swipedUp, 1);

    // Vertical swipe down dismisses.
    await tester.drag(find.byType(MiniPlayer), const Offset(0, 60),
        warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 700));
    expect(swipedDown, 1);
  });

  testWidgets('horizontal swipe applies the configured volume action',
      (tester) async {
    final cubit = stubTransport();

    await tester.pumpWidget(sheetHost(
      playerCubit: cubit,
      settingsCubit: stubSettingsCubit(
        state: const SettingsState(
          miniPlayerSwipeLeft: MiniPlayerSwipeAction.volume,
          miniPlayerSwipeRight: MiniPlayerSwipeAction.none,
        ),
      ),
      child: MiniPlayer(onTap: () {}),
    ));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(MiniPlayer), const Offset(-80, 0),
        warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 50));

    verify(() => cubit.adjustVolume(-0.05)).called(1);
  });

  testWidgets('progress bar records an optimistic seek on tap', (tester) async {
    final cubit = stubTransport();

    await tester.pumpWidget(sheetHost(
      playerCubit: cubit,
      settingsCubit: stubSettingsCubit(),
      child: MiniPlayer(onTap: () {}),
    ));
    await tester.pumpAndSettle();

    final progress = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_MiniPlayerProgressBar',
    );
    expect(progress, findsOneWidget);

    await tester.tapAt(tester.getCenter(progress));
    await tester.pump(const Duration(milliseconds: 20));

    verify(() => cubit.seek(any())).called(greaterThanOrEqualTo(1));
  });

  testWidgets('MiniPlayerHorizontal renders and controls playback',
      (tester) async {
    final cubit = stubTransport();

    await tester.pumpWidget(sheetHost(
      playerCubit: cubit,
      settingsCubit: stubSettingsCubit(),
      child: MiniPlayerHorizontal(onTap: () {}),
    ));
    await tester.pumpAndSettle();

    expect(find.text(testSong.title), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pump();
    verify(() => cubit.togglePlayPause()).called(1);

    await tester.tap(find.byIcon(Icons.skip_next_rounded));
    await tester.pump();
    verify(() => cubit.next()).called(1);
  });

  testWidgets(
      'P3-28: optimistic seek clears via BlocListener cleanly without mutating during build',
      (tester) async {
    final controller = StreamController<PlayerState>.broadcast();
    addTearDown(controller.close);
    var current = playingState();
    final cubit = stubTransport();
    when(() => cubit.state).thenAnswer((_) => current);
    when(() => cubit.stream).thenAnswer((_) => controller.stream);

    await tester.pumpWidget(sheetHost(
      playerCubit: cubit,
      settingsCubit: stubSettingsCubit(),
      child: MiniPlayer(onTap: () {}),
    ));
    await tester.pumpAndSettle();

    final progressFinder = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_MiniPlayerProgressBar',
    );
    expect(progressFinder, findsOneWidget);

    final handle = tester.ensureSemantics();
    try {
      // Tap center (~90s out of 180s) to record an optimistic seek target.
      await tester.tapAt(tester.getCenter(progressFinder));
      await tester.pump();
      verify(() => cubit.seek(any())).called(1);

      // A slightly stale tick inside 350ms keeps displaying the optimistic ~1:30.
      current = current.copyWith(
        playback:
            current.playback.copyWith(position: const Duration(seconds: 31)),
      );
      controller.add(current);
      await tester.pump();
      await tester.pump();
      final seekSemantics = find.ancestor(
        of: progressFinder,
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.slider == true,
        ),
      );
      final duringHold = find.descendant(
        of: progressFinder,
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.slider == true,
        ),
      );
      final semanticsFinder =
          seekSemantics.evaluate().isNotEmpty ? seekSemantics : duringHold;
      expect(semanticsFinder, findsOneWidget);
      expect(
        tester.getSemantics(semanticsFinder.first).value,
        startsWith('1:30 / 3:00'),
      );

      // Engine catches up to ~90s -> BlocListener clears optimistic hold cleanly.
      current = current.copyWith(
        playback:
            current.playback.copyWith(position: const Duration(seconds: 90)),
      );
      controller.add(current);
      await tester.pump();
      await tester.pump();

      // Next tick advances normally rather than snapping back to an uncleared hold.
      current = current.copyWith(
        playback:
            current.playback.copyWith(position: const Duration(seconds: 95)),
      );
      controller.add(current);
      await tester.pump();
      await tester.pump();
      expect(
        tester.getSemantics(semanticsFinder.first).value,
        startsWith('1:35 / 3:00'),
      );
      expect(tester.takeException(), isNull);
    } finally {
      handle.dispose();
    }
  });
}
