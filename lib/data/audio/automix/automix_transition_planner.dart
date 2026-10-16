// lib/data/audio/automix/automix_transition_planner.dart
import 'dart:math' as math;
import 'track_analysis.dart';

/// Concrete plan for an Automix / Smart Transition between two tracks.
class TransitionPlan {
  final bool shouldStart;
  final bool markerVisible;
  final bool blocked;
  final String reason;
  final double transitionStart;
  final double transitionEnd;
  final double fadeSeconds;
  final TransitionTier tier;

  /// Playhead time (seconds) to cue the incoming track to.
  final double incomingCueTime;

  /// Target arrival time for the arrangement on incoming track.
  final double incomingHandoffTime;

  /// Playback speed rate for incoming track (1.0 to 1.10).
  final double incomingPlaybackRate;

  /// Playback speed rate for outgoing track (1.0).
  final double outgoingPlaybackRate;

  /// Duration of handoff in seconds.
  final double handoffDuration;

  /// Fade duration in musical beats (4, 8, 16).
  final int transitionBeats;

  /// Whether a bass swap EQ transition is scheduled.
  final bool bassSwap;

  /// Fraction along the transition (0.0 to 1.0) where low frequencies swap.
  final double bassSwapFraction;

  /// Cutoff depth for filter sweep (0.0 for blend, up to 1.0 for sweep).
  final double filterSweep;

  /// Normalized BPMs.
  final double outgoingBpm;
  final double incomingBpm;

  /// Seconds per beat on outgoing grid.
  final double beatSeconds;

  /// Policy reasons for decision.
  final List<String> policyReasons;

  const TransitionPlan({
    this.shouldStart = false,
    this.markerVisible = false,
    this.blocked = false,
    this.reason = '',
    this.transitionStart = 0.0,
    this.transitionEnd = 0.0,
    this.fadeSeconds = 0.0,
    this.tier = TransitionTier.plainCrossfade,
    this.incomingCueTime = 0.0,
    this.incomingHandoffTime = 0.0,
    this.incomingPlaybackRate = 1.0,
    this.outgoingPlaybackRate = 1.0,
    this.handoffDuration = 0.0,
    this.transitionBeats = 0,
    this.bassSwap = false,
    this.bassSwapFraction = 0.7,
    this.filterSweep = 0.0,
    this.outgoingBpm = 0.0,
    this.incomingBpm = 0.0,
    this.beatSeconds = 0.0,
    this.policyReasons = const [],
  });

  Duration get fadeDuration =>
      Duration(milliseconds: (fadeSeconds * 1000).round());

  Duration get incomingCueDuration =>
      Duration(milliseconds: (incomingCueTime * 1000).round());
}

/// Automix and DJ Beatmatch Transition Engine Planner.
///
/// Ports and adapts BitChord & Orchard transition policy and WSOLA phrase-switch planner:
/// - Assesses transition tier (beatmatched, djBlend, djFilter, plainCrossfade).
/// - Tempo stretches slower tracks up to 10% (speedUpBetween).
/// - Aligns fade duration to musical beats (4, 8, 16 beats).
/// - Computes mix-in cue skipping quiet intros.
/// - Computes bass swap fraction along the beat grid.
class AutomixTransitionPlanner {
  static const double minBpm = 40.0;
  static const double maxBpm = 220.0;
  static const double minBeatmatchConfidence = 0.55;
  static const double minDjConfidence = 0.20;
  static const double maxSpeedUp = 0.10; // 10% tempo stretch window
  static const double maxStretchDeviation = 0.04;
  static const double vocalActiveThreshold = 0.60;
  static const double maxDiscardedMusicSeconds = 12.0;

  static const int minFadeBeats = 4;
  static const int maxFadeBeats = 16;
  static const double maxOverlapSeconds = 16.0;
  static const double autoMinSeconds = 4.0;
  static const double autoMaxSeconds = 12.0;
  static const double defaultBassSwapFraction = 0.70;

