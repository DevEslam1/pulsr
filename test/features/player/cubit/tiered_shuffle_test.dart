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

  test('0.7 tieredShuffle passes queueIndex: currIdx to preserve active slot with past duplicate', () async {
    final handler = RecordingAudioHandler();

    final songAPast = buildSong(42, title: 'Song A (Past Duplicate)');
    final songACurrent = buildSong(42, title: 'Song A (Current)');
    final songB = buildSong(10, title: 'Song B');
    final songC = buildSong(11, title: 'Song C');

    final initialQueue = [songAPast, songACurrent, songB, songC];
    // Current index is 1 (songACurrent)
    var state = PlayerState(
      playback: PlaybackSlice(currentSong: songACurrent),
      queueSlice: QueueSlice(
        queue: initialQueue,
        currentIndex: 1,
      ),
    );

    final controller = PlayerQueueController(
      audioHandler: handler,
      repository: MockMusicRepository(),
      getState: () => state,
      emit: (s) => state = s,
      isClosed: () => false,
      queueMutex: Mutex(),
      slotLookupCache: <int, SongsTableData>{},
      queueSlots: <int, QueueSlotData>{},
      updateWidgetThrottled: ({bool force = false}) {},
      loadLyrics: (_) {},
      bumpQueueVersion: () {},
      isSameTrack: (a, b) => a?.id == b?.id,
    );

    // Call tieredShuffle
    await controller.tieredShuffle();

    // The current index must remain 1 (not 0, which would happen if indexWhere found the past duplicate)
    expect(state.currentIndex, 1);
    expect(state.currentSong?.id, 42);
    expect(state.queue[1].title, 'Song A (Current)');
  });
}
