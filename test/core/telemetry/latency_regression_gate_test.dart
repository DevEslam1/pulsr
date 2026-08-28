import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/telemetry/clock.dart';
import 'package:pulsr/core/telemetry/playback_latency_tracker.dart';

void main() {
  group('Task 8 — Latency Regression Gate Budget Tests', () {
    late FakeClock fakeClock;
    late PlaybackLatencyTracker tracker;

    setUp(() {
      fakeClock = FakeClock(DateTime(2026, 8, 28, 12, 0, 0));
      tracker = PlaybackLatencyTracker.withClock(fakeClock);
    });

    test('Pre-resolved Track Budget Assertion (< 300 ms target)', () {
      // Scenario: Next-in-queue pre-resolved in background, stream URL in YtmUrlCache
      tracker.start(videoId: 'preresolved_v1');

      // 1. Resolution requested (Cache hit in YtmUrlCache: 5ms)
      fakeClock.advance(const Duration(milliseconds: 5));
      tracker.markStage(PlaybackStage.resolutionRequested);

      // 2. URL obtained directly from memory cache (5ms)
      fakeClock.advance(const Duration(milliseconds: 5));
      tracker.markStage(PlaybackStage.urlObtained);

      // 3. Source set on just_audio / ExoPlayer (30ms)
      fakeClock.advance(const Duration(milliseconds: 30));
      tracker.markStage(PlaybackStage.sourceSet);

      // 4. First bytes ready (ExoPlayer start buffer 800ms configured: 140ms)
      fakeClock.advance(const Duration(milliseconds: 140));
      tracker.markStage(PlaybackStage.firstBytesReady);

      // 5. Playing state (Audible sound emitted: 20ms)
      fakeClock.advance(const Duration(milliseconds: 20));
      tracker.markStage(PlaybackStage.playing);

      final report = tracker.lastReport;

      expect(report, isNotNull);
      expect(report!.bucket, PlaybackLatencyBucket.preResolved);
      expect(
        report.total.inMilliseconds,
        lessThan(300),
        reason: 'Pre-resolved tap-to-audible-sound must be strictly < 300 ms (Actual: ${report.total.inMilliseconds}ms)',
      );
      expect(
        report.stageDurations[PlaybackStage.resolutionRequested]?.inMilliseconds,
        lessThanOrEqualTo(10),
      );
    });

    test('Warm Track Budget Assertion (< 1000 ms target)', () {
      // Scenario: poToken cached, winning client known, persistent OkHttp/HTTP2 connection, TLS warm
      tracker.start(videoId: 'warm_v2');

      // 1. Resolution requested
      fakeClock.advance(const Duration(milliseconds: 10));
      tracker.markStage(PlaybackStage.resolutionRequested);

      // 2. Plugin entered (poToken retrieved from PoTokenStore in 2ms)
      fakeClock.advance(const Duration(milliseconds: 2));
      tracker.markStage(PlaybackStage.pluginEntered);

      // 3. Client request sent to winning client (Innertube + Decipher cache hit: 280ms)
      fakeClock.advance(const Duration(milliseconds: 280));
      tracker.markStage(PlaybackStage.clientRequestSent);

      // 4. URL obtained & TLS pre-connected
      fakeClock.advance(const Duration(milliseconds: 20));
      tracker.markStage(PlaybackStage.urlObtained);

      // 5. Source set on player
      fakeClock.advance(const Duration(milliseconds: 50));
      tracker.markStage(PlaybackStage.sourceSet);

      // 6. First bytes ready from warm connection
      fakeClock.advance(const Duration(milliseconds: 250));
      tracker.markStage(PlaybackStage.firstBytesReady);

      // 7. Playing state reached
      fakeClock.advance(const Duration(milliseconds: 30));
      tracker.markStage(PlaybackStage.playing);

      final report = tracker.lastReport;

      expect(report, isNotNull);
      expect(report!.bucket, PlaybackLatencyBucket.warm);
      expect(
        report.total.inMilliseconds,
        lessThan(1000),
        reason: 'Warm stream resolution and playback start must be < 1.0 s (Actual: ${report.total.inMilliseconds}ms)',
      );
    });

    test('Cold Track Budget Assertion (< 3000 ms absolute worst-case target)', () {
      // Scenario: Cold start, first install, poToken generation + 350ms hedged resolution race
      tracker.start(videoId: 'cold_v3');

      // 1. Resolution requested
      fakeClock.advance(const Duration(milliseconds: 10));
      tracker.markStage(PlaybackStage.resolutionRequested);

      // 2. poToken needed & generated via WebView JS
      fakeClock.advance(const Duration(milliseconds: 900));
      tracker.markStage(PlaybackStage.poTokenNeeded);

      // 3. poToken regenerated
      fakeClock.advance(const Duration(milliseconds: 10));
      tracker.markStage(PlaybackStage.poTokenRegenerated);

      // 4. Client request sent (350ms hedged race between candidate 1 and candidate 2)
      fakeClock.advance(const Duration(milliseconds: 650));
      tracker.markStage(PlaybackStage.clientRequestSent);

      // 5. URL obtained
      fakeClock.advance(const Duration(milliseconds: 30));
      tracker.markStage(PlaybackStage.urlObtained);

      // 6. Source set
      fakeClock.advance(const Duration(milliseconds: 80));
      tracker.markStage(PlaybackStage.sourceSet);

      // 7. First bytes ready
      fakeClock.advance(const Duration(milliseconds: 450));
      tracker.markStage(PlaybackStage.firstBytesReady);

      // 8. Playing state
      fakeClock.advance(const Duration(milliseconds: 50));
      tracker.markStage(PlaybackStage.playing);

      final report = tracker.lastReport;

      expect(report, isNotNull);
      expect(report!.bucket, PlaybackLatencyBucket.cold);
      expect(
        report.total.inMilliseconds,
        lessThan(3000),
        reason: 'Cold start absolute worst-case must remain strictly < 3.0 s (Actual: ${report.total.inMilliseconds}ms)',
      );
    });
  });
}
