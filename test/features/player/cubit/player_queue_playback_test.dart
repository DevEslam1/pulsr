// Regression tests for player_queue_playback.dart.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mutex/mutex.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/cubit/controllers/player_controllers.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../player_test_support.dart';

class _LoadQueueCapturingHandler extends RecordingAudioHandler {
  Duration? lastInitialPosition;
  bool? lastAutoPlay;

  @override
  Future<void> loadQueue(
    List<SongsTableData> songs, {
    int initialIndex = 0,
    Duration? initialPosition,
    bool autoPlay = true,
  }) {
    lastInitialPosition = initialPosition;
    lastAutoPlay = autoPlay;
    return super.loadQueue(
      songs,
      initialIndex: initialIndex,
      initialPosition: initialPosition,
      autoPlay: autoPlay,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _LoadQueueCapturingHandler handler;
  late MockMusicRepository repo;
  late PlayerState state;
  late Map<int, SongsTableData> cache;
  late Map<int, QueueSlotData> slots;
  late bool closed;

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
        debouncedPersistQueueSlots: () {},
        bumpQueueVersion: () {},
        isSameTrack: (a, b) => a?.id == b?.id,
        invalidateQueueSyncResolution: () {},
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    handler = _LoadQueueCapturingHandler();
    repo = MockMusicRepository();
    state = const PlayerState();
    cache = <int, SongsTableData>{};
    slots = <int, QueueSlotData>{};
    closed = false;
  });

  group('PlayerQueuePlaybackExtension.playSong', () {
    test(
        're-reads live state after findMatchingLocalSong so position ticks and '
        'isPlaying changes survive optimistic emit', () async {
      final ytSong = buildSong(
        1,
        source: SongSource.youtube,
        remoteId: 'yt-1',
        path: 'ytmusic://yt-1',
      );
      final song2 = buildSong(2);

      state = PlayerState(
        queueSlice: QueueSlice(
          queue: [ytSong, song2],
          currentIndex: 0,
          queueHistory: const [],
        ),
        playback: PlaybackSlice(
          currentSong: ytSong,
          position: const Duration(seconds: 5),
          isPlaying: false,
          isBuffering: false,
        ),
      );

      final matchCompleter = Completer<Result<SongsTableData?>>();
      when(() => repo.findMatchingLocalSong(
            remoteId: 'yt-1',
            title: ytSong.title,
            artist: ytSong.artist,
          )).thenAnswer((_) => matchCompleter.future);

      final controller = buildController();
      // Pass a reordered queue so the early-resume shortcut is bypassed and
      // _playSongLocked awaits findMatchingLocalSong.
      final playFuture = controller.playSong(
        ytSong,
        queue: [song2, ytSong],
        preservePlaybackState: true,
      );

      await Future<void>.delayed(Duration.zero);

      // Simulate concurrent engine position tick, play-state flip, buffering,
      // and history update arriving while findMatchingLocalSong is pending.
      state = state.copyWith(
        playback: state.playback.copyWith(
          position: const Duration(seconds: 17),
          isPlaying: true,
          isBuffering: true,
        ),
        queueSlice: state.queueSlice.copyWith(
          queueHistory: [song2],
        ),
      );

      matchCompleter.complete(right(null));
      await playFuture;

      expect(state.position, const Duration(seconds: 17));
      expect(state.isPlaying, isTrue);
      expect(state.isBuffering, isTrue);
      expect(state.queueHistory, [song2]);
      expect(handler.lastInitialPosition, const Duration(seconds: 17));
      expect(handler.lastAutoPlay, isTrue);
    });
  });
}
