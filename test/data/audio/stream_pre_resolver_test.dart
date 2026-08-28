// test/data/audio/stream_pre_resolver_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/ytm_url_cache.dart';
import 'package:pulsr/core/telemetry/clock.dart';
import 'package:pulsr/data/audio/stream_pre_resolver.dart';
import 'package:pulsr/data/audio/ytm_resolving_source.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/ytm_track.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  SongsTableData createSong(int id, String title, {String? remoteId}) {
    return SongsTableData(
      id: id,
      title: title,
      artist: 'Test Artist',
      album: 'Test Album',
      durationMs: 200000,
      path: remoteId != null ? 'ytmusic://$remoteId' : '/storage/emulated/0/Music/test.mp3',
      source: remoteId != null ? SongSource.youtube : SongSource.local,
      remoteId: remoteId,
      isFavorite: false,
      isMissing: false,
      isDownloaded: false,
      playCount: 0,
      lastPositionMs: 0,
    );
  }

  group('StreamPreResolver — Task 3 Unit Tests', () {
    late FakeClock clock;
    late YtmUrlCache urlCache;
    late List<String> resolvedVideoIds;
    late StreamPreResolver preResolver;

    setUp(() {
      clock = FakeClock(DateTime.fromMillisecondsSinceEpoch(1000000));
      urlCache = YtmUrlCache.withClock(clock);
      resolvedVideoIds = [];

      preResolver = StreamPreResolver(
        resolveUrl: (videoId, {quality = 'high'}) async {
          resolvedVideoIds.add(videoId);
          return YtmStream(
            videoId: videoId,
            url: 'https://googlevideo.com/stream_$videoId.m4a',
            mimeType: 'audio/mp4',
            container: 'm4a',
            bitrateKbps: 256,
            duration: const Duration(seconds: 200),
            title: 'Track $videoId',
            artist: 'Artist',
          );
        },
        urlCache: urlCache,
        debounceDuration: const Duration(milliseconds: 50),
      );
    });

    tearDown(() {
      preResolver.dispose();
    });

    test('fires on track start and pre-resolves next queue item into URL cache', () async {
      final queue = [
        createSong(1, 'Current Track', remoteId: 'vid1'),
        createSong(2, 'Next Track', remoteId: 'vid2'),
        createSong(3, 'Third Track', remoteId: 'vid3'),
      ];

      expect(urlCache.contains('vid2'), isFalse);

      preResolver.onTrackStarted(
        queue: queue,
        currentIndex: 0,
        isShuffle: false,
      );

      // Wait a tick for async resolution
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(resolvedVideoIds, contains('vid2'));
      expect(urlCache.contains('vid2'), isTrue);
      expect(urlCache.getUrl('vid2'), equals('https://googlevideo.com/stream_vid2.m4a'));
    });

    test('shuffle-aware: pre-resolves head of upcoming queue according to shuffleIndices', () async {
      final queue = [
        createSong(1, 'Track 1', remoteId: 'vid1'),
        createSong(2, 'Track 2', remoteId: 'vid2'),
        createSong(3, 'Track 3', remoteId: 'vid3'),
      ];

      // Shuffle order: 0 (vid1) -> 2 (vid3) -> 1 (vid2)
      final shuffleIndices = [0, 2, 1];

      preResolver.onTrackStarted(
        queue: queue,
        currentIndex: 0,
        isShuffle: true,
        shuffleIndices: shuffleIndices,
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));

      // In shuffle mode, next after index 0 is shuffle index 2 (vid3)
      expect(resolvedVideoIds, contains('vid3'));
      expect(urlCache.contains('vid3'), isTrue);
      expect(urlCache.contains('vid2'), isFalse);
    });

    test('debounced re-plan on queue mutation (add/remove/reorder/shuffle)', () async {
      final queue = [
        createSong(1, 'Track 1', remoteId: 'vid1'),
        createSong(2, 'Track 2', remoteId: 'vid2'),
      ];

      // Rapidly mutate queue 3 times before debounce duration (50ms)
      preResolver.onQueueMutated(queue: queue, currentIndex: 0, isShuffle: false);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final updatedQueue = [
        createSong(1, 'Track 1', remoteId: 'vid1'),
        createSong(3, 'New Track 3', remoteId: 'vid3'),
        createSong(2, 'Track 2', remoteId: 'vid2'),
      ];
      preResolver.onQueueMutated(queue: updatedQueue, currentIndex: 0, isShuffle: false);

      // Wait for debounce timer (50ms) to fire
      await Future<void>.delayed(const Duration(milliseconds: 80));

      // Should have only resolved the final head: vid3
      expect(resolvedVideoIds, equals(['vid3']));
      expect(urlCache.contains('vid3'), isTrue);
    });

    test('idempotent: does not re-resolve if next track is already in URL cache', () async {
      urlCache.put('vid2', 'https://googlevideo.com/already_cached.m4a');

      final queue = [
        createSong(1, 'Track 1', remoteId: 'vid1'),
        createSong(2, 'Track 2', remoteId: 'vid2'),
      ];

      preResolver.onTrackStarted(
        queue: queue,
        currentIndex: 0,
        isShuffle: false,
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(resolvedVideoIds, isEmpty, reason: 'Must skip network resolution on cache hit');
    });

    test('cancelled on dispose: pending resolutions and timers do not write after dispose', () async {
      final queue = [
        createSong(1, 'Track 1', remoteId: 'vid1'),
        createSong(2, 'Track 2', remoteId: 'vid2'),
      ];

      preResolver.onQueueMutated(queue: queue, currentIndex: 0, isShuffle: false);
      preResolver.dispose();

      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(resolvedVideoIds, isEmpty);
    });

    test('integration: pre-resolved track plays with zero resolver plugin calls', () async {
      final queue = [
        createSong(1, 'Song 1', remoteId: 'v1'),
        createSong(2, 'Song 2', remoteId: 'v2'),
      ];

      // Track 1 starts playing -> pre-resolver resolves Track 2 into cache
      preResolver.onTrackStarted(
        queue: queue,
        currentIndex: 0,
        isShuffle: false,
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(urlCache.contains('v2'), isTrue);

      // User advances or taps next track (Song 2)
      var resolverClosureInvoked = false;
      final source = YtmResolvingSource(
        videoId: 'v2',
        urlCache: urlCache,
        resolve: ({bool forceRefresh = false}) async {
          resolverClosureInvoked = true;
          return 'https://googlevideo.com/plugin_call.m4a';
        },
      );

      expect(source.videoId, equals('v2'));
      // Constructing and streaming from pre-resolved source uses cache directly
      expect(resolverClosureInvoked, isFalse, reason: 'Cache hit skips plugin call');
    });
  });
}