  static const Map<String, int> keyIndex = {
    'C': 0,
    'C#': 1,
    'Db': 1,
    'D': 2,
    'D#': 3,
    'Eb': 3,
    'E': 4,
    'F': 5,
    'F#': 6,
    'Gb': 6,
    'G': 7,
    'G#': 8,
    'Ab': 8,
    'A': 9,
    'A#': 10,
    'Bb': 10,
    'B': 11,
  };

  /// Folds [incomingBpm] into octave nearest to [outgoingBpm] (e.g., 63 BPM vs 126 BPM).
  static double alignTempoOctave(double outgoingBpm, double incomingBpm) {
    if (outgoingBpm <= 0 || incomingBpm <= 0) return incomingBpm;
    var aligned = incomingBpm;
    while (aligned / outgoingBpm > 1.5) {
      aligned /= 2;
    }
    while (aligned / outgoingBpm < 0.67) {
      aligned *= 2;
    }
    return aligned;
  }

  /// Calculates the speed-up ratio required to match tempi.
  static double speedUpBetween(double outgoingBpm, double incomingBpm) {
    if (outgoingBpm <= 0 || incomingBpm <= 0) return double.infinity;
    final octaveAligned = alignTempoOctave(outgoingBpm, incomingBpm);
    final ratio = outgoingBpm / octaveAligned;
    return math.max(ratio, 1.0 / ratio);
  }

  /// Checks harmonic compatibility using Circle of Fifths.
  static bool areHarmonicallyCompatible(String keyA, String keyB) {
    if (keyA.isEmpty || keyB.isEmpty) {
      return true; // Without evidence, don't disqualify
    }
    final rootA = _extractKeyRoot(keyA);
    final rootB = _extractKeyRoot(keyB);
    final indexA = keyIndex[rootA];
    final indexB = keyIndex[rootB];
    if (indexA == null || indexB == null) return true;

    final distance =
        math.min((indexA - indexB + 12) % 12, (indexB - indexA + 12) % 12);
    final isMinorA = keyA.endsWith('m');
    final isMinorB = keyB.endsWith('m');

    if (isMinorA != isMinorB) {
      return distance <= 1;
    }
    // Fifths (distance 7 or 5) or adjacent
    return distance <= 2 || distance == 5 || distance == 7;
  }

  static String _extractKeyRoot(String key) {
    var k = key.trim();
    if (k.endsWith('m')) k = k.substring(0, k.length - 1);
    return k;
  }

  /// Assesses the transition tier for two tracks.
  static TransitionPolicyVerdict assessTransitionTier({
    required TrackAnalysis outgoing,
    required TrackAnalysis incoming,
    bool advancedAutomix = true,
  }) {
    final outBpm = outgoing.bpm;
    final inBpm = incoming.bpm;
    final outConf = outgoing.beatConfidence;
    final inConf = incoming.beatConfidence;
    final floorConf = math.min(outConf, inConf);
    final reasons = <String>[];

    if (outBpm < minBpm || outBpm > maxBpm) reasons.add('outgoing-tempo');
    if (inBpm < minBpm || inBpm > maxBpm) reasons.add('incoming-tempo');
    if (reasons.isNotEmpty) {
      return TransitionPolicyVerdict(
        tier: TransitionTier.plainCrossfade,
        reasons: reasons,
        beatConfidence: floorConf,
      );
    }

    if (outConf < minDjConfidence && inConf < minDjConfidence) {
      return TransitionPolicyVerdict(
        tier: TransitionTier.plainCrossfade,
        reasons: ['beat-confidence-too-low'],
        beatConfidence: floorConf,
      );
    }

    final speedUp = speedUpBetween(outBpm, inBpm);
    final tempoTooFar = advancedAutomix
        ? (speedUp - 1.0 > maxSpeedUp)
        : (speedUp - 1.0 > maxStretchDeviation);

    if (tempoTooFar) reasons.add('tempo-distance');
    if (outConf < minBeatmatchConfidence || inConf < minBeatmatchConfidence) {
      reasons.add('beat-confidence');
    }

    if (reasons.isEmpty) {
      return TransitionPolicyVerdict(
        tier: TransitionTier.beatmatched,
        reasons: const [],
        beatConfidence: floorConf,
      );
    }

    if (!tempoTooFar) {
      return TransitionPolicyVerdict(
        tier: TransitionTier.djBlend,
        reasons: reasons,
        beatConfidence: floorConf,
      );
    }

    return TransitionPolicyVerdict(
      tier: TransitionTier.djFilter,
      reasons: reasons,
      beatConfidence: floorConf,
    );
  }

