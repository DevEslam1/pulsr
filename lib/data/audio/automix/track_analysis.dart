// lib/data/audio/automix/track_analysis.dart

/// Single sample along an energy curve over time.
class EnergySample {
  final double time;
  final double energy;

  const EnergySample({
    required this.time,
    required this.energy,
  });

  Map<String, dynamic> toJson() => {
        'time': time,
        'energy': energy,
      };

  factory EnergySample.fromJson(Map<String, dynamic> json) => EnergySample(
        time: (json['time'] as num?)?.toDouble() ?? 0.0,
        energy: (json['energy'] as num?)?.toDouble() ?? 0.0,
      );
}

/// A candidate anchor point for a transition entry or exit.
class MixCandidate {
  final double time;
  final double score;
  final String type;

  const MixCandidate({
    required this.time,
    required this.score,
    required this.type,
  });

  Map<String, dynamic> toJson() => {
        'time': time,
        'score': score,
        'type': type,
      };

  factory MixCandidate.fromJson(Map<String, dynamic> json) => MixCandidate(
        time: (json['time'] as num?)?.toDouble() ?? 0.0,
        score: (json['score'] as num?)?.toDouble() ?? 0.0,
        type: (json['type'] as String?) ?? '',
      );
}

/// A candidate anchor point ranked by policy scoring.
class RankedMixCandidate {
  final double time;
  final double score;
  final String type;
  final double rankScore;
  final double discardedMusicSeconds;
  final bool measured;

  const RankedMixCandidate({
    required this.time,
    required this.score,
    required this.type,
    required this.rankScore,
    this.discardedMusicSeconds = 0.0,
    this.measured = true,
  });
}

/// Where a transition ends on the outgoing track and the music cost of ending there.
class MixOutAnchor {
  final double time;
  final String type;
  final double discardedMusicSeconds;

  const MixOutAnchor({
    required this.time,
    required this.type,
    this.discardedMusicSeconds = 0.0,
  });
}

/// Degradation ladder tier representing transition ambition.
enum TransitionTier {
  /// Both beat grids trusted and tempi within transparent stretch window.
  beatmatched,

  /// Beat-quantized anchors and bass swap; time-stretching locked or minimal.
  djBlend,

  /// Low-pass sweep out or filtered handoff for distant tempi or conflicting energy.
  djFilter,

  /// Flat equal-power crossfade when evidence is absent or unreliable.
  plainCrossfade,
}

/// Verdict on transition ambition with reasons.
class TransitionPolicyVerdict {
  final TransitionTier tier;
  final List<String> reasons;
  final double beatConfidence;

  const TransitionPolicyVerdict({
    required this.tier,
    required this.reasons,
    required this.beatConfidence,
  });
}

/// Stored offline analysis for one track, in that track's own timeline seconds.
///
/// Ported and adapted from BitChord / Orchard smart playback engine.
class TrackAnalysis {
  static const String statusReady = 'ready';

  final String status;
  final String trackId;
  final double duration;

  /// Beats per minute.
  final double bpm;

  /// Seconds per beat.
  final double beatInterval;

  /// Confidence in the beat grid (0.0 to 1.0).
  final double beatConfidence;

  /// Downbeat time stamps in seconds.
  final List<double> downbeats;

  /// Phrase boundaries (typically 4/8/16 bars) in seconds.
  final List<double> phraseBoundaries;

  /// Time of first detected beat in seconds.
  final double firstBeat;

  /// Musical key (e.g. "C", "Am", "F#m").
  final String key;

  /// Key confidence (0.0 to 1.0).
  final double keyConfidence;

  /// Overall energy level (0.0 to 1.0).
  final double energyLevel;

  /// Mix-in cue point in milliseconds (skips quiet intros on incoming track).
  final int mixInCueMs;

  /// Mix-out cue point in milliseconds.
  final int mixOutCueMs;

  /// Audible start time in seconds (where file starts making sound).
  final double? audibleStartTime;

  /// Pickup time in seconds.
  final double? pickupTime;

  /// Intro end time in seconds.
  final double introEndTime;

  /// Content end time in seconds (excluding trailing silence).
  final double contentEndTime;

  /// Outro start time in seconds.
  final double outroStartTime;

  /// Mix in time in seconds.
  final double mixInTime;

