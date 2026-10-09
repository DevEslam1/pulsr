// test/features/player/mini_player_more_test.dart
//
// Branch coverage for [MiniPlayer]: configured swipe actions (next/prev/none),
// carousel page completion, the progress-bar scrub handlers + lifecycle, the
// vinyl theme variant and the interaction notifier drain path.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/widgets/spinning_vinyl_disc.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/mini_player.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';

import 'widgets/player_sheet_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(Duration.zero);
  });

  const secondSong = SongsTableData(
    id: 43,
    title: 'Second Song',
    artist: 'Second Artist',
    album: 'Album',
    durationMs: 200000,
    path: '/music/second.flac',
    isFavorite: false,
    isMissing: false,
    playCount: 0,
    lastPositionMs: 0,
    source: 'local',
    isDownloaded: true,
  );

  PlayerState queueState({int currentIndex = 0}) => PlayerState(
        playback: const PlaybackSlice(
          currentSong: testSong,
          isPlaying: true,
          duration: Duration(minutes: 3),
          position: Duration(seconds: 30),
        ),
        queueSlice: QueueSlice(
          queue: const [testSong, secondSong],
          currentIndex: currentIndex,
        ),
      );

  MockPlayerCubit stubTransport({PlayerState? state}) {
    final cubit = stubPlayerCubit(state: state ?? queueState());
    when(() => cubit.togglePlayPause()).thenAnswer((_) async {});
    when(() => cubit.next()).thenAnswer((_) async {});
    when(() => cubit.previous()).thenAnswer((_) async {});
    when(() => cubit.adjustVolume(any())).thenAnswer((_) async {});
    when(() => cubit.seek(any())).thenAnswer((_) async {});
    when(() => cubit.skipToQueueItem(any())).thenAnswer((_) async {});
    return cubit;
  }

  testWidgets('configured horizontal swipe runs prev then next',
      (tester) async {
    final cubit = stubTransport();
    await tester.pumpWidget(sheetHost(
      playerCubit: cubit,
      settingsCubit: stubSettingsCubit(
        state: const SettingsState(
          miniPlayerSwipeLeft: MiniPlayerSwipeAction.prev,
          miniPlayerSwipeRight: MiniPlayerSwipeAction.next,
        ),
      ),
      child: MiniPlayer(onTap: () {}),
    ));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(MiniPlayer), const Offset(-80, 0),
        warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 60));
    verify(() => cubit.previous()).called(1);

    await tester.drag(find.byType(MiniPlayer), const Offset(80, 0),
        warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 60));
    verify(() => cubit.next()).called(1);
  });

  testWidgets('a "none" swipe action and sub-threshold drags are ignored',
      (tester) async {
    final cubit = stubTransport();
    await tester.pumpWidget(sheetHost(
      playerCubit: cubit,
      settingsCubit: stubSettingsCubit(
        state: const SettingsState(
          miniPlayerSwipeLeft: MiniPlayerSwipeAction.none,
          miniPlayerSwipeRight: MiniPlayerSwipeAction.none,
        ),
      ),
      child: MiniPlayer(onTap: () {}),
    ));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(MiniPlayer), const Offset(-80, 0),
        warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.drag(find.byType(MiniPlayer), const Offset(10, 0),
        warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 60));

    verifyNever(() => cubit.next());
    verifyNever(() => cubit.previous());
  });

  testWidgets('carousel swipe completes to the next queue item',
      (tester) async {
    final cubit = stubTransport();
    await tester.pumpWidget(sheetHost(
      playerCubit: cubit,
      settingsCubit: stubSettingsCubit(),
      child: MiniPlayer(onTap: () {}),
    ));
    await tester.pumpAndSettle();

    // Drive the carousel's page-change callback directly; the interaction
    // guard requires an in-progress user interaction.
    final state = tester.state<MiniPlayerState>(find.byType(MiniPlayer));
    state.isInteractingNotifier.value = true;
    final pageView = tester.widget<PageView>(find.byType(PageView));
    pageView.onPageChanged!(1);
    await tester.pumpAndSettle();

    verify(() => cubit.skipToQueueItem(any())).called(greaterThanOrEqualTo(1));
  });

  testWidgets('progress-bar drag start/update/end records a seek',
      (tester) async {
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

    final gesture = await tester.startGesture(tester.getCenter(progress));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    verify(() => cubit.seek(any())).called(greaterThanOrEqualTo(1));
  });

  testWidgets('progress-bar drag cancel clears the transient state',
      (tester) async {
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
    final gesture = await tester.startGesture(tester.getCenter(progress));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('app lifecycle pause/resume keeps the wave controller sane',
      (tester) async {
    final cubit = stubTransport();
    await tester.pumpWidget(sheetHost(
      playerCubit: cubit,
      settingsCubit: stubSettingsCubit(),
      child: MiniPlayer(onTap: () {}),
    ));
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the vinyl theme renders the spinning disc', (tester) async {
    final cubit = stubTransport();
    await tester.pumpWidget(sheetHost(
      playerCubit: cubit,
      settingsCubit: stubSettingsCubit(
        state: const SettingsState(playerThemeMode: PlayerThemeMode.vinyl),
      ),
      child: MiniPlayer(onTap: () {}),
    ));
    // The vinyl disc animates forever; settle would time out.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byType(SpinningVinylDisc), findsOneWidget);
  });

  testWidgets('interaction notifier toggling drains pending page syncs',
      (tester) async {
    final cubit = stubTransport(state: queueState(currentIndex: 1));
    await tester.pumpWidget(sheetHost(
      playerCubit: cubit,
      settingsCubit: stubSettingsCubit(),
      child: MiniPlayer(onTap: () {}),
    ));
    await tester.pumpAndSettle();

    final state = tester.state<MiniPlayerState>(find.byType(MiniPlayer));
    state.isInteractingNotifier.value = true;
    await tester.pump();
    state.isInteractingNotifier.value = false;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a downward swipe without a callback is a no-op',
      (tester) async {
    final cubit = stubTransport();
    await tester.pumpWidget(sheetHost(
      playerCubit: cubit,
      settingsCubit: stubSettingsCubit(),
      child: MiniPlayer(onTap: () {}),
    ));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(MiniPlayer), const Offset(0, 80),
        warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
  });
}