  /// Plans a complete transition from [outgoing] to [incoming].
  static TransitionPlan planTransition({
    required TrackAnalysis outgoing,
    required TrackAnalysis incoming,
    double outgoingCurrentTime = 0.0,
    double outgoingDuration = 0.0,
    double incomingDuration = 0.0,
    Duration fallbackDuration = const Duration(seconds: 6),
    bool advancedAutomix = true,
  }) {
    final outLength = math.max(outgoingDuration, outgoing.duration);
    final inLength = math.max(incomingDuration, incoming.duration);

    if (outLength <= 0 || inLength <= 0) {
      return TransitionPlan(
        blocked: true,
        reason: 'no-duration',
        transitionEnd: outLength,
      );
    }

    final policy = assessTransitionTier(
      outgoing: outgoing,
      incoming: incoming,
      advancedAutomix: advancedAutomix,
    );

    // Fallback: Plain crossfade
    if (policy.tier == TransitionTier.plainCrossfade) {
      final fadeSec = fallbackDuration.inMilliseconds / 1000.0;
      final tStart = math.max(0.0, outLength - fadeSec);
      final shouldStart = outgoingCurrentTime >= tStart;
      return TransitionPlan(
        shouldStart: shouldStart,
        markerVisible: true,
        tier: TransitionTier.plainCrossfade,
        transitionStart: tStart,
        transitionEnd: outLength,
        fadeSeconds: outLength - tStart,
        incomingCueTime: _findAudibleStart(incoming),
        policyReasons: policy.reasons,
        reason:
            shouldStart ? 'automix-plain-crossfade' : 'before-plain-crossfade',
      );
    }

    final outBpm = outgoing.bpm;
    final alignedInBpm = alignTempoOctave(outBpm, incoming.bpm);
    final outBeatSec = outBpm > 0 ? 60.0 / outBpm : 0.5;

    // Tempo stretch calculation:
    // Speed up the slower track by up to 10% (1.0 to 1.10)
    double incomingRate = 1.0;
    if (policy.tier == TransitionTier.beatmatched) {
      if (alignedInBpm < outBpm) {
        // Incoming is slower: speed it up to match outgoing
        final ratio = outBpm / alignedInBpm;
        incomingRate = ratio.clamp(1.0, 1.0 + maxSpeedUp);
      } else {
        // Outgoing is slower or identical: keep incoming at 1.0
        incomingRate = 1.0;
      }
    }

    // Mix-in cue: skip quiet intro / lead-in on incoming track
    final incomingCue = _resolveIncomingCueTime(incoming, inLength);
    final incomingHandoff =
        _resolveIncomingHandoffTime(incoming, inLength, incomingCue);

    // Fade duration in musical beats (4, 8, 16 beats)
    final transitionBeats = _calculateTransitionBeats(
      outgoing: outgoing,
      incoming: incoming,
      tier: policy.tier,
      outBeatSec: outBeatSec,
    );

    final calculatedOverlapSec = transitionBeats * outBeatSec;
    final overlapSec =
        calculatedOverlapSec.clamp(autoMinSeconds, autoMaxSeconds);

    // Align transition start to outgoing downbeat or phrase
    final mixOutTarget = _resolveMixOutTarget(outgoing, outLength);
    final tStartTarget = math.max(0.0, mixOutTarget - overlapSec);
    final alignedStart = _alignToBeatGrid(outgoing.downbeats, tStartTarget);
    final tEnd = math.min(outLength, alignedStart + overlapSec);
    final effectiveFadeSec = tEnd - alignedStart;

    // Bass swap moment: fraction (typically 0.7 or on bar boundary)
    final bassSwapFraction = _calculateBassSwapFraction(
      outgoing: outgoing,
      incoming: incoming,
      transitionBeats: transitionBeats,
    );

    final shouldStart = outgoingCurrentTime >= alignedStart;

    return TransitionPlan(
      shouldStart: shouldStart,
      markerVisible: true,
      tier: policy.tier,
      transitionStart: alignedStart,
      transitionEnd: tEnd,
      fadeSeconds: effectiveFadeSec,
      incomingCueTime: incomingCue,
      incomingHandoffTime: incomingHandoff,
      incomingPlaybackRate: incomingRate,
      outgoingPlaybackRate: 1.0,
      handoffDuration: effectiveFadeSec,
      transitionBeats: transitionBeats,
      bassSwap: policy.tier == TransitionTier.beatmatched ||
          policy.tier == TransitionTier.djBlend,
      bassSwapFraction: bassSwapFraction,
      filterSweep: policy.tier == TransitionTier.djFilter ? 1.0 : 0.0,
      outgoingBpm: outBpm,
      incomingBpm: alignedInBpm,
      beatSeconds: outBeatSec,
      policyReasons: policy.reasons,
      reason: shouldStart
          ? 'automix-${policy.tier.name}'
          : 'before-${policy.tier.name}',
    );
  }

