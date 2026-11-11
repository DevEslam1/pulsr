import 'package:flutter_test/flutter_test.dart';
import 'package:mutex/mutex.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/cubit/controllers/player_queue_controller.dart';
import 'package:pulsr/features/player/cubit/controllers/queue_slot_data.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../player_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('0.6 calculateReorderedIndex semantics', () {
    test('moving current item updates current to newIndex', () {
      expect(calculateReorderedIndex(2, 5, 2), 5);
      expect(calculateReorderedIndex(4, 1, 4), 1);
      expect(calculateReorderedIndex(0, 0, 0), 0);
    });

    test('moving item from before current to after/at current shifts current left (-1)', () {
      // old < current && new >= current
      expect(calculateReorderedIndex(0, 3, 2), 1);
      expect(calculateReorderedIndex(1, 2, 2), 1);
      expect(calculateReorderedIndex(0, 5, 3), 2);
    });

    test('moving item from after current to before/at current shifts current right (+1)', () {
      // old > current && new <= current
      expect(calculateReorderedIndex(4, 1, 2), 3);
      expect(calculateReorderedIndex(3, 2, 2), 3);
      expect(calculateReorderedIndex(5, 0, 3), 4);
    });

    test('moving item without crossing current leaves current unchanged', () {
      // old < current && new < current
      expect(calculateReorderedIndex(0, 1, 3), 3);
      expect(calculateReorderedIndex(1, 0, 3), 3);
      // old > current && new > current
      expect(calculateReorderedIndex(4, 5, 2), 2);
      expect(calculateReorderedIndex(5, 4, 2), 2);
    });

    test('moving to ends', () {
      // move to top
      expect(calculateReorderedIndex(3, 0, 1), 2);
      // move to bottom
      expect(calculateReorderedIndex(1, 5, 3), 2);
    });
  });

  group('0.6 PlayerQueueController with duplicates and reorders', () {
    final trackA1 = buildSong(1, title: 'Track A (1)');
    final trackB = buildSong(2, title: 'Track B');
    final trackC = buildSong(3, title: 'Track C');
    final trackA2 = buildSong(1, title: 'Track A (duplicate)');
    final trackD = buildSong(4, title: 'Track D');

    late RecordingAudioHandler handler;

    setUp(() {
      handler = RecordingAudioHandler();
    });

    PlayerQueueController createController({
      required PlayerState Function() getState,
      required void Function(PlayerState) emit,
    }) {
      return PlayerQueueController(
        audioHandler: handler,
        repository: MockMusicRepository(),
        getState: getState,
        emit: emit,
        isClosed: () => false,
        queueMutex: Mutex(),
        slotLookupCache: <int, SongsTableData>{},
        queueSlots: <int, QueueSlotData>{},
        updateWidgetThrottled: ({bool force = false}) {},
        loadLyrics: (_) {},
        bumpQueueVersion: () {},
        isSameTrack: (a, b) => a?.id == b?.id,
      );
    }

    test('playNext with duplicate in queue moves non-current duplicate to next', () async {
      // Queue: [Track A (curr=0), Track B (1), Track C (2), Track A (3)]
      final initialQueue = [trackA1, trackB, trackC, trackA2];
      var state = PlayerState(
        queueSlice: QueueSlice(
          queue: initialQueue,
          currentIndex: 0,
        ),
      );

      final controller = createController(
        getState: () => state,
        emit: (s) => state = s,
      );

      // Play Next on Track A: since trackA1 is playing at index 0, it should find
      // trackA2 at index 3 and move it to index 1 (next)!
      await controller.playNext(trackA2);

      expect(state.queue.length, 4);
      expect(state.queue[0].title, 'Track A (1)');
      expect(state.queue[1].title, 'Track A (duplicate)');
      expect(state.queue[2].title, 'Track B');
      expect(state.queue[3].title, 'Track C');
      expect(state.currentIndex, 0);
    });

    test('addToQueue with duplicate in queue moves non-current duplicate to end', () async {
      // Queue: [Track A (curr=0), Track B (1), Track A (2), Track C (3)]
      final initialQueue = [trackA1, trackB, trackA2, trackC];
      var state = PlayerState(
        queueSlice: QueueSlice(
          queue: initialQueue,
          currentIndex: 0,
        ),
      );

      final controller = createController(
        getState: () => state,
        emit: (s) => state = s,
      );

      // Add To Queue on Track A: should move trackA2 (index 2) to end (index 3)
      await controller.addToQueue(trackA2);

      expect(state.queue.length, 4);
      expect(state.queue[0].title, 'Track A (1)');
      expect(state.queue[1].title, 'Track B');
      expect(state.queue[2].title, 'Track C');
      expect(state.queue[3].title, 'Track A (duplicate)');
      expect(state.currentIndex, 0);
    });

    test('reorderQueue moves items up, down, around current and updates currentIndex', () async {
      // Queue: [0: A, 1: B (current), 2: C, 3: D]
      final initialQueue = [trackA1, trackB, trackC, trackD];
      var state = PlayerState(
        queueSlice: QueueSlice(
          queue: initialQueue,
          currentIndex: 1,
        ),
      );

      final controller = createController(
        getState: () => state,
        emit: (s) => state = s,
      );

      // 1. Move after-current (index 3) to before-current (index 0)
      // currentIndex should shift from 1 to 2
      await controller.reorderQueue(3, 0);
      expect(state.currentIndex, 2);
      expect(state.queue[2].title, 'Track B');

      // 2. Move current track (index 2) to end (index 3)
      await controller.reorderQueue(2, 3);
      expect(state.currentIndex, 3);
      expect(state.queue[3].title, 'Track B');

      // 3. Move before-current (index 0) to after-current (index 3)
      // currentIndex should shift from 3 to 2
      await controller.reorderQueue(0, 3);
      expect(state.currentIndex, 2);
      expect(state.queue[2].title, 'Track B');
    });
  });
}