  /// Mix out time in seconds.
  final double mixOutTime;

  /// Candidate mix-in points.
  final List<MixCandidate> mixInCandidates;

  /// Candidate mix-out points.
  final List<MixCandidate> mixOutCandidates;

  /// Energy curve samples over time.
  final List<EnergySample> energyCurve;

  /// Low-band (bass) energy curve samples over time.
  final List<EnergySample> lowEnergyCurve;

  /// Per-sample vocal activity mask (0.0 to 1.0).
  final List<double> vocalMask;

  /// Whole-track vocal probability (0.0 to 1.0).
  final double vocalProbability;

  const TrackAnalysis({
    this.status = statusReady,
    this.trackId = '',
    this.duration = 0.0,
    this.bpm = 0.0,
    this.beatInterval = 0.0,
    this.beatConfidence = 0.0,
    this.downbeats = const [],
    this.phraseBoundaries = const [],
    this.firstBeat = 0.0,
    this.key = '',
    this.keyConfidence = 0.0,
    this.energyLevel = 0.5,
    this.mixInCueMs = 0,
    this.mixOutCueMs = 0,
    this.audibleStartTime,
    this.pickupTime,
    this.introEndTime = 0.0,
    this.contentEndTime = 0.0,
    this.outroStartTime = 0.0,
    this.mixInTime = 0.0,
    this.mixOutTime = 0.0,
    this.mixInCandidates = const [],
    this.mixOutCandidates = const [],
    this.energyCurve = const [],
    this.lowEnergyCurve = const [],
    this.vocalMask = const [],
    this.vocalProbability = 0.0,
  });

  bool get isUsable => status == statusReady && bpm > 0;

  Map<String, dynamic> toJson() => {
        'status': status,
        'trackId': trackId,
        'duration': duration,
        'bpm': bpm,
        'beatInterval': beatInterval,
        'beatConfidence': beatConfidence,
        'downbeats': downbeats,
        'phraseBoundaries': phraseBoundaries,
        'firstBeat': firstBeat,
        'key': key,
        'keyConfidence': keyConfidence,
        'energyLevel': energyLevel,
        'mixInCueMs': mixInCueMs,
        'mixOutCueMs': mixOutCueMs,
        'audibleStartTime': audibleStartTime,
        'pickupTime': pickupTime,
        'introEndTime': introEndTime,
        'contentEndTime': contentEndTime,
        'outroStartTime': outroStartTime,
        'mixInTime': mixInTime,
        'mixOutTime': mixOutTime,
        'mixInCandidates': mixInCandidates.map((c) => c.toJson()).toList(),
        'mixOutCandidates': mixOutCandidates.map((c) => c.toJson()).toList(),
        'energyCurve': energyCurve.map((e) => e.toJson()).toList(),
        'lowEnergyCurve': lowEnergyCurve.map((e) => e.toJson()).toList(),
        'vocalMask': vocalMask,
        'vocalProbability': vocalProbability,
      };

