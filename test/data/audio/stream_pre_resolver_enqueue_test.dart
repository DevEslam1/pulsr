import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/ytm_url_cache.dart';
import 'package:pulsr/core/telemetry/clock.dart';
import 'package:pulsr/data/audio/stream_pre_resolver.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/ytm_track.dart';

void main() {
  SongsTableData makeSong(int id, String? remoteId, {String source = SongSource.youtube}) {
    return SongsTableData(
      id: id,
      remoteId: remoteId,
      title: 'Track $id',
      artist: 'Artist',
      album: 'Album',
      durationMs: 200000,
      path: 'ytmusic://$remoteId',
      source: source,
      isDownloaded: false,
      isFavorite: false,
      isMissing: false,
      playCount: 0,
      lastPositionMs: 0,
    );
  }

  group('StreamPreResolver — Speculative Tap & Enqueue Hook (P0-2)', () {
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
        qualityProvider: () => 'high',
      );
    });

    tearDown(() {
      preResolver.dispose();
    });

    test('onTrackEnqueuedOrTapped immediately pre-resolves YouTube track into URL cache', () async {
      final song = makeSong(1, 'tap_vid_1');

      expect(urlCache.contains('tap_vid_1', quality: 'high'), isFalse);
      preResolver.onTrackEnqueuedOrTapped(song);

      // Allow microtasks to complete
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(resolvedVideoIds, contains('tap_vid_1'));
      expect(urlCache.contains('tap_vid_1', quality: 'high'), isTrue);
    });

    test('onTrackEnqueuedOrTapped skips tracks already cached', () async {
      final song = makeSong(2, 'cached_vid_2');
      urlCache.put('cached_vid_2', 'https://googlevideo.com/cached.m4a', quality: 'high');

      preResolver.onTrackEnqueuedOrTapped(song);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(resolvedVideoIds, isEmpty);
    });

    test('onTrackEnqueuedOrTapped ignores local files', () async {
      final localSong = makeSong(3, 'local_id_3', source: SongSource.local);

      preResolver.onTrackEnqueuedOrTapped(localSong);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(resolvedVideoIds, isEmpty);
    });

    test('onTrackEnqueuedOrTapped does not duplicate if already in flight', () async {
      final song = makeSong(4, 'in_flight_vid_4');

      preResolver.onTrackEnqueuedOrTapped(song);
      preResolver.onTrackEnqueuedOrTapped(song);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(resolvedVideoIds.where((id) => id == 'in_flight_vid_4').length, equals(1));
    });
  });
}
