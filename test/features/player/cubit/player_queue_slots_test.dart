// Coverage for the uncovered branches of player_queue_slots.dart.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mutex/mutex.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/cubit/controllers/player_controllers.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../player_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RecordingAudioHandler handler;
  late MockMusicRepository repo;
  late PlayerState state;
  late Map<int, SongsTableData> cache;
  late Map<int, QueueSlotData> slots;
  late bool closed;
  late int debounced;
  late int bumped;
  late int invalidated;

  PlayerQueueController buildController() => PlayerQueueController(
        audioHandler: handler,
        repository: repo,
        getState: () => state,
        emit: (s) => state = s,
        isClosed: () => closed,
        queueMutex: Mutex(),
        slotLookupCache: cache,
        queueSlots: slots,
        updateWidgetThrottled: ({bool force = false}) {},
        loadLyrics: (_) {},
        debouncedPersistQueueSlots: () => debounced++,
        bumpQueueVersion: () => bumped++,
        isSameTrack: (a, b) => a?.id == b?.id,
        invalidateQueueSyncResolution: () => invalidated++,
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    handler = RecordingAudioHandler();
    repo = MockMusicRepository();
    state = const PlayerState();
    cache = <int, SongsTableData>{};
    slots = <int, QueueSlotData>{};
    closed = false;
    debounced = 0;
    bumped = 0;
    invalidated = 0;
    when(() => repo.getSongsByIds(any()))
        .thenAnswer((_) async => right(<SongsTableData>[]));
  });

  PlayerState stateWithQueue(List<SongsTableData> queue,
          {int currentIndex = 0, int activeSlot = 0}) =>
      PlayerState(
        queueSlice: QueueSlice(
            queue: queue, currentIndex: currentIndex, activeQueueSlot: activeSlot),
      );

  group('persistQueueSlotsNow', () {
    test('is a no-op when the controller is closed', () async {
      closed = true;
      await buildController().persistQueueSlotsNow();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(PrefsKeys.queueSlots), isNull);
    });

    test('writes the encoded document on success', () async {
      state = stateWithQueue([buildSong(1)]);
      final controller = buildController();
      controller.setQueueSlot(0,
          songs: [buildSong(1)],
          currentIndex: 0,
          position: Duration.zero,
          speed: 1.0);
      await controller.persistQueueSlotsNow();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(PrefsKeys.queueSlots), isNotNull);
    });
  });

  group('restoreQueueSlots', () {
    test('returns early when nothing is persisted', () async {
      await buildController().restoreQueueSlots();
      expect(slots, isEmpty);
    });

    test('skips corrupt/unknown keys and restores valid slots', () async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.queueSlots: jsonEncode({
          'schemaVersion': 1,
          'activeSlot': 1,
          'notASlot': {
            'songIds': [9],
            'currentIndex': 0,
            'positionMs': 0,
            'speed': 1.0,
          },
          '1': {
            'songIds': [2],
            'currentIndex': 0,
            'positionMs': 0,
            'speed': 1.0,
          },
        }),
      });
      when(() => repo.getSongsByIds([2]))
          .thenAnswer((_) async => right([buildSong(2)]));

      await buildController().restoreQueueSlots();

      expect(slots.containsKey(1), isTrue);
      expect(slots[1]!.songIds, [2]);
      expect(state.activeQueueSlot, 1);
    });

    test('does not overwrite a live active slot (cold-start race)', () async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.queueSlots: jsonEncode({
          'schemaVersion': 1,
          'activeSlot': 0,
          '0': {
            'songIds': [2],
            'currentIndex': 0,
            'positionMs': 0,
            'speed': 1.0,
          },
        }),
      });
      when(() => repo.getSongsByIds([2]))
          .thenAnswer((_) async => right([buildSong(2)]));

      state = stateWithQueue([buildSong(1)], activeSlot: 0);
      await buildController().restoreQueueSlots();

      // Active slot already has a live queue: leave it untouched.
      expect(slots.containsKey(0), isFalse);
    });

    test('re-anchors the current index by identity when ids shift', () async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.queueSlots: jsonEncode({
          'schemaVersion': 1,
          '0': {
            'songIds': [1, 2, 3],
            'currentIndex': 2,
            'positionMs': 5000,
            'speed': 1.25,
          },
        }),
      });
      // Only 3 and 1 resolve; the order must follow the persisted ids.
      when(() => repo.getSongsByIds([1, 2, 3]))
          .thenAnswer((_) async => right([buildSong(3), buildSong(1)]));

      await buildController().restoreQueueSlots();

      expect(slots[0]!.songIds, [1, 3]);
      // Anchor id 3 now lives at index 1.
      expect(slots[0]!.currentIndex, 1);
      expect(slots[0]!.speed, 1.25);
    });

    test('logs and continues when a slot lookup throws', () async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.queueSlots: jsonEncode({
          'schemaVersion': 1,
          '0': {
            'songIds': [1],
            'currentIndex': 0,
            'positionMs': 0,
            'speed': 1.0,
          },
        }),
      });
      when(() => repo.getSongsByIds([1]))
          .thenThrow(Exception('DB exploded'));

      await buildController().restoreQueueSlots();
      expect(slots, isEmpty);
    });
  });

  group('clearQueue', () {
    test('retains the current song', () async {
      final song = buildSong(1);
      state = stateWithQueue([song]);
      state = state.copyWith(
          playback: state.playback.copyWith(currentSong: song));
      final controller = buildController();
      await controller.clearQueue();
      expect(state.queue.length, 1);
      expect(state.queue.first.id, 1);
      expect(handler.calls, contains('clearQueue'));
    });

    test('empties the queue when there is no current song', () async {
      state = stateWithQueue([buildSong(1)]);
      await buildController().clearQueue();
      expect(state.queue, isEmpty);
    });
  });

  group('restoreQueue', () {
    test('is a no-op for an empty previous queue', () async {
      await buildController().restoreQueue(const [], 3);
      expect(state.queue, isEmpty);
      expect(handler.calls, isNot(contains('loadQueue')));
    });

    test('restores a non-empty queue and clamps the index', () async {
      final controller = buildController();
      await controller.restoreQueue([buildSong(1), buildSong(2)], 9);
      expect(state.queue.length, 2);
      expect(state.currentIndex, 1);
      expect(handler.calls, contains('loadQueue'));
    });
  });

  group('reorderQueue', () {
    test('ignores out-of-range indices', () async {
      state = stateWithQueue([buildSong(1), buildSong(2)]);
      await buildController().reorderQueue(0, 5);
      expect(state.queue.map((s) => s.id), [1, 2]);
      expect(handler.calls, isNot(contains('reorderQueue')));
    });

    test('adjusts the current index for each move direction', () async {
      state = stateWithQueue([buildSong(1), buildSong(2), buildSong(3)],
          currentIndex: 2);
      final controller = buildController();
      // Move an item before the current index.
      await controller.reorderQueue(0, 2);
      expect(state.currentIndex, 1);
      expect(handler.calls, contains('reorderQueue'));
    });

    test('rolls back when the handler throws', () async {
      state = stateWithQueue([buildSong(1), buildSong(2), buildSong(3)],
          currentIndex: 0);
      handler.throwCalls.add('reorderQueue');
      await buildController().reorderQueue(1, 2);
      expect(state.queue.map((s) => s.id), [1, 2, 3]);
      expect(state.errorMessage, 'Failed to reorder queue');
    });
  });

  group('removeQueueItem', () {
    test('ignores out-of-range indices', () async {
      state = stateWithQueue([buildSong(1)]);
      await buildController().removeQueueItem(4);
      expect(state.queue.length, 1);
    });

    test('clears everything when the last item is removed', () async {
      state = stateWithQueue([buildSong(1)]);
      state = state.copyWith(
          playback: state.playback.copyWith(currentSong: buildSong(1)));
      await buildController().removeQueueItem(0);
      expect(state.queue, isEmpty);
      expect(state.currentSong, isNull);
      expect(handler.calls, contains('clearQueue'));
    });

    test('removing the current item advances to the next song', () async {
      final songs = [buildSong(1), buildSong(2), buildSong(3)];
      state = stateWithQueue(songs, currentIndex: 1);
      state = state.copyWith(
          playback: state.playback.copyWith(currentSong: songs[1]));
      await buildController().removeQueueItem(1);
      expect(state.currentSong?.id, 3);
      expect(state.currentIndex, 1);
      expect(handler.calls, contains('removeQueueItemAt'));
    });

    test('removing an item before the current one shifts the index', () async {
      final songs = [buildSong(1), buildSong(2), buildSong(3)];
      state = stateWithQueue(songs, currentIndex: 2);
      state = state.copyWith(
          playback: state.playback.copyWith(currentSong: songs[2]));
      await buildController().removeQueueItem(0);
      expect(state.currentIndex, 1);
      expect(state.currentSong?.id, 3);
    });

    test('rolls back when the handler throws', () async {
      final songs = [buildSong(1), buildSong(2)];
      state = stateWithQueue(songs, currentIndex: 0);
      handler.throwCalls.add('removeQueueItemAt');
      await buildController().removeQueueItem(1);
      expect(state.queue.map((s) => s.id), [1, 2]);
    });
  });

  group('switchQueueSlot', () {
    test('returns early when already on the requested slot', () async {
      state = stateWithQueue([buildSong(1)], activeSlot: 1);
      await buildController().switchQueueSlot(1);
      expect(handler.calls, isNot(contains('loadQueue')));
    });

    test('emits an error when the target slot has no playable songs',
        () async {
      state = stateWithQueue([buildSong(1)], activeSlot: 0);
      await buildController().switchQueueSlot(2);
      expect(state.errorMessage, 'Queue slot is empty');
    });

    test('filters missing songs out of the target slot', () async {
      state = stateWithQueue([buildSong(1)], activeSlot: 0);
      final controller = buildController();
      controller.setQueueSlot(1,
          songs: [buildSong(2, isMissing: true)],
          currentIndex: 0,
          position: Duration.zero,
          speed: 1.0);
      await controller.switchQueueSlot(1);
      expect(state.errorMessage, 'Queue slot is empty');
    });

    test('switches to a populated slot and loads it', () async {
      state = stateWithQueue([buildSong(1)], activeSlot: 0);
      final controller = buildController();
      controller.setQueueSlot(1,
          songs: [buildSong(2), buildSong(3)],
          currentIndex: 1,
          position: const Duration(seconds: 5),
          speed: 1.5);
      await controller.switchQueueSlot(1);
      expect(state.activeQueueSlot, 1);
      expect(state.currentSong?.id, 3);
      expect(handler.calls, contains('loadQueue'));
    });

    test('rolls back when the engine load fails', () async {
      state = stateWithQueue([buildSong(1)], activeSlot: 0);
      final controller = buildController();
      controller.setQueueSlot(1,
          songs: [buildSong(2)],
          currentIndex: 0,
          position: Duration.zero,
          speed: 1.0);
      handler.throwCalls.add('loadQueue');
      await controller.switchQueueSlot(1);
      expect(state.errorMessage, 'Failed to switch queue slot');
      expect(state.activeQueueSlot, 0);
    });
  });

  group('swapReconciledSong', () {
    test('ignores a null old id', () async {
      await buildController().swapReconciledSong(null, buildSong(2));
      expect(handler.calls, isNot(contains('swapReconciledSong')));
    });

    test('ignores a same-id swap', () async {
      await buildController().swapReconciledSong(1, buildSong(1));
      expect(handler.calls, isNot(contains('swapReconciledSong')));
    });

    test('resolves an int new id through the repository', () async {
      when(() => repo.getSongById(2))
          .thenAnswer((_) async => right(buildSong(2)));
      state = stateWithQueue([buildSong(1)]);
      state = state.copyWith(
          playback: state.playback.copyWith(currentSong: buildSong(1)));
      await buildController().swapReconciledSong(1, 2);
      expect(state.queue.first.id, 2);
      expect(handler.calls, contains('swapReconciledSong'));
    });

    test('ignores a new song already present in the queue', () async {
      state = stateWithQueue([buildSong(1), buildSong(2)]);
      await buildController().swapReconciledSong(1, buildSong(2));
      expect(handler.calls, isNot(contains('swapReconciledSong')));
    });

    test('unresolvable int new id is a no-op', () async {
      when(() => repo.getSongById(2))
          .thenAnswer((_) async => left(DatabaseFailure('missing')));
      await buildController().swapReconciledSong(1, 2);
      expect(handler.calls, isNot(contains('swapReconciledSong')));
    });
  });

  group('addToQueue', () {
    test('reorders an existing non-tail song to the end', () async {
      state = stateWithQueue([buildSong(1), buildSong(2), buildSong(3)]);
      await buildController().addToQueue(buildSong(2));
      expect(state.queue.map((s) => s.id), [1, 3, 2]);
    });

    test('is a no-op for the current or tail song', () async {
      state = stateWithQueue([buildSong(1), buildSong(2), buildSong(3)]);
      await buildController().addToQueue(buildSong(1));
      expect(state.queue.map((s) => s.id), [1, 2, 3]);
    });

    test('rejects when the queue is full', () async {
      state = stateWithQueue(List.generate(500, (i) => buildSong(i + 1)));
      await buildController().addToQueue(buildSong(999));
      expect(state.errorMessage, contains('Queue full'));
    });

    test('surfaces a handler failure', () async {
      state = stateWithQueue([buildSong(1)]);
      handler.throwCalls.add('addToQueueEnd');
      await buildController().addToQueue(buildSong(2));
      expect(state.errorMessage, contains('Failed to add'));
    });

    test('appends a new song on success', () async {
      state = stateWithQueue([buildSong(1)]);
      await buildController().addToQueue(buildSong(2));
      expect(state.queue.map((s) => s.id), [1, 2]);
      expect(handler.calls, contains('addToQueueEnd'));
    });
  });

  group('playNext', () {
    test('delegates to addToQueue when the queue is empty', () async {
      await buildController().playNext(buildSong(1));
      expect(state.queue.length, 1);
      expect(handler.calls, contains('addToQueueEnd'));
    });

    test('is a no-op when the song is current or already next', () async {
      state = stateWithQueue([buildSong(1), buildSong(2), buildSong(3)],
          currentIndex: 0);
      await buildController().playNext(buildSong(2));
      expect(state.queue.map((s) => s.id), [1, 2, 3]);
      expect(handler.calls, isNot(contains('insertNextInQueue')));
    });

    test('reorders an existing song toward the next slot', () async {
      state = stateWithQueue(
          [buildSong(1), buildSong(2), buildSong(3), buildSong(4)],
          currentIndex: 0);
      await buildController().playNext(buildSong(4));
      expect(state.queue.map((s) => s.id), [1, 4, 2, 3]);
    });

    test('rejects when the queue is full', () async {
      state = stateWithQueue(List.generate(500, (i) => buildSong(i + 1)));
      await buildController().playNext(buildSong(999));
      expect(state.errorMessage, contains('Queue full'));
    });

    test('surfaces a handler failure', () async {
      state = stateWithQueue([buildSong(1)]);
      handler.throwCalls.add('insertNextInQueue');
      await buildController().playNext(buildSong(2));
      expect(state.errorMessage, contains('Failed to add'));
    });

    test('inserts a new song right after the current one', () async {
      state = stateWithQueue([buildSong(1), buildSong(2)], currentIndex: 0);
      await buildController().playNext(buildSong(3));
      expect(state.queue.map((s) => s.id), [1, 3, 2]);
      expect(handler.calls, contains('insertNextInQueue'));
    });
  });

  group('addAllToQueue', () {
    test('ignores an empty input', () async {
      state = stateWithQueue([buildSong(1)]);
      await buildController().addAllToQueue(const []);
      expect(handler.calls, isNot(contains('addToQueueEnd')));
    });

    test('rejects when there is no room', () async {
      state = stateWithQueue(List.generate(500, (i) => buildSong(i + 1)));
      await buildController().addAllToQueue([buildSong(999)]);
      expect(state.errorMessage, contains('Queue full'));
    });

    test('deduplicates against the existing queue', () async {
      state = stateWithQueue([buildSong(1)]);
      await buildController()
          .addAllToQueue([buildSong(1), buildSong(2), buildSong(2)]);
      expect(state.queue.map((s) => s.id), [1, 2]);
    });

    test('reports a partial batch failure', () async {
      state = stateWithQueue([buildSong(1)]);
      var count = 0;
      handler.failWhen = (name) {
        if (name == 'addToQueueEnd') {
          count++;
          if (count == 2) return Exception('second add failed');
        }
        return null;
      };
      await buildController()
          .addAllToQueue([buildSong(2), buildSong(3), buildSong(4)]);
      expect(state.errorMessage, contains('Added 1 of 3'));
      expect(state.queue.map((s) => s.id), [1, 2]);
    });

    test('surfaces a total batch failure', () async {
      state = stateWithQueue([buildSong(1)]);
      handler.throwCalls.add('addToQueueEnd');
      await buildController().addAllToQueue([buildSong(2)]);
      expect(state.errorMessage, 'Failed to add songs to queue');
    });

    test('appends a deduplicated batch on success', () async {
      state = stateWithQueue([buildSong(1)]);
      await buildController().addAllToQueue([buildSong(2), buildSong(3)]);
      expect(state.queue.map((s) => s.id), [1, 2, 3]);
    });
  });

  group('slot lookup cache', () {
    test('evicts the oldest entries beyond the cap', () async {
      final controller = buildController();
      final many = List.generate(4100, (i) => buildSong(i + 1));
      controller.setQueueSlot(0,
          songs: many,
          currentIndex: 0,
          position: Duration.zero,
          speed: 1.0);
      expect(cache.length, lessThanOrEqualTo(4096));
      // The most recently written ids survive.
      expect(cache.containsKey(4100), isTrue);
    });
  });
}