  factory TrackAnalysis.fromJson(Map<String, dynamic> json) {
    final downbeats = (json['downbeats'] as List<dynamic>?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        const [];
    final phraseBoundaries = (json['phraseBoundaries'] as List<dynamic>?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        const [];
    final mixInCandidates = (json['mixInCandidates'] as List<dynamic>?)
            ?.map((e) => MixCandidate.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [];
    final mixOutCandidates = (json['mixOutCandidates'] as List<dynamic>?)
            ?.map((e) => MixCandidate.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [];
    final energyCurve = (json['energyCurve'] as List<dynamic>?)
            ?.map((e) => EnergySample.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [];
    final lowEnergyCurve = (json['lowEnergyCurve'] as List<dynamic>?)
            ?.map((e) => EnergySample.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [];
    final vocalMask = (json['vocalMask'] as List<dynamic>?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        const [];

    return TrackAnalysis(
      status: (json['status'] as String?) ?? statusReady,
      trackId: (json['trackId'] as String?) ?? '',
      duration: (json['duration'] as num?)?.toDouble() ?? 0.0,
      bpm: (json['bpm'] as num?)?.toDouble() ?? 0.0,
      beatInterval: (json['beatInterval'] as num?)?.toDouble() ?? 0.0,
      beatConfidence: (json['beatConfidence'] as num?)?.toDouble() ?? 0.0,
      downbeats: downbeats,
      phraseBoundaries: phraseBoundaries,
      firstBeat: (json['firstBeat'] as num?)?.toDouble() ?? 0.0,
      key: (json['key'] as String?) ?? '',
      keyConfidence: (json['keyConfidence'] as num?)?.toDouble() ?? 0.0,
      energyLevel: (json['energyLevel'] as num?)?.toDouble() ?? 0.5,
      mixInCueMs: (json['mixInCueMs'] as num?)?.toInt() ?? 0,
      mixOutCueMs: (json['mixOutCueMs'] as num?)?.toInt() ?? 0,
      audibleStartTime: (json['audibleStartTime'] as num?)?.toDouble(),
      pickupTime: (json['pickupTime'] as num?)?.toDouble(),
      introEndTime: (json['introEndTime'] as num?)?.toDouble() ?? 0.0,
      contentEndTime: (json['contentEndTime'] as num?)?.toDouble() ?? 0.0,
      outroStartTime: (json['outroStartTime'] as num?)?.toDouble() ?? 0.0,
      mixInTime: (json['mixInTime'] as num?)?.toDouble() ?? 0.0,
      mixOutTime: (json['mixOutTime'] as num?)?.toDouble() ?? 0.0,
      mixInCandidates: mixInCandidates,
      mixOutCandidates: mixOutCandidates,
      energyCurve: energyCurve,
      lowEnergyCurve: lowEnergyCurve,
      vocalMask: vocalMask,
      vocalProbability: (json['vocalProbability'] as num?)?.toDouble() ?? 0.0,
    );
  }

  TrackAnalysis copyWith({
    String? status,
    String? trackId,
    double? duration,
    double? bpm,
    double? beatInterval,
    double? beatConfidence,
    List<double>? downbeats,
    List<double>? phraseBoundaries,
    double? firstBeat,
    String? key,
    double? keyConfidence,
    double? energyLevel,
    int? mixInCueMs,
    int? mixOutCueMs,
    double? audibleStartTime,
    double? pickupTime,
    double? introEndTime,
    double? contentEndTime,
    double? outroStartTime,
    double? mixInTime,
    double? mixOutTime,
    List<MixCandidate>? mixInCandidates,
    List<MixCandidate>? mixOutCandidates,
    List<EnergySample>? energyCurve,
    List<EnergySample>? lowEnergyCurve,
    List<double>? vocalMask,
    double? vocalProbability,
  }) {
    return TrackAnalysis(
      status: status ?? this.status,
      trackId: trackId ?? this.trackId,
      duration: duration ?? this.duration,
      bpm: bpm ?? this.bpm,
      beatInterval: beatInterval ?? this.beatInterval,
      beatConfidence: beatConfidence ?? this.beatConfidence,
      downbeats: downbeats ?? this.downbeats,
      phraseBoundaries: phraseBoundaries ?? this.phraseBoundaries,
      firstBeat: firstBeat ?? this.firstBeat,
      key: key ?? this.key,
      keyConfidence: keyConfidence ?? this.keyConfidence,
      energyLevel: energyLevel ?? this.energyLevel,
      mixInCueMs: mixInCueMs ?? this.mixInCueMs,
      mixOutCueMs: mixOutCueMs ?? this.mixOutCueMs,
      audibleStartTime: audibleStartTime ?? this.audibleStartTime,
      pickupTime: pickupTime ?? this.pickupTime,
      introEndTime: introEndTime ?? this.introEndTime,
      contentEndTime: contentEndTime ?? this.contentEndTime,
      outroStartTime: outroStartTime ?? this.outroStartTime,
      mixInTime: mixInTime ?? this.mixInTime,
      mixOutTime: mixOutTime ?? this.mixOutTime,
      mixInCandidates: mixInCandidates ?? this.mixInCandidates,
      mixOutCandidates: mixOutCandidates ?? this.mixOutCandidates,
      energyCurve: energyCurve ?? this.energyCurve,
      lowEnergyCurve: lowEnergyCurve ?? this.lowEnergyCurve,
      vocalMask: vocalMask ?? this.vocalMask,
      vocalProbability: vocalProbability ?? this.vocalProbability,
    );
  }
}
