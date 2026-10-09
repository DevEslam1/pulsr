// Coverage for the uncovered branches of player_queue_warming.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mutex/mutex.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/cubit/controllers/player_controllers.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';

import '../player_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RecordingAudioHandler handler;
  late MockStreamPreResolver resolver;
  late MockMusicRepository repo;
  late bool closed;

  setUpAll(() {
    registerFallbackValue(buildSong(0));
  });

  PlayerQueueController buildController() => PlayerQueueController(
        audioHandler: handler,
        repository: repo,
        getState: () => const PlayerState(),
        emit: (_) {},
        isClosed: () => closed,
        queueMutex: Mutex(),
        slotLookupCache: <int, SongsTableData>{},
        queueSlots: <int, QueueSlotData>{},
        updateWidgetThrottled: ({bool force = false}) {},
        loadLyrics: (_) {},
        bumpQueueVersion: () {},
        isSameTrack: (a, b) => a?.id == b?.id,
      );

  setUp(() {
    handler = RecordingAudioHandler();
    resolver = MockStreamPreResolver();
    repo = MockMusicRepository();
    closed = false;
    handler.preResolver = resolver;
  });

  group('warmStream', () {
    test('forwards the song to the pre-resolver', () {
      final song = buildSong(1, source: SongSource.youtube, remoteId: 'v1');
      buildController().warmStream(song);
      verify(() => resolver.onTrackEnqueuedOrTapped(song)).called(1);
    });

    test('swallows resolver failures', () {
      when(() => resolver.onTrackEnqueuedOrTapped(any())).thenThrow(
        Exception('resolver down'),
      );
      final song = buildSong(1, source: SongSource.youtube, remoteId: 'v1');
      expect(() => buildController().warmStream(song), returnsNormally);
    });
  });

  group('warmStreams', () {
    test('does nothing for an empty list', () async {
      buildController().warmStreams(const []);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      verifyNever(() => resolver.onTrackEnqueuedOrTapped(any()));
    });

    test('does nothing when count is non-positive', () async {
      buildController().warmStreams([buildSong(1, remoteId: 'v1')], count: 0);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      verifyNever(() => resolver.onTrackEnqueuedOrTapped(any()));
    });

    test('skips local, downloaded and remote-id-less tracks', () async {
      final local = buildSong(1);
      final downloaded =
          buildSong(2, source: SongSource.youtube, remoteId: 'v2', isDownloaded: true);
      final noRemote = buildSong(3, source: SongSource.youtube);
      buildController().warmStreams([local, downloaded, noRemote]);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      verifyNever(() => resolver.onTrackEnqueuedOrTapped(any()));
    });

    test('warms the first N streaming-eligible tracks with a stagger',
        () async {
      final songs = [
        buildSong(1, source: SongSource.youtube, remoteId: 'v1'),
        buildSong(2, source: SongSource.youtube, remoteId: 'v2'),
        buildSong(3, source: SongSource.youtube, remoteId: 'v3'),
        buildSong(4, source: SongSource.youtube, remoteId: 'v4'),
      ];
      buildController().warmStreams(songs, count: 2);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      verify(() => resolver.onTrackEnqueuedOrTapped(songs[0])).called(1);
      verifyNever(() => resolver.onTrackEnqueuedOrTapped(songs[1]));
      await Future<void>.delayed(const Duration(milliseconds: 500));
      verify(() => resolver.onTrackEnqueuedOrTapped(songs[1])).called(1);
      verifyNever(() => resolver.onTrackEnqueuedOrTapped(songs[2]));
    });

    test('short-circuits when the controller closes before the stagger fires',
        () async {
      closed = true;
      final song = buildSong(1, source: SongSource.youtube, remoteId: 'v1');
      buildController().warmStreams([song], count: 1);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      verifyNever(() => resolver.onTrackEnqueuedOrTapped(any()));
    });

    test('swallows resolver failures during a staggered warm', () async {
      when(() => resolver.onTrackEnqueuedOrTapped(any())).thenThrow(
        Exception('resolver down'),
      );
      final song = buildSong(1, source: SongSource.youtube, remoteId: 'v1');
      expect(
        () => buildController().warmStreams([song], count: 1),
        returnsNormally,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
  });
}
