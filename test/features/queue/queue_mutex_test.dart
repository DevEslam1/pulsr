// test/features/queue/queue_mutex_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mutex/mutex.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';
import 'package:pulsr/features/player/cubit/controllers/player_queue_controller.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';

import '../../helpers/test_pulsr_audio_handler.dart';

class MockMusicRepository extends Mock implements IMusicRepository {}

/// Delays every `addToQueueEnd` so two overlapping `addToQueue` calls would
/// interleave their read-modify-write windows if they were not serialized.
class _DelayedQueueHandler extends TestPulsrAudioHandler {
  Duration addDelay = const Duration(milliseconds: 20);

  @override
  Future<void> addToQueueEnd(SongsTableData song) async {
    await Future<void>.delayed(addDelay);
  }
}

SongsTableData _song(int id) => SongsTableData(
      id: id,
      title: 'Song $id',
      artist: 'Artist $id',
      album: 'Album $id',
      durationMs: 180000,
      path: '/path/$id.mp3',
      isFavorite: false,
      isMissing: false,
      isDownloaded: false,
      playCount: 0,
      lastPositionMs: 0,
      source: SongSource.local,
    );

void main() {
  test('concurrent addToQueue calls do not lose tracks', () async {
    final seed = _song(1);
    final songA = _song(2);
    final songB = _song(3);

    var state = PlayerState(
      queueSlice: QueueSlice(queue: [seed], currentIndex: 0),
      playback: PlaybackSlice(currentSong: seed),
    );

    final controller = PlayerQueueController(
      audioHandler: _DelayedQueueHandler(),
      repository: MockMusicRepository(),
      getState: () => state,
      emit: (s) => state = s,
      isClosed: () => false,
      queueMutex: Mutex(),
      slotLookupCache: {},
      queueSlots: {},
      updateWidgetThrottled: ({bool force = false}) {},
      loadLyrics: (_) {},
      debouncedPersistQueueSlots: () {},
      bumpQueueVersion: () {},
      isSameTrack: (a, b) => a?.id == b?.id,
      invalidateQueueSyncResolution: () {},
    );

    // Fire two appends without awaiting between them: without the queue mutex
    // both would read the same [seed] snapshot and clobber one another.
    await Future.wait([
      controller.addToQueue(songA),
      controller.addToQueue(songB),
    ]);

    final ids = state.queue.map((s) => s.id).toList();
    expect(ids.toSet(), {seed.id, songA.id, songB.id});
    expect(state.queue.length, 3);

    controller.dispose();
  });
}
