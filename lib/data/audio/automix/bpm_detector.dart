// lib/data/audio/automix/bpm_detector.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/utils/error_logger.dart';
import 'track_analysis.dart';

/// Lightweight BPM estimator and beat-grid calculator with local cache (`track_id -> TrackAnalysis`).
class BpmDetector {
  static const String prefsCacheKey = 'pulsr_automix_analysis_cache_v1';
  static const int maxCacheEntries = 500;

  /// Default musical keys
  static const List<String> standardKeys = [
    'C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B',
    'Am', 'Bbm', 'Bm', 'Cm', 'C#m', 'Dm', 'Ebm', 'Em', 'Fm', 'F#m', 'Gm', 'G#m',
  ];

  final Map<String, TrackAnalysis> _cache = {};
  late final Future<void> ready;
  Future<void> _persistChain = Future<void>.value();

  BpmDetector() {
    ready = _load();
  }

  /// Gets cached [TrackAnalysis] for a given track id or key.
  TrackAnalysis? getCachedAnalysis(String trackId) => _cache[trackId];

  /// Stores or updates [TrackAnalysis] in memory and persists to local storage.
  Future<void> cacheAnalysis(String trackId, TrackAnalysis analysis) async {
    await ready;
    if (trackId.isEmpty) return;
    _cache.remove(trackId);
    _cache[trackId] = analysis;
    _trimCache();
    await _persist();
  }

  /// Estimates or derives a [TrackAnalysis] using provided metadata or waveform heuristics.
  /// If [explicitBpm] is provided, it is used; otherwise an estimate is constructed.
  TrackAnalysis estimateTrackAnalysis({
    required String trackId,
    required double durationSeconds,
    double? explicitBpm,
    String? explicitKey,
    double? beatConfidence,
    int? mixInCueMs,
    int? mixOutCueMs,
  }) {
    final cached = _cache[trackId];
    if (cached != null && cached.isUsable) {
      if (explicitBpm != null && (cached.bpm - explicitBpm).abs() > 0.5) {
        // Update cached with new explicit BPM
        final updated = calculateBeatGrid(
          trackId: trackId,
          bpm: explicitBpm,
          durationSeconds: durationSeconds > 0 ? durationSeconds : cached.duration,
          key: explicitKey ?? cached.key,
          beatConfidence: beatConfidence ?? 0.8,
          mixInCueMs: mixInCueMs,
          mixOutCueMs: mixOutCueMs,
        );
        unawaited(cacheAnalysis(trackId, updated));
        return updated;
      }
      return cached;
    }

    final effectiveBpm = (explicitBpm != null && explicitBpm >= 40 && explicitBpm <= 240)
        ? explicitBpm
        : 120.0;
    final effectiveConfidence = (explicitBpm != null && explicitBpm >= 40 && explicitBpm <= 240)
        ? (beatConfidence ?? 0.85)
        : 0.3;

    final analysis = calculateBeatGrid(
      trackId: trackId,
      bpm: effectiveBpm,
      durationSeconds: durationSeconds,
      key: explicitKey ?? '',
      beatConfidence: effectiveConfidence,
      mixInCueMs: mixInCueMs,
      mixOutCueMs: mixOutCueMs,
    );

    unawaited(cacheAnalysis(trackId, analysis));
    return analysis;
  }

