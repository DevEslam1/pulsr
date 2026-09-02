// test/stream_pre_resolver_comprehensive_test.dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/services/ytm_url_cache.dart';
import 'package:pulsr/core/telemetry/clock.dart';
import 'package:pulsr/data/audio/stream_pre_resolver.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/ytm_track.dart';

class TestClock implements Clock {
  DateTime _now = DateTime(2026, 1, 1, 12, 0, 0);

  @override
  DateTime now() => _now;

  void advance(Duration duration) {
    _now = _now.add(duration);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestClock clock;
  late YtmUrlCache urlCache;
  late StreamPreResolver preResolver;
  late int resolveCallCount;
  late List<String> resolvedVideoIds;
  Completer<YtmStream>? pendingResolve;

  SongsTableData createSong({
    required int id,
    required String title,
    String? remoteId,
    String source = SongSource.youtube,
  }) {
    return SongsTableData(
      id: id,
      title: title,
      artist: 'Test Artist',
      album: 'Test Album',
      durationMs: 180000,
      path: remoteId != null ? 'ytmusic://$remoteId' : '/storage/local_$id.mp3',
      source: source,
      remoteId: remoteId,
      isFavorite: false,
      playCount: 0,
      isMissing: false,
      isDownloaded: false,
      lastPositionMs: 0,
    );
  }

  setUp(() {
    clock = TestClock();
    urlCache = YtmUrlCache.withClock(clock);
    resolveCallCount = 0;
    resolvedVideoIds = [];
    pendingResolve = null;

    preResolver = StreamPreResolver(
      urlCache: urlCache,
      debounceDuration: const Duration(milliseconds: 50),
      resolveUrl: (videoId, {quality = 'high'}) {
        resolveCallCount++;
        resolvedVideoIds.add(videoId);
        if (pendingResolve != null) {
          return pendingResolve!.future;
        }
        return Future.value(YtmStream(
          videoId: videoId,
          url: 'https://googlevideo.com/videoplayback?id=$videoId&expire=1767272400',
          mimeType: 'audio/webm',
          container: 'webm',
          bitrateKbps: 160,
          duration: const Duration(seconds: 180),
          title: 'Track $videoId',
          artist: 'Artist $videoId',
        ));
      },
    );
  });

  tearDown(() {
    preResolver.dispose();
  });

  group('StreamPreResolver Comprehensive Conditions', () {
    test('Condition 1: Pre-resolves sequential next track in queue upon track start', () async {
      final queue = [
        createSong(id: 1, title: 'Song 1', remoteId: 'vid_1'),
        createSong(id: 2, title: 'Song 2', remoteId: 'vid_2'),
        createSong(id: 3, title: 'Song 3', remoteId: 'vid_3'),
      ];

      preResolver.onTrackStarted(
        queue: queue,
        currentIndex: 0,
        isShuffle: false,
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(resolveCallCount, 1);
      expect(resolvedVideoIds, ['vid_2']);
      expect(urlCache.contains('vid_2'), isTrue);
    });

    test('Condition 2: Shuffle-aware pre-resolution targets upcoming track per shuffleIndices', () async {
      final queue = [
        createSong(id: 1, title: 'Song 1', remoteId: 'vid_1'),
        createSong(id: 2, title: 'Song 2', remoteId: 'vid_2'),
        createSong(id: 3, title: 'Song 3', remoteId: 'vid_3'),
        createSong(id: 4, title: 'Song 4', remoteId: 'vid_4'),
      ];

      // Shuffle permutation: Song 3 -> Song 1 -> Song 4 -> Song 2
      final shuffleIndices = [2, 0, 3, 1];

      // Currently playing Song 1 (original index 0, position 1 in shuffle order)
      preResolver.onTrackStarted(
        queue: queue,
        currentIndex: 0,
        isShuffle: true,
        shuffleIndices: shuffleIndices,
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Next in shuffle after index 0 is index 3 (Song 4 => 'vid_4')
      expect(resolveCallCount, 1);
      expect(resolvedVideoIds, ['vid_4']);
      expect(urlCache.contains('vid_4'), isTrue);
    });

    test('Condition 3: Queue loop-around (pre-resolves head of queue when at last track)', () async {
      final queue = [
        createSong(id: 1, title: 'Song 1', remoteId: 'vid_1'),
        createSong(id: 2, title: 'Song 2', remoteId: 'vid_2'),
      ];

      preResolver.onTrackStarted(
        queue: queue,
        currentIndex: 1, // Last track
        isShuffle: false,
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(resolveCallCount, 1);
      expect(resolvedVideoIds, ['vid_1']);
      expect(urlCache.contains('vid_1'), isTrue);
    });

    test('Condition 4: Skips pre-resolution when next track is local/offline (no remoteId)', () async {
      final queue = [
        createSong(id: 1, title: 'Song 1', remoteId: 'vid_1'),
        createSong(id: 2, title: 'Local Song', remoteId: null, source: SongSource.local),
      ];

      preResolver.onTrackStarted(
        queue: queue,
        currentIndex: 0,
        isShuffle: false,
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(resolveCallCount, 0);
      expect(resolvedVideoIds.isEmpty, isTrue);
    });

    test('Condition 5: Idempotency — skips network call if next track is already cached and unexpired', () async {
      urlCache.put(
        'vid_2',
        'https://googlevideo.com/videoplayback?id=vid_2',
        explicitExpiry: clock.now().add(const Duration(hours: 2)),
      );

      final queue = [
        createSong(id: 1, title: 'Song 1', remoteId: 'vid_1'),
        createSong(id: 2, title: 'Song 2', remoteId: 'vid_2'),
      ];

      preResolver.onTrackStarted(
        queue: queue,
        currentIndex: 0,
        isShuffle: false,
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(resolveCallCount, 0); // Reused cached stream without network request
    });

    test('Condition 6: Queue mutation debounces and adapts to new upcoming track', () async {
      final queue = [
        createSong(id: 1, title: 'Song 1', remoteId: 'vid_1'),
        createSong(id: 2, title: 'Song 2', remoteId: 'vid_2'),
      ];

      // Initial queue mutation
      preResolver.onQueueMutated(
        queue: queue,
        currentIndex: 0,
        isShuffle: false,
      );

      // Rapidly insert Song 3 as the new next track before debounce timer expires
      final updatedQueue = [
        createSong(id: 1, title: 'Song 1', remoteId: 'vid_1'),
        createSong(id: 3, title: 'Song 3', remoteId: 'vid_3'),
        createSong(id: 2, title: 'Song 2', remoteId: 'vid_2'),
      ];

      preResolver.onQueueMutated(
        queue: updatedQueue,
        currentIndex: 0,
        isShuffle: false,
      );

      // Wait for debounce duration
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(resolveCallCount, 1);
      expect(resolvedVideoIds, ['vid_3']);
      expect(urlCache.contains('vid_3'), isTrue);
    });

    test('Condition 7: Network failure is handled non-fatally and recovers on next track', () async {
      final failingResolver = StreamPreResolver(
        urlCache: urlCache,
        debounceDuration: const Duration(milliseconds: 20),
        resolveUrl: (videoId, {quality = 'high'}) {
          return Future.error(Exception('Network down'));
        },
      );

      final queue = [
        createSong(id: 1, title: 'Song 1', remoteId: 'vid_1'),
        createSong(id: 2, title: 'Song 2', remoteId: 'vid_2'),
      ];

      // Does not throw
      failingResolver.onTrackStarted(
        queue: queue,
        currentIndex: 0,
        isShuffle: false,
      );

      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(urlCache.contains('vid_2'), isFalse);
      failingResolver.dispose();
    });

    test('Condition 8: Fast track skips cancel in-flight pre-resolution cleanly', () async {
      pendingResolve = Completer<YtmStream>();

      final queue = [
        createSong(id: 1, title: 'Song 1', remoteId: 'vid_1'),
        createSong(id: 2, title: 'Song 2', remoteId: 'vid_2'),
        createSong(id: 3, title: 'Song 3', remoteId: 'vid_3'),
      ];

      // Start playing Song 1 -> starts pre-resolving Song 2
      preResolver.onTrackStarted(
        queue: queue,
        currentIndex: 0,
        isShuffle: false,
      );

      expect(preResolver.inFlightVideoId, 'vid_2');

      // User immediately skips to Song 2 -> starts pre-resolving Song 3
      preResolver.onTrackStarted(
        queue: queue,
        currentIndex: 1,
        isShuffle: false,
      );

      expect(preResolver.inFlightVideoId, 'vid_3');
    });
  });
}
