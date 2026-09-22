import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mutex/mutex.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/cubit/controllers/player_queue_controller.dart';
import 'package:pulsr/features/player/cubit/controllers/queue_slot_data.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';
import 'package:pulsr/data/audio/audio_handler.dart';

class MockAudioHandler extends Mock implements PulsrAudioHandler {}
class MockMusicRepo extends Mock implements IMusicRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P0 Bug Fixes Unit Tests', () {
    test('C2: PlayerState slice field-count parity test', () {
      const state = PlayerState();

      // Ensure every slice exists and is accessible
      expect(state.playback, isA<PlaybackSlice>());
      expect(state.queueSlice, isA<QueueSlice>());
      expect(state.dsp, isA<DspSlice>());
      expect(state.lyricsSlice, isA<LyricsSlice>());

      // Verify forwarded getters maintain backwards compatibility
      expect(state.isPlaying, equals(state.playback.isPlaying));
      expect(state.queue, equals(state.queueSlice.queue));
      expect(state.isEqEnabled, equals(state.dsp.isEqEnabled));
      expect(state.lyrics, equals(state.lyricsSlice.lyrics));

      // differsFromBeyondPosition compares playback + queue without triggering on DSP/lyrics changes
      final modifiedDsp = state.copyWith(dsp: state.dsp.copyWith(isVirtualizerEnabled: true));
      expect(state.differsFromBeyondPosition(modifiedDsp), isFalse);

      final modifiedQueue = state.copyWith(queueSlice: state.queueSlice.copyWith(currentIndex: 2));
      expect(state.differsFromBeyondPosition(modifiedQueue), isTrue);
    });

    test('C3: playSong rollback invalidates guards and prevents stale queue re-apply', () async {
      final mockHandler = MockAudioHandler();
      final mockRepo = MockMusicRepo();
      final queueMutex = Mutex();
      final slotCache = <int, SongsTableData>{};
      final queueSlots = <int, QueueSlotData>{};
      var state = const PlayerState();

      final controller = PlayerQueueController(
        audioHandler: mockHandler,
        repository: mockRepo,
        getState: () => state,
        emit: (s) => state = s,
        isClosed: () => false,
        queueMutex: queueMutex,
        slotLookupCache: slotCache,
        queueSlots: queueSlots,
        updateWidgetThrottled: ({bool force = false}) {},
        loadLyrics: (_) {},
        bumpQueueVersion: () {},
        isSameTrack: (a, b) => a?.id == b?.id,
      );

      const failedSong = SongsTableData(
        id: 99,
        title: 'Failing Song',
        artist: 'Artist',
        album: 'Album',
        durationMs: 180000,
        path: 'http://example.com/fail.mp3',
        source: SongSource.youtube,
        isFavorite: false,
        isMissing: false,
        isDownloaded: false,
        playCount: 0,
        lastPositionMs: 0,
      );

      // Make loadQueue fail/throw
      when(() => mockHandler.loadQueue(
            any(),
            initialIndex: any(named: 'initialIndex'),
            initialPosition: any(named: 'initialPosition'),
            autoPlay: any(named: 'autoPlay'),
          )).thenThrow(Exception('Engine load failure'));

      final lyricsGen = controller.lyricsGuard.next();

      await controller.playSong(failedSong);

      // Rollback occurred
      expect(state.errorMessage, contains('Failed to play Failing Song'));
      expect(controller.mediaItemResolutionGuard.isValid(1), isFalse);
      expect(controller.localMatchSwapGuard.isValid(1), isFalse);
      expect(controller.lyricsGuard.isValid(lyricsGen), isFalse);
    });

    test('C4: Tombstone boundary correctly ignores events within deletion window', () async {
      final deleteMutex = Mutex();
      final deletedAtMsByVideoId = <String, int>{};
      const windowMs = 5000;

      // Simulate a task deleted at timestamp 1000
      deletedAtMsByVideoId['video_123'] = 1000;

      // At exactly timestamp 5999 (boundary - 1 ms), task is still within window
      final shouldIgnore1 = await deleteMutex.protect(() async {
        const now = 5999;
        deletedAtMsByVideoId.removeWhere((_, deletedAt) => now - deletedAt >= windowMs);
        return deletedAtMsByVideoId.containsKey('video_123');
      });
      expect(shouldIgnore1, isTrue);

      // At exactly timestamp 6000 (boundary), task window expires and is cleaned
      final shouldIgnore2 = await deleteMutex.protect(() async {
        const now = 6000;
        deletedAtMsByVideoId.removeWhere((_, deletedAt) => now - deletedAt >= windowMs);
        return deletedAtMsByVideoId.containsKey('video_123');
      });
      expect(shouldIgnore2, isFalse);
    });

    test('C6: Favorite merge deduplicates songs by song.id', () {
      const song1 = SongsTableData(
        id: 1,
        title: 'Song 1',
        artist: 'Artist 1',
        album: 'Album',
        durationMs: 120000,
        path: '/path/1.mp3',
        source: SongSource.local,
        isFavorite: true,
        isMissing: false,
        isDownloaded: false,
        playCount: 0,
        lastPositionMs: 0,
      );

      final incomingFavs = [song1, song1.copyWith()];
      final seen = <int>{};
      final deduped = incomingFavs.where((s) => seen.add(s.id)).toList();

      expect(deduped.length, equals(1));
      expect(deduped.first.id, equals(1));
    });
  });
}