  /// Generates synthetic beat grid, downbeats, phrase boundaries, and mix cues
  /// for a track of known or estimated BPM and duration.
  static TrackAnalysis calculateBeatGrid({
    required String trackId,
    required double bpm,
    required double durationSeconds,
    String key = '',
    double beatConfidence = 0.8,
    double keyConfidence = 0.5,
    int? mixInCueMs,
    int? mixOutCueMs,
  }) {
    if (bpm <= 0 || durationSeconds <= 0) {
      return TrackAnalysis(
        trackId: trackId,
        bpm: bpm,
        duration: durationSeconds,
        beatConfidence: 0.0,
      );
    }

    final beatInterval = 60.0 / bpm;
    // Assume musical start ~ 0.5s or first beat offset
    final firstBeat = math.min(0.5, beatInterval * 0.5);
    final downbeats = <double>[];
    final phraseBoundaries = <double>[];

    // Downbeats every 4 beats (4/4 time signature)
    final barInterval = beatInterval * 4.0;
    // Phrase boundaries every 8 bars (32 beats) or 4 bars (16 beats)
    final phraseInterval = barInterval * 4.0;

    var currentBar = firstBeat;
    while (currentBar < durationSeconds) {
      downbeats.add(currentBar);
      currentBar += barInterval;
    }

    var currentPhrase = firstBeat;
    while (currentPhrase < durationSeconds) {
      phraseBoundaries.add(currentPhrase);
      currentPhrase += phraseInterval;
    }

    // Mix-in cue: skip quiet intro / lead-in, landing on bar 2 or 4 (or 16 beats)
    final defaultMixInSec = math.min(
      barInterval * 2.0,
      durationSeconds * 0.15,
    );
    final resolvedMixInSec = mixInCueMs != null && mixInCueMs > 0
        ? (mixInCueMs / 1000.0)
        : defaultMixInSec;

    // Mix-out cue: start blend before outro silence
    final defaultMixOutSec = math.max(
      0.0,
      durationSeconds - math.max(barInterval * 4.0, 12.0),
    );
    final resolvedMixOutSec = mixOutCueMs != null && mixOutCueMs > 0
        ? (mixOutCueMs / 1000.0)
        : defaultMixOutSec;

    final mixInCandidates = <MixCandidate>[
      MixCandidate(time: resolvedMixInSec, score: 0.9, type: 'intro_drop'),
      if (phraseBoundaries.length > 1)
        MixCandidate(time: phraseBoundaries[1], score: 0.85, type: 'phrase'),
    ];

    final mixOutCandidates = <MixCandidate>[
      MixCandidate(time: resolvedMixOutSec, score: 0.9, type: 'outro_start'),
      MixCandidate(time: durationSeconds, score: 0.75, type: 'content_end'),
    ];

    return TrackAnalysis(
      status: TrackAnalysis.statusReady,
      trackId: trackId,
      duration: durationSeconds,
      bpm: bpm,
      beatInterval: beatInterval,
      beatConfidence: beatConfidence.clamp(0.0, 1.0),
      downbeats: downbeats,
      phraseBoundaries: phraseBoundaries,
      firstBeat: firstBeat,
      key: key,
      keyConfidence: key.isNotEmpty ? keyConfidence : 0.0,
      energyLevel: 0.7,
      mixInCueMs: (resolvedMixInSec * 1000).round(),
      mixOutCueMs: (resolvedMixOutSec * 1000).round(),
      audibleStartTime: firstBeat * 0.5,
      introEndTime: resolvedMixInSec,
      contentEndTime: durationSeconds,
      outroStartTime: resolvedMixOutSec,
      mixInTime: resolvedMixInSec,
      mixOutTime: resolvedMixOutSec,
      mixInCandidates: mixInCandidates,
      mixOutCandidates: mixOutCandidates,
      energyCurve: const [],
      lowEnergyCurve: const [],
      vocalMask: const [],
      vocalProbability: 0.2,
    );
  }

  void _trimCache() {
    final excess = _cache.length - maxCacheEntries;
    if (excess <= 0) return;
    final toRemove = _cache.keys.take(excess).toList();
    for (final k in toRemove) {
      _cache.remove(k);
    }
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsCacheKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      decoded.forEach((k, v) {
        if (k is String && v is Map<String, dynamic>) {
          try {
            _cache[k] = TrackAnalysis.fromJson(v);
          } catch (_) {}
        }
      });
      _trimCache();
    } catch (e, st) {
      ErrorLogger.log('Failed to load BPM detector analysis cache',
          error: e, stackTrace: st, category: 'BpmDetector');
    }
  }

  Future<void> _persist() {
    _persistChain = _persistChain.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final rawMap = <String, dynamic>{};
        _cache.forEach((k, v) {
          rawMap[k] = v.toJson();
        });
        await prefs.setString(prefsCacheKey, jsonEncode(rawMap));
      } catch (e, st) {
        ErrorLogger.log('Failed to persist BPM detector analysis cache',
            error: e, stackTrace: st, category: 'BpmDetector');
      }
    });
    return _persistChain;
  }
}