  static double _findAudibleStart(TrackAnalysis analysis) {
    final first = analysis.audibleStartTime ?? analysis.pickupTime;
    if (first != null && first.isFinite && first >= 0) return first;
    return (analysis.firstBeat > 0 && analysis.firstBeat.isFinite)
        ? analysis.firstBeat
        : 0.0;
  }

  static double _resolveIncomingCueTime(TrackAnalysis analysis, double length) {
    if (analysis.mixInCueMs > 0) {
      final cue = analysis.mixInCueMs / 1000.0;
      if (cue < length * 0.25) return cue;
    }
    if (analysis.mixInCandidates.isNotEmpty) {
      final best = analysis.mixInCandidates.first;
      if (best.time < length * 0.25) return best.time;
    }
    final audible = _findAudibleStart(analysis);
    return audible;
  }

  static double _resolveIncomingHandoffTime(
    TrackAnalysis analysis,
    double length,
    double cueTime,
  ) {
    final handoff = analysis.introEndTime > cueTime
        ? analysis.introEndTime
        : (cueTime + 4.0);
    return math.min(handoff, length);
  }

  static double _resolveMixOutTarget(TrackAnalysis analysis, double length) {
    if (analysis.mixOutCueMs > 0) {
      final cue = analysis.mixOutCueMs / 1000.0;
      if (cue > 0 && cue <= length) return cue;
    }
    if (analysis.outroStartTime > 0 && analysis.outroStartTime < length) {
      return analysis.outroStartTime;
    }
    return length;
  }

  static int _calculateTransitionBeats({
    required TrackAnalysis outgoing,
    required TrackAnalysis incoming,
    required TransitionTier tier,
    required double outBeatSec,
  }) {
    if (tier == TransitionTier.djFilter) {
      // Shorter, crisper handoff: 4 or 8 beats
      return 8;
    }
    // High energy into high energy or compatible phrasing gets 16 beats
    if (tier == TransitionTier.beatmatched && outBeatSec > 0) {
      final sixteenSec = 16 * outBeatSec;
      if (sixteenSec <= autoMaxSeconds) return 16;
      return 8;
    }
    return 8;
  }

  static double _alignToBeatGrid(List<double> downbeats, double target) {
    if (downbeats.isEmpty) return target;
    // Find closest downbeat at or before target across the whole list
    double? best;
    for (final db in downbeats) {
      if (db <= target) {
        if (best == null || db > best) {
          best = db;
        }
      }
    }
    return best ?? target;
  }

  static double _calculateBassSwapFraction({
    required TrackAnalysis outgoing,
    required TrackAnalysis incoming,
    required int transitionBeats,
  }) {
    if (transitionBeats <= 4) return 0.50;
    // Hand over on 3/4 of the transition or beat 6 of 8 / beat 12 of 16
    if (transitionBeats == 8) return 6.0 / 8.0; // 0.75
    if (transitionBeats == 16) return 12.0 / 16.0; // 0.75
    return defaultBassSwapFraction;
  }
}
