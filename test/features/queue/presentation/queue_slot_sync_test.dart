// test/features/queue/presentation/queue_slot_sync_test.dart
//
// Regression tests ensuring QueueScreen, NowPlayingQueueView, and MiniPlayer
// share an identical Q1/Q2/Q3 queue slot mental model and track ordering.
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/mini_player.dart';
import 'package:pulsr/features/player/presentation/widgets/now_playing_queue_view.dart';
import 'package:pulsr/features/queue/presentation/queue_screen.dart';
import 'package:pulsr/features/queue/presentation/widgets/queue_slot_switcher.dart';
import 'package:pulsr/features/settings/cubit/settings_cubit.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/screen_harness.dart';
import '../../../helpers/test_song_factory.dart';

class _MockSettingsCubit extends Mock implements SettingsCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(createTestSong());
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('QueueScreen exposes Q1/Q2/Q3 switcher even on an empty slot',
      (tester) async {
    final player = stubPlayerCubit(
      const PlayerState(queueSlice: QueueSlice(activeQueueSlot: 1)),
    );
    when(() => player.switchQueueSlot(any())).thenAnswer((_) async {});

    await tester.pumpWidget(screenHarness(
      providers: [BlocProvider<PlayerCubit>.value(value: player)],
      child: const QueueScreen(),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(QueueSlotSwitcher), findsOneWidget);
    expect(find.text('Q1'), findsOneWidget);
    expect(find.text('Q2'), findsOneWidget);
    expect(find.text('Q3'), findsOneWidget);

    await tester.tap(find.text('Q1'));
    await tester.pump();
    verify(() => player.switchQueueSlot(0)).called(1);

    await tester.tap(find.text('Q3'));
    await tester.pump();
    verify(() => player.switchQueueSlot(2)).called(1);
  });

  testWidgets(
      'QueueScreen and NowPlayingQueueView share active slot and track ordering',
      (tester) async {
    final songs = [
      createTestSong(id: 10, title: 'Slot Two First'),
      createTestSong(id: 11, title: 'Slot Two Second'),
    ];
    final state = PlayerState(
      playback: PlaybackSlice(currentSong: songs.first),
      queueSlice: QueueSlice(
        queue: songs,
        currentIndex: 0,
        activeQueueSlot: 1,
      ),
    );
    final player = stubPlayerCubit(state);
    when(() => player.switchQueueSlot(any())).thenAnswer((_) async {});

    await tester.pumpWidget(screenHarness(
      providers: [BlocProvider<PlayerCubit>.value(value: player)],
      child: const QueueScreen(),
    ));
    await tester.pumpAndSettle();

    final firstScreenDy = tester.getTopLeft(find.text('Slot Two First')).dy;
    final secondScreenDy = tester.getTopLeft(find.text('Slot Two Second')).dy;
    expect(firstScreenDy, lessThan(secondScreenDy));
    expect(
      tester
          .widget<QueueSlotSwitcher>(find.byType(QueueSlotSwitcher))
          .activeSlot,
      1,
    );

    await tester.pumpWidget(screenHarness(
      providers: [BlocProvider<PlayerCubit>.value(value: player)],
      child: const Scaffold(
        body: SizedBox(
          height: 480,
          child: NowPlayingQueueView(),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final firstViewDy = tester.getTopLeft(find.text('Slot Two First')).dy;
    final secondViewDy = tester.getTopLeft(find.text('Slot Two Second')).dy;
    expect(firstViewDy, lessThan(secondViewDy));
    expect(
      tester
          .widget<QueueSlotSwitcher>(find.byType(QueueSlotSwitcher))
          .activeSlot,
      1,
    );
  });

  testWidgets('MiniPlayer reflects active queue slot switches immediately',
      (tester) async {
    final song1 = createTestSong(id: 1, title: 'Slot 1 Song');
    final song2 = createTestSong(id: 2, title: 'Slot 2 Song');
    final controller = StreamController<PlayerState>.broadcast();
    addTearDown(controller.close);

    var current = PlayerState(
      playback: PlaybackSlice(currentSong: song1),
      queueSlice: QueueSlice(
        queue: [song1],
        currentIndex: 0,
        activeQueueSlot: 0,
      ),
    );
    final player = MockPlayerCubit();
    when(() => player.state).thenAnswer((_) => current);
    when(() => player.stream).thenAnswer((_) => controller.stream);
    when(() => player.rawPositionStream)
        .thenAnswer((_) => const Stream<Duration>.empty());

    final settings = _MockSettingsCubit();
    when(() => settings.state).thenReturn(const SettingsState());
    when(() => settings.stream)
        .thenAnswer((_) => const Stream<SettingsState>.empty());

    await tester.pumpWidget(screenHarness(
      providers: [
        BlocProvider<PlayerCubit>.value(value: player),
        BlocProvider<SettingsCubit>.value(value: settings),
      ],
      child: Align(
        alignment: Alignment.bottomCenter,
        child: MiniPlayer(onTap: () {}),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Q1'), findsOneWidget);
    expect(find.text('Slot 1 Song'), findsWidgets);

    current = PlayerState(
      playback: PlaybackSlice(currentSong: song2),
      queueSlice: QueueSlice(
        queue: [song2],
        currentIndex: 0,
        activeQueueSlot: 2,
      ),
    );
    controller.add(current);
    await tester.pumpAndSettle();

    expect(find.text('Q3'), findsOneWidget);
    expect(find.text('Slot 2 Song'), findsWidgets);
  });
}
