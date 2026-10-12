// test/data/audio/automix/automix_transition_engine_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/automix/automix_transition_planner.dart';
import 'package:pulsr/data/audio/automix/bpm_detector.dart';
import 'package:pulsr/data/audio/automix/track_analysis.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('TrackAnalysis & BpmDetector Tests', () {
    test('TrackAnalysis serializes and deserializes correctly', () {
      final analysis = TrackAnalysis(
        trackId: 'track_123',
        bpm: 124.0,
        beatConfidence: 0.92,
        key: '8A',
        keyConfidence: 0.85,
        energyLevel: 0.8,
        mixInCueMs: 3500,
        mixOutCueMs: 180000,
        firstBeat: 0.25,
        downbeats: [0.25, 2.18, 4.12],
        phraseBoundaries: [0.25, 7.99],
        vocalMask: [0.1, 0.2, 0.8],
      );

      final json = analysis.toJson();
      final restored = TrackAnalysis.fromJson(json);

      expect(restored.trackId, 'track_123');
      expect(restored.bpm, 124.0);
      expect(restored.beatConfidence, 0.92);
      expect(restored.key, '8A');
      expect(restored.mixInCueMs, 3500);
      expect(restored.mixOutCueMs, 180000);
      expect(restored.vocalMask, [0.1, 0.2, 0.8]);
      expect(restored.isUsable, isTrue);
    });

    test('BpmDetector calculateBeatGrid generates musical grid and cues', () {
      final analysis = BpmDetector.calculateBeatGrid(
        trackId: 'test_song',
        bpm: 120.0,
        durationSeconds: 240.0,
        key: 'Am',
      );

      expect(analysis.bpm, 120.0);
      expect(analysis.beatInterval, 0.5); // 60 / 120 = 0.5s
      expect(analysis.downbeats, isNotEmpty);
      expect(analysis.phraseBoundaries, isNotEmpty);
      expect(analysis.mixInCueMs, greaterThan(0));
      expect(analysis.mixOutCueMs, greaterThan(0));
      expect(analysis.mixInCandidates, isNotEmpty);
      expect(analysis.mixOutCandidates, isNotEmpty);
    });

    test('BpmDetector caches and retrieves TrackAnalysis', () async {
      final detector = BpmDetector();
      await detector.ready;

      final analysis = TrackAnalysis(
        trackId: 'cached_song_1',
        bpm: 128.0,
        beatConfidence: 0.88,
        duration: 210.0,
      );

      await detector.cacheAnalysis('cached_song_1', analysis);
      final retrieved = detector.getCachedAnalysis('cached_song_1');

      expect(retrieved, isNotNull);
      expect(retrieved!.bpm, 128.0);
      expect(retrieved.beatConfidence, 0.88);
    });
  });

  group('AutomixTransitionPlanner Tests', () {
    test('alignTempoOctave folds octaves accurately', () {
      // 63 BPM folded into 126 BPM octave
      final aligned = AutomixTransitionPlanner.alignTempoOctave(126.0, 63.0);
      expect(aligned, 126.0);

      // 175 BPM folded towards 90 BPM
      final halfAligned = AutomixTransitionPlanner.alignTempoOctave(90.0, 180.0);
      expect(halfAligned, 90.0);
    });

    test('speedUpBetween calculates speed-up factor', () {
      // 120 BPM and 126 BPM -> 126 / 120 = 1.05
      final speedUp = AutomixTransitionPlanner.speedUpBetween(120.0, 126.0);
      expect(speedUp, closeTo(1.05, 0.01));
    });

    test('assessTransitionTier chooses beatmatched tier for close tempi and high confidence', () {
      final trackA = TrackAnalysis(
        trackId: 'a',
        bpm: 124.0,
        beatConfidence: 0.9,
        duration: 200.0,
      );
      final trackB = TrackAnalysis(
        trackId: 'b',
        bpm: 126.0,
        beatConfidence: 0.88,
        duration: 220.0,
      );

      final verdict = AutomixTransitionPlanner.assessTransitionTier(
        outgoing: trackA,
        incoming: trackB,
        advancedAutomix: true,
      );

      expect(verdict.tier, TransitionTier.beatmatched);
      expect(verdict.reasons, isEmpty);
    });

    test('assessTransitionTier chooses djFilter for distant tempi', () {
      final trackA = TrackAnalysis(
        trackId: 'a',
        bpm: 85.0,
        beatConfidence: 0.8,
        duration: 200.0,
      );
      final trackB = TrackAnalysis(
        trackId: 'b',
        bpm: 130.0,
        beatConfidence: 0.8,
        duration: 220.0,
      );

      final verdict = AutomixTransitionPlanner.assessTransitionTier(
        outgoing: trackA,
        incoming: trackB,
        advancedAutomix: true,
      );

      expect(verdict.tier, TransitionTier.djFilter);
      expect(verdict.reasons, contains('tempo-distance'));
    });

    test('assessTransitionTier degrades to plainCrossfade if confidence is very low', () {
      final trackA = TrackAnalysis(
        trackId: 'a',
        bpm: 120.0,
        beatConfidence: 0.1,
        duration: 200.0,
      );
      final trackB = TrackAnalysis(
        trackId: 'b',
        bpm: 120.0,
        beatConfidence: 0.1,
        duration: 220.0,
      );

      final verdict = AutomixTransitionPlanner.assessTransitionTier(
        outgoing: trackA,
        incoming: trackB,
      );

      expect(verdict.tier, TransitionTier.plainCrossfade);
    });

    test('planTransition produces tempo-stretched beatmatched plan', () {
      final trackA = TrackAnalysis(
        trackId: 'out',
        bpm: 128.0,
        beatConfidence: 0.95,
        duration: 240.0,
        downbeats: [0.0, 1.875, 3.75, 230.0, 231.875, 233.75],
        outroStartTime: 232.0,
      );
      // Incoming is 124 BPM (slower by ~3.2%), so it should be sped up to 128 BPM
      final trackB = TrackAnalysis(
        trackId: 'in',
        bpm: 124.0,
        beatConfidence: 0.90,
        duration: 210.0,
        mixInCueMs: 3800,
        introEndTime: 7.74,
      );

      final plan = AutomixTransitionPlanner.planTransition(
        outgoing: trackA,
        incoming: trackB,
        outgoingCurrentTime: 225.0,
        outgoingDuration: 240.0,
        incomingDuration: 210.0,
        advancedAutomix: true,
      );

      expect(plan.blocked, isFalse);
      expect(plan.tier, TransitionTier.beatmatched);
      expect(plan.incomingPlaybackRate, closeTo(128.0 / 124.0, 0.01));
      expect(plan.incomingCueTime, closeTo(3.8, 0.1));
      expect(plan.transitionBeats, anyOf(8, 16));
      expect(plan.bassSwap, isTrue);
      expect(plan.bassSwapFraction, greaterThan(0.5));
      expect(plan.filterSweep, 0.0);
    });

    test('planTransition sets filterSweep for djFilter transitions', () {
      final trackA = TrackAnalysis(
        trackId: 'out_slow',
        bpm: 70.0,
        beatConfidence: 0.8,
        duration: 180.0,
      );
      final mismatchedTrackB = TrackAnalysis(
        trackId: 'in_mismatch',
        bpm: 105.0,
        beatConfidence: 0.8,
        duration: 200.0,
      );

      final plan = AutomixTransitionPlanner.planTransition(
        outgoing: trackA,
        incoming: mismatchedTrackB,
        outgoingCurrentTime: 170.0,
        outgoingDuration: 180.0,
        incomingDuration: 200.0,
      );

      expect(plan.tier, TransitionTier.djFilter);
      expect(plan.filterSweep, 1.0);
      expect(plan.transitionBeats, 8);
    });
  });
}
