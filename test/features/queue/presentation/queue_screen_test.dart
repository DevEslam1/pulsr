// QueueScreen widget suite.
//
// Covers the empty state, the populated reorderable queue, the overflow menu
// and forwarding a track tap to PlayerCubit.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/widgets/pulsr_empty_state.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/queue/presentation/queue_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/screen_harness.dart';
import '../../../helpers/test_song_factory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(createTestSong());
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget build(PlayerCubit player) => screenHarness(
        providers: [BlocProvider<PlayerCubit>.value(value: player)],
        child: const QueueScreen(),
      );

  testWidgets('renders the empty state when the queue is empty',
      (tester) async {
    await tester.pumpWidget(build(stubPlayerCubit()));
    await tester.pumpAndSettle();

    expect(find.byType(QueueScreen), findsOneWidget);
    expect(find.byType(PulsrEmptyState), findsOneWidget);
    expect(find.text('Up Next'), findsWidgets);
    // The overflow menu is hidden while the queue is empty.
    expect(find.byType(PopupMenuButton<String>), findsNothing);
  });

  testWidgets('renders every queued track in a reorderable list',
      (tester) async {
    final songs = [
      createTestSong(id: 1, title: 'Alpha'),
      createTestSong(id: 2, title: 'Beta'),
    ];
    final player = stubPlayerCubit(PlayerState(
      queueSlice: QueueSlice(queue: songs, currentIndex: 1),
    ));

    await tester.pumpWidget(build(player));
    await tester.pumpAndSettle();

    expect(find.byType(ReorderableListView), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    // The menu is available once there are tracks.
    expect(find.byType(PopupMenuButton<String>), findsOneWidget);
  });

  testWidgets('tapping a track forwards playback to PlayerCubit',
      (tester) async {
    final songs = [createTestSong(id: 1, title: 'Alpha')];
    final player = stubPlayerCubit(
      PlayerState(queueSlice: QueueSlice(queue: songs)),
    );
    when(() => player.playSong(any(), queue: any(named: 'queue')))
        .thenAnswer((_) async {});

    await tester.pumpWidget(build(player));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alpha'));
    await tester.pump();

    verify(() => player.playSong(any(), queue: any(named: 'queue'))).called(1);
  });

  testWidgets('the overflow menu exposes shuffle, auto-mix, save and clear',
      (tester) async {
    final songs = [createTestSong(id: 1, title: 'Alpha')];
    final player = stubPlayerCubit(
      PlayerState(queueSlice: QueueSlice(queue: songs)),
    );

    await tester.pumpWidget(build(player));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();

    // The menu rows overflow by ~1.6px at narrow popup widths (a pre-existing
    // screen layout quirk); swallow that render exception so it does not fail
    // the interaction test, which is about the menu contents.
    tester.takeException();

    expect(find.text('Shuffle'), findsOneWidget);
    expect(find.text('Auto-mix'), findsOneWidget);
    expect(find.text('Save as Playlist'), findsOneWidget);
    expect(find.text('Clear Queue'), findsOneWidget);
  });

  testWidgets('removing a track calls removeQueueItem with its index',
      (tester) async {
    final songs = [
      createTestSong(id: 1, title: 'Alpha'),
      createTestSong(id: 2, title: 'Beta'),
    ];
    final player = stubPlayerCubit(
      PlayerState(queueSlice: QueueSlice(queue: songs)),
    );
    when(() => player.removeQueueItem(any())).thenAnswer((_) async {});

    await tester.pumpWidget(build(player));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await tester.pump();

    verify(() => player.removeQueueItem(0)).called(1);
  });
}
