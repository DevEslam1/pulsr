// test/core/telemetry/playback_latency_tracker_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/telemetry/clock.dart';
import 'package:pulsr/core/telemetry/playback_latency_tracker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlaybackLatencyTracker — Task 0 instrumentation', () {
    late FakeClock clock;
    late PlaybackLatencyTracker tracker;

    setUp(() {
      clock = FakeClock(DateTime.fromMillisecondsSinceEpoch(1000000));
      tracker = PlaybackLatencyTracker.withClock(clock);
    });

    tearDown(() {
      tracker.debugReset();
      tracker.dispose();
    });

    test('span assembly: stage offsets and durations match fake-clock advances', () {
      tracker.start(videoId: 'abc123');
      // tap at t=0 automatically
      expect(tracker.activePlayId, isNotNull);
      final reportAfterTap = tracker.lastReport;
      expect(reportAfterTap, isNull, reason: 'not finished yet');

      // Simulate pipeline progression with deterministic advances
      clock.advance(const Duration(milliseconds: 5));
      tracker.markStage(PlaybackStage.resolutionRequested);
      clock.advance(const Duration(milliseconds: 3));
      tracker.markStage(PlaybackStage.pluginEntered);
      clock.advance(const Duration(milliseconds: 10));
      tracker.markStage(PlaybackStage.clientRequestSent);
      clock.advance(const Duration(milliseconds: 7));
      tracker.markStage(PlaybackStage.poTokenNeeded);
      // poToken regenerated path takes extra 40 ms
      clock.advance(const Duration(milliseconds: 40));
      tracker.markStage(PlaybackStage.poTokenRegenerated);
      clock.advance(const Duration(milliseconds: 15));
      tracker.markStage(PlaybackStage.urlObtained);
      clock.advance(const Duration(milliseconds: 8));
      tracker.markStage(PlaybackStage.sourceSet);
      clock.advance(const Duration(milliseconds: 12));
      tracker.markStage(PlaybackStage.firstBytesReady);
      clock.advance(const Duration(milliseconds: 20));
      tracker.markStage(PlaybackStage.playing);

      final report = tracker.lastReport;
      expect(report, isNotNull);
      expect(report!.videoId, equals('abc123'));
      expect(report.success, isTrue);
      // Total should be sum of all advances = 5+3+10+7+40+15+8+12+20 = 120ms
      expect(report.total.inMilliseconds, equals(120));

      // Offsets from tap
      expect(report.stageOffsets[PlaybackStage.tap]!.inMilliseconds, equals(0));
      expect(report.stageOffsets[PlaybackStage.resolutionRequested]!.inMilliseconds, equals(5));
      expect(report.stageOffsets[PlaybackStage.pluginEntered]!.inMilliseconds, equals(8));
      expect(report.stageOffsets[PlaybackStage.clientRequestSent]!.inMilliseconds, equals(18));
      expect(report.stageOffsets[PlaybackStage.poTokenNeeded]!.inMilliseconds, equals(25));
      expect(report.stageOffsets[PlaybackStage.poTokenRegenerated]!.inMilliseconds, equals(65));
      expect(report.stageOffsets[PlaybackStage.urlObtained]!.inMilliseconds, equals(80));
      expect(report.stageOffsets[PlaybackStage.sourceSet]!.inMilliseconds, equals(88));
      expect(report.stageOffsets[PlaybackStage.firstBytesReady]!.inMilliseconds, equals(100));
      expect(report.stageOffsets[PlaybackStage.playing]!.inMilliseconds, equals(120));

      // Incremental durations
      expect(report.stageDurations[PlaybackStage.resolutionRequested]!.inMilliseconds, equals(5));
      expect(report.stageDurations[PlaybackStage.pluginEntered]!.inMilliseconds, equals(3));
      expect(report.stageDurations[PlaybackStage.poTokenRegenerated]!.inMilliseconds, equals(40));
      expect(report.stageDurations[PlaybackStage.playing]!.inMilliseconds, equals(20));

      // Every play produces full breakdown: ensure all stages present in report
      expect(report.stageOffsets.length, equals(10));
    });

    test('bucket math: preResolved <300ms, warm <1s, cold <3s, overBudget >=3s', () {
      expect(PlaybackLatencyTracker.bucketFor(const Duration(milliseconds: 120)),
          equals(PlaybackLatencyBucket.preResolved));
      expect(PlaybackLatencyTracker.bucketFor(const Duration(milliseconds: 250)),
          equals(PlaybackLatencyBucket.preResolved));
      expect(PlaybackLatencyTracker.bucketFor(const Duration(milliseconds: 299)),
          equals(PlaybackLatencyBucket.preResolved));
      expect(PlaybackLatencyTracker.bucketFor(const Duration(milliseconds: 300)),
          equals(PlaybackLatencyBucket.warm));
      expect(PlaybackLatencyTracker.bucketFor(const Duration(milliseconds: 800)),
          equals(PlaybackLatencyBucket.warm));
      expect(PlaybackLatencyTracker.bucketFor(const Duration(milliseconds: 999)),
          equals(PlaybackLatencyBucket.warm));
      expect(PlaybackLatencyTracker.bucketFor(const Duration(milliseconds: 1000)),
          equals(PlaybackLatencyBucket.cold));
      expect(PlaybackLatencyTracker.bucketFor(const Duration(milliseconds: 2500)),
          equals(PlaybackLatencyBucket.cold));
      expect(PlaybackLatencyTracker.bucketFor(const Duration(milliseconds: 2999)),
          equals(PlaybackLatencyBucket.cold));
      expect(PlaybackLatencyTracker.bucketFor(const Duration(milliseconds: 3000)),
          equals(PlaybackLatencyBucket.overBudget));
      expect(PlaybackLatencyTracker.bucketFor(const Duration(milliseconds: 5000)),
          equals(PlaybackLatencyBucket.overBudget));
    });

    test('meetsBudgetForScenario helper respects per-scenario budgets', () {
      expect(
          PlaybackLatencyTracker.meetsBudgetForScenario(
              total: const Duration(milliseconds: 200),
              scenario: PlaybackLatencyBucket.preResolved),
          isTrue);
      expect(
          PlaybackLatencyTracker.meetsBudgetForScenario(
              total: const Duration(milliseconds: 350),
              scenario: PlaybackLatencyBucket.preResolved),
          isFalse);
      expect(
          PlaybackLatencyTracker.meetsBudgetForScenario(
              total: const Duration(milliseconds: 900),
              scenario: PlaybackLatencyBucket.warm),
          isTrue);
      expect(
          PlaybackLatencyTracker.meetsBudgetForScenario(
              total: const Duration(milliseconds: 1100),
              scenario: PlaybackLatencyBucket.warm),
          isFalse);
      expect(
          PlaybackLatencyTracker.meetsBudgetForScenario(
              total: const Duration(milliseconds: 2500),
              scenario: PlaybackLatencyBucket.cold),
          isTrue);
      expect(
          PlaybackLatencyTracker.meetsBudgetForScenario(
              total: const Duration(milliseconds: 3100),
              scenario: PlaybackLatencyBucket.cold),
          isFalse);
    });

    test('missing stages still produce report; superseded play is marked failure', () {
      tracker.start(videoId: 'vid1');
      clock.advance(const Duration(milliseconds: 50));
      tracker.markStage(PlaybackStage.resolutionRequested);
      // Start new play before finishing old one — old should be force-finished as failure
      tracker.start(videoId: 'vid2');
      // First history entry should be failure for vid1
      expect(tracker.history.length, equals(1));
      expect(tracker.history.first.videoId, equals('vid1'));
      expect(tracker.history.first.success, isFalse);
      expect(tracker.history.first.failureStage, equals('superseded'));

      // Advance second play to success
      clock.advance(const Duration(milliseconds: 100));
      tracker.markStage(PlaybackStage.urlObtained);
      clock.advance(const Duration(milliseconds: 50));
      tracker.markStage(PlaybackStage.playing);
      expect(tracker.history.length, equals(2));
      expect(tracker.history.last.videoId, equals('vid2'));
      expect(tracker.history.last.success, isTrue);
      expect(tracker.history.last.total.inMilliseconds, equals(150));
    });

    test('idempotent markStage: duplicate marks keep earliest timestamp', () {
      tracker.start(videoId: 'dupTest');
      clock.advance(const Duration(milliseconds: 10));
      tracker.markStage(PlaybackStage.resolutionRequested);
      final firstOffset = tracker.activePlayId != null
          ? clock.now().difference(DateTime.fromMillisecondsSinceEpoch(1000000))
          : Duration.zero;
      expect(firstOffset.inMilliseconds, equals(10));
      // Try to mark same stage again after more time — should not overwrite
      clock.advance(const Duration(milliseconds: 20));
      tracker.markStage(PlaybackStage.resolutionRequested);
      tracker.markStage(PlaybackStage.playing);
      final report = tracker.lastReport!;
      expect(report.stageOffsets[PlaybackStage.resolutionRequested]!.inMilliseconds, equals(10));
      expect(report.total.inMilliseconds, equals(30)); // 10 +20, duplicate ignored
    });

    test('finishWithError produces failure report with stage', () {
      tracker.start(videoId: 'errVid');
      clock.advance(const Duration(milliseconds: 30));
      tracker.markStage(PlaybackStage.pluginEntered);
      tracker.finishWithError(Exception('network'), stage: PlaybackStage.clientRequestSent);
      final report = tracker.lastReport!;
      expect(report.success, isFalse);
      expect(report.failureStage, equals(PlaybackStage.clientRequestSent.name));
      expect(report.total.inMilliseconds, equals(30));
    });

    test('debug summary contains breakdown for every stage', () {
      tracker.start(videoId: 'summaryVid');
      clock.advance(const Duration(milliseconds: 10));
      tracker.markStage(PlaybackStage.resolutionRequested);
      clock.advance(const Duration(milliseconds: 10));
      tracker.markStage(PlaybackStage.urlObtained);
      clock.advance(const Duration(milliseconds: 10));
      tracker.markStage(PlaybackStage.playing);
      final report = tracker.lastReport!;
      // toJson should contain breakdown
      final json = report.toJson();
      expect(json['stageOffsetsMs'], containsPair(PlaybackStage.tap.name, 0));
      expect(json['stageOffsetsMs'], containsPair(PlaybackStage.resolutionRequested.name, 10));
      expect(json['totalMs'], equals(30));
    });
  });

  group('PlaybackLatencyTracker — TTFA tags & native timing relay', () {
    late FakeClock clock;
    late PlaybackLatencyTracker tracker;

    setUp(() {
      clock = FakeClock(DateTime.fromMillisecondsSinceEpoch(1000000));
      tracker = PlaybackLatencyTracker.withClock(clock);
    });

    tearDown(() {
      tracker.debugReset();
      tracker.dispose();
    });

    test('setTag records classification tags on the active session', () {
      tracker.start(videoId: 'tagVid');
      tracker.setTag('tierUsed', 'account');
      tracker.setTag('cacheHit', 'false');
      expect(tracker.activeTags?['tierUsed'], equals('account'));
      expect(tracker.activeTags?['cacheHit'], equals('false'));

      // Marks after finish must not resurrect the session.
      tracker.markStage(PlaybackStage.playing);
      tracker.setTag('tierUsed', 'native');
      expect(tracker.activeTags, isNull);
      expect(tracker.lastReport!.success, isTrue);
    });

    test('markNativeTiming classifies poTokenWasCold from the mint relay', () {
      tracker.start(videoId: 'mintVid');
      tracker.markNativeTiming('poToken.mint', 137, attrs: {'cold': true});
      expect(tracker.activeTags?['poTokenWasCold'], equals('true'));

      tracker.markNativeTiming('ladder.client_attempt', 42,
          attrs: {'client': 'ANDROID_VR'});
      expect(tracker.activeTags?['poTokenWasCold'], equals('true'),
          reason: 'unrelated relays must not clobber the tag');

      tracker.markNativeTiming('rate_limiter.wait_player', 15);
      expect(tracker.activeTags?['poTokenWasCold'], equals('true'),
          reason: 'relays without attrs must be no-ops for tags');
    });

    test('markNativeTiming is a no-op without an active session', () {
      expect(tracker.activeTags, isNull);
      tracker.markNativeTiming('executor.queue_wait', 3);
      expect(tracker.activeTags, isNull);
      expect(tracker.lastReport, isNull);
    });
  });
}
