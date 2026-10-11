// test/features/player/player_queue_rollback_test.dart
//
// Regression coverage for queue mutation rollbacks re-emitting stale playback,
// and for the coalesced-seek cancellation wired into track-change paths.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mutex/mutex.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/cubit/controllers/player_controllers.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';

import 'player_test_support.dart';

class _GatedLoadHandler extends RecordingAudioHandler {
  final Completer<void> gate = Completer<void>();

  @override
  Future<void> loadQueue(
    List<SongsTableData> songs, {
    int initialIndex = 0,
    Duration? initialPosition,
    bool autoPlay = true,
  }) async {
    await gate.future;
    throw Exception('engine load failed');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  PlayerQueueController build(
    RecordingAudioHandler handler, {
    required PlayerState Function() getState,
    required void Function(PlayerState) emit,
    void Function()? cancelPendingSeek,
  }) =>
      PlayerQueueController(
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
        cancelPendingSeek: cancelPendingSeek,
      );

  test('playSong failure does not roll back a track change that superseded it',
      () async {
    final handler = _GatedLoadHandler();
    var state = PlayerState(
      playback: PlaybackSlice(
          currentSong: buildSong(1), position: const Duration(seconds: 5)),
      queueSlice: QueueSlice(queue: [buildSong(1)], currentIndex: 0),
    );
    final controller = build(
      handler,
      getState: () => state,
      emit: (s) => state = s,
    );

    final play = controller.playSong(buildSong(2));
    await pumpEventQueue();
    expect(state.currentSong?.id, 2); // optimistic selection

    // The user skips to a third track while the failing load is still running.
    state = state.copyWith(
      playback: state.playback.copyWith(
        currentSong: buildSong(3),
        position: const Duration(seconds: 9),
      ),
    );

    handler.gate.complete();
    await play;

    // The rollback must keep the newer selection and only surface the error.
    expect(state.currentSong?.id, 3);
    expect(state.position, const Duration(seconds: 9));
    expect(state.errorMessage, contains('Failed to play'));
  });

  test('playSong failure still rolls back when no newer track superseded it',
      () async {
    final handler = RecordingAudioHandler();
    var loadCalls = 0;
    handler.failWhen = (name) {
      if (name == 'loadQueue' && loadCalls++ == 0) {
        return Exception('engine load failed');
      }
      return null;
    };
    var state = PlayerState(
      playback: PlaybackSlice(
          currentSong: buildSong(1), position: const Duration(seconds: 5)),
      queueSlice: QueueSlice(queue: [buildSong(1)], currentIndex: 0),
    );
    final controller = build(
      handler,
      getState: () => state,
      emit: (s) => state = s,
    );

    await controller.playSong(buildSong(2));

    expect(state.currentSong?.id, 1);
    expect(state.position, const Duration(seconds: 5));
    expect(state.errorMessage, contains('Failed to play'));
  });

  test('playSong and switchQueueSlot cancel a pending coalesced seek',
      () async {
    final handler = RecordingAudioHandler();
    var cancelled = 0;
    var state = PlayerState(
      queueSlice:
          QueueSlice(queue: [buildSong(1), buildSong(2)], currentIndex: 0),
    );
    final controller = build(
      handler,
      getState: () => state,
      emit: (s) => state = s,
      cancelPendingSeek: () => cancelled++,
    );

    await controller.playSong(buildSong(2));
    expect(cancelled, 1);

    controller.setQueueSlot(
      1,
      songs: [buildSong(3)],
      currentIndex: 0,
      position: Duration.zero,
      speed: 1.0,
    );
    await controller.switchQueueSlot(1);
    expect(cancelled, 2);
  });
}
