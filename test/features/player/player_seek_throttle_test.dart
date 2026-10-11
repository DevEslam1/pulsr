// test/features/player/player_seek_throttle_test.dart
//
// Regression coverage for the coalesced-seek leak across track changes: a
// scrub release followed by next()/previous()/skipToQueueItem()/playSong()
// within the throttle window must not seek the NEW track to the old position.
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/player/cubit/controllers/player_controllers.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';

import 'player_test_support.dart';

class _SeekRecordingHandler extends RecordingAudioHandler {
  final List<Duration> seeks = <Duration>[];

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
  }

  @override
  Future<void> seekDirect(Duration position) async {
    seeks.add(position);
  }

  @override
  Future<void> skipToNext() async {}

  @override
  Future<void> skipToPrevious() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  PlayerState stateFor() => PlayerState(
        playback: const PlaybackSlice(position: Duration(seconds: 30)),
        queueSlice:
            QueueSlice(queue: [buildSong(1), buildSong(2)], currentIndex: 0),
      );

  PlayerTransportController build(
    _SeekRecordingHandler handler,
    PlayerState Function() getState,
    void Function(PlayerState) emit,
  ) =>
      PlayerTransportController(
        audioHandler: handler,
        getState: getState,
        emit: emit,
        isClosed: () => false,
      );

  test('next() drops a coalesced trailing seek from the previous track', () {
    fakeAsync((async) {
      final handler = _SeekRecordingHandler();
      var state = stateFor();
      final controller = build(handler, () => state, (s) => state = s);

      controller.seek(const Duration(seconds: 30));
      expect(handler.seeks, [const Duration(seconds: 30)]);

      // Inside the throttle window: coalesced onto a trailing timer.
      controller.seek(const Duration(seconds: 31));
      controller.next();
      async.elapse(const Duration(seconds: 1));

      expect(handler.seeks, [const Duration(seconds: 30)]);
      controller.dispose();
    });
  });

  test('previous() and skipToQueueItem() also drop the pending seek', () {
    fakeAsync((async) {
      final handler = _SeekRecordingHandler();
      var state = stateFor();
      final controller = build(handler, () => state, (s) => state = s);

      controller.seek(const Duration(seconds: 30));
      expect(handler.seeks, [const Duration(seconds: 30)]);

      controller.seek(const Duration(seconds: 31));
      controller.previous();
      async.elapse(const Duration(seconds: 1));
      expect(handler.seeks, [const Duration(seconds: 30)]);

      // A fresh pending seek for the next track must be dropped as well.
      controller.seek(const Duration(seconds: 32));
      controller.skipToQueueItem(1);
      async.elapse(const Duration(seconds: 1));
      expect(handler.seeks, [const Duration(seconds: 30)]);
      controller.dispose();
    });
  });

  test('a trailing seek still fires when no track change intervenes', () {
    fakeAsync((async) {
      final handler = _SeekRecordingHandler();
      var state = stateFor();
      final controller = build(handler, () => state, (s) => state = s);

      controller.seek(const Duration(seconds: 30));
      controller.seek(const Duration(seconds: 31));
      async.elapse(const Duration(seconds: 1));

      expect(handler.seeks,
          [const Duration(seconds: 30), const Duration(seconds: 31)]);
      controller.dispose();
    });
  });
}
