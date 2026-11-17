// test/data/audio/stream_pre_resolver_budget_test.dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/ytm_url_cache.dart';
import 'package:pulsr/core/telemetry/clock.dart';
import 'package:pulsr/data/audio/stream_pre_resolver.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/ytm_track.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  SongsTableData makeSong(int id, String remoteId) {
    return SongsTableData(
      id: id,
      remoteId: remoteId,
      title: 'Track $id',
      artist: 'Artist',
      album: 'Album',
      durationMs: 200000,
      path: 'ytmusic://$remoteId',
      source: SongSource.youtube,
      isDownloaded: false,
      isFavorite: false,
      isMissing: false,
      playCount: 0,
      lastPositionMs: 0,
    );
  }

  List<SongsTableData> makeQueue(int count) => List<SongsTableData>.generate(
      count, (i) => makeSong(i + 1, 'v${i + 1}'));

  YtmStream makeStream(String videoId) => YtmStream(
        videoId: videoId,
        url: 'https://googlevideo.com/stream_$videoId.m4a',
        mimeType: 'audio/mp4',
        container: 'm4a',
        bitrateKbps: 256,
        duration: const Duration(seconds: 200),
        title: 'Track $videoId',
        artist: 'Artist',
      );

  group('StreamPreResolver — global resolution budget', () {
    late FakeClock clock;
    late YtmUrlCache urlCache;
    late Map<String, Completer<YtmStream>> gates;
    late List<String> started;
    late int maxObservedInFlight;
    late StreamPreResolver preResolver;

    void build({
      int maxConcurrent = 2,
      int maxQueued = 8,
      int window = 4,
    }) {
      preResolver = StreamPreResolver(
        resolveUrl: (videoId, {quality = 'high', title, artist}) {
          started.add(videoId);
          final inFlight = preResolver.inFlightVideoIds.length;
          if (inFlight > maxObservedInFlight) maxObservedInFlight = inFlight;
          final gate = Completer<YtmStream>();
          gates[videoId] = gate;
          return gate.future;
        },
        urlCache: urlCache,
        qualityProvider: () => 'high',
        debounceDuration: const Duration(milliseconds: 10),
        preResolveWindowSize: window,
        maxConcurrentResolutions: maxConcurrent,
        maxQueuedResolutions: maxQueued,
        clock: clock,
      );
    }

    /// Settles [videoId] successfully, then lets the queued pump run.
    Future<void> complete(String videoId) async {
      gates[videoId]!.complete(makeStream(videoId));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    /// Settles [videoId] as a failed resolve, then lets the queued pump run.
    Future<void> fail(String videoId) async {
      gates[videoId]!.completeError(StateError('bot challenge'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    setUp(() {
      clock = FakeClock(DateTime.fromMillisecondsSinceEpoch(1000000));
      urlCache = YtmUrlCache.withClock(clock);
      gates = {};
      started = [];
      maxObservedInFlight = 0;
      PreconnectedSocketPool().debugLookupOverride = (_) async {};
      PreconnectedSocketPool().clear();
    });

    tearDown(() {
      preResolver.dispose();
      PreconnectedSocketPool().debugLookupOverride = null;
      PreconnectedSocketPool().clear();
    });

    test('never exceeds maxConcurrentResolutions across every trigger',
        () async {
      build(maxConcurrent: 2);

      // Track start plans four lookahead items (v2..v5).
      preResolver.onTrackStarted(
        queue: makeQueue(5),
        currentIndex: 0,
        isShuffle: false,
      );
      expect(started, equals(['v2', 'v3']));
      expect(preResolver.inFlightVideoIds.length, 2);

      // A tap arriving with the budget exhausted must not push past the cap.
      preResolver.onTrackEnqueuedOrTapped(makeSong(9, 'v9'));
      expect(started, equals(['v2', 'v3']));
      expect(preResolver.inFlightVideoIds.length, 2);

      // Freeing one slot starts exactly one more chain, and the tap wins it.
      await complete('v2');
      expect(started, equals(['v2', 'v3', 'v9']));
      expect(preResolver.inFlightVideoIds.length, 2);

      // Draining the rest starts the remaining background requests one by one.
      await complete('v3');
      expect(started, equals(['v2', 'v3', 'v9', 'v4']));
      await complete('v9');
      expect(started, equals(['v2', 'v3', 'v9', 'v4', 'v5']));
      await complete('v4');
      await complete('v5');

      expect(maxObservedInFlight, lessThanOrEqualTo(2));
      expect(preResolver.inFlightVideoIds, isEmpty);
      expect(preResolver.inFlightVideoId, isNull);
    });

    test('a tapped track overtakes queued background work', () async {
      build(maxConcurrent: 1, window: 3);

      preResolver.onTrackStarted(
        queue: makeQueue(4),
        currentIndex: 0,
        isShuffle: false,
      );
      expect(started, equals(['v2']));

      // v3 and v4 are queued behind the running chain; the tap jumps ahead.
      preResolver.onTrackEnqueuedOrTapped(makeSong(7, 'v7'));
      expect(started, equals(['v2']));

      await complete('v2');
      expect(started, equals(['v2', 'v7']));

      await complete('v7');
      expect(started, equals(['v2', 'v7', 'v3']));
    });

    test('prioritize drops queued background work for other tracks', () async {
      build(maxConcurrent: 1, window: 3);

      preResolver.onTrackStarted(
        queue: makeQueue(4),
        currentIndex: 0,
        isShuffle: false,
      );
      expect(started, equals(['v2']));

      // The user taps v9 while v3 and v4 sit in the queue.
      preResolver.prioritize('v9');
      preResolver.onTrackEnqueuedOrTapped(makeSong(9, 'v9'));

      await complete('v2');
      expect(started, equals(['v2', 'v9']));

      await complete('v9');
      // The dropped lookahead never starts, even with the budget free again.
      expect(started, isNot(contains('v3')));
      expect(started, isNot(contains('v4')));
      expect(preResolver.inFlightVideoIds, isEmpty);
    });

    test('background warming is held back while a foreground resolve runs',
        () async {
      build(maxConcurrent: 2, window: 3);

      preResolver.prioritize('v9');
      preResolver.onTrackEnqueuedOrTapped(makeSong(9, 'v9'));
      expect(started, equals(['v9']));

      // The lookahead plan arrives while the tapped track is still resolving.
      preResolver.onTrackStarted(
        queue: [...makeQueue(3), makeSong(9, 'v9')],
        currentIndex: 0,
        isShuffle: false,
      );
      expect(started, equals(['v9']),
          reason: 'No background chain may start behind a foreground resolve');
      expect(preResolver.inFlightVideoIds, equals({'v9'}));

      await complete('v9');
      expect(started, equals(['v9', 'v2', 'v3']));
      expect(maxObservedInFlight, lessThanOrEqualTo(2));
    });

    test('requests beyond the queue bound are dropped, not parked', () async {
      build(maxConcurrent: 1, maxQueued: 1, window: 4);

      preResolver.onTrackStarted(
        queue: makeQueue(5),
        currentIndex: 0,
        isShuffle: false,
      );
      // v2 runs, v3 is queued, v4 and v5 are dropped.
      expect(started, equals(['v2']));

      await complete('v2');
      expect(started, equals(['v2', 'v3']));
      await complete('v3');

      expect(started, equals(['v2', 'v3']));
      expect(preResolver.inFlightVideoIds, isEmpty);
    });

    test('a queued request is only ever started once', () async {
      build(maxConcurrent: 1, window: 1);

      preResolver.onTrackStarted(
        queue: makeQueue(2),
        currentIndex: 0,
        isShuffle: false,
      );
      expect(started, equals(['v2']));

      preResolver.onTrackEnqueuedOrTapped(makeSong(5, 'v5'));
      preResolver.onTrackEnqueuedOrTapped(makeSong(5, 'v5'));

      await complete('v2');
      expect(started, equals(['v2', 'v5']));
      await complete('v5');

      expect(started.where((id) => id == 'v5').length, 1);
      expect(preResolver.inFlightVideoIds, isEmpty);
    });

    test('a failed resolve is skipped for 60 s everywhere, then retried',
        () async {
      build();
      final bad = makeSong(20, 'bad');

      preResolver.onTrackEnqueuedOrTapped(bad);
      expect(started, equals(['bad']));
      await fail('bad');

      // No stale in-flight entry survives the failure.
      expect(preResolver.inFlightVideoIds, isEmpty);

      // Every trigger skips the id while the cooldown holds.
      preResolver.onTrackEnqueuedOrTapped(bad);
      preResolver.onTrackStarted(
        queue: [makeSong(21, 'current'), bad],
        currentIndex: 0,
        isShuffle: false,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(started, equals(['bad']));

      // A minute later the same id is eligible again.
      clock.advance(const Duration(seconds: 61));
      preResolver.onTrackEnqueuedOrTapped(bad);
      expect(started, equals(['bad', 'bad']));
      await complete('bad');
      expect(urlCache.contains('bad', quality: 'high'), isTrue);

      // A success leaves no lingering skip behind: marking the cached entry
      // stale makes the very next tap resolve again.
      urlCache.put('bad', 'https://googlevideo.com/stale.m4a',
          explicitExpiry: clock.now().add(const Duration(minutes: 5)));
      preResolver.onTrackEnqueuedOrTapped(bad);
      expect(started, equals(['bad', 'bad', 'bad']));
      await complete('bad');
    });
  });
}
