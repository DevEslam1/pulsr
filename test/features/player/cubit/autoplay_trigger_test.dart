import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mutex/mutex.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/ytm_track.dart';
import 'package:pulsr/features/player/cubit/controllers/player_queue_controller.dart';
import 'package:pulsr/features/player/cubit/controllers/queue_slot_data.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../player_test_support.dart';

class _MockYtmService extends Mock implements YtmService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RecordingAudioHandler handler;
  late _MockYtmService ytmService;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    handler = RecordingAudioHandler();
    ytmService = _MockYtmService();
    when(() => ytmService.getRadioTracks(any(), limit: any(named: 'limit')))
        .thenAnswer((_) async => [
              const YtmTrack(
                videoId: 'rec1',
                title: 'Recommended Song',
                artist: 'Artist',
                duration: Duration(seconds: 200),
              ),
            ]);
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
      ytmService: ytmService,
    );
  }

  test('0.8 checkAndTriggerAutoplay treats local / downloaded as local queue and does not trigger', () async {
    final localTrack = buildSong(1, source: SongSource.local, path: '/local/song.mp3', isDownloaded: false);
    final downloadedTrack = buildSong(2, source: SongSource.youtube, path: 'ytmusic://vid2', isDownloaded: true);

    var state = PlayerState(
      playback: PlaybackSlice(
        currentSong: localTrack,
      ),
      queueSlice: QueueSlice(
        queue: [localTrack, downloadedTrack],
        currentIndex: 1, // at end of queue
        isAutoplayEnabled: true,
      ),
    );

    final controller = createController(
      getState: () => state,
      emit: (s) => state = s,
    );

    await controller.checkAndTriggerAutoplay();

    // Must not call getRadioTracks because it is a local/downloaded queue
    verifyNever(() => ytmService.getRadioTracks(any(), limit: any(named: 'limit')));
  });

  test('0.8 checkAndTriggerAutoplay recognizes https stream, radio, and ytmusic as online queues', () async {
    // 1. https stream track
    final httpsTrack = buildSong(
      10,
      source: SongSource.youtube,
      path: 'https://stream.server.org/track.mp3',
      remoteId: 'https_remote_10',
      isDownloaded: false,
    );

    // 2. internet radio track
    final radioTrack = buildSong(
      11,
      source: SongSource.radio,
      path: 'https://icecast.radio.fm/live',
      remoteId: 'radio_remote_11',
      isDownloaded: false,
    );

    // 3. ytmusic track
    final ytTrack = buildSong(
      12,
      source: SongSource.youtube,
      path: 'ytmusic://yt_video_12',
      remoteId: 'yt_video_12',
      isDownloaded: false,
    );

    for (final track in [httpsTrack, radioTrack, ytTrack]) {
      reset(ytmService);
      when(() => ytmService.getRadioTracks(any(), limit: any(named: 'limit')))
          .thenAnswer((_) async => [
                const YtmTrack(
                  videoId: 'rec1',
                  title: 'Rec',
                  artist: 'Artist',
                  duration: Duration(seconds: 180),
                ),
              ]);

      var state = PlayerState(
        playback: PlaybackSlice(
          currentSong: track,
        ),
        queueSlice: QueueSlice(
          queue: [track],
          currentIndex: 0,
          isAutoplayEnabled: true,
        ),
      );

      final controller = createController(
        getState: () => state,
        emit: (s) => state = s,
      );

      await controller.checkAndTriggerAutoplay();

      // Should recognize as online queue (NOT local queue) and invoke recommendations
      verify(() => ytmService.getRadioTracks(track.remoteId!, limit: any(named: 'limit'))).called(1);
    }
  });
}
