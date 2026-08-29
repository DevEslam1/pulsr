// lib/core/telemetry/playback_latency_tracker.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../utils/error_logger.dart';
import 'clock.dart';

/// Stages in tap-to-audible pipeline. Ordered by expected occurrence.
enum PlaybackStage {
  tap,
  resolutionRequested,
  pluginEntered,
  clientRequestSent,
  poTokenNeeded,
  poTokenRegenerated,
  urlObtained,
  sourceSet,
  firstBytesReady,
  playing,
}

/// Bucket classification for latency budgets defined in GOAL.
enum PlaybackLatencyBucket {
  /// < 300 ms when stream URL is pre-resolved (next-in-queue, replay)
  preResolved,

  /// < 1 s warm (poToken cached, winning client known)
  warm,

  /// 2–3 s absolute worst case (cold, fresh install)
  cold,

  /// Exceeds 3 s – over budget.
  overBudget;
}

class PlaybackLatencyReport {
  final String playId;
  final String videoId;
  final DateTime startedAt;
  final DateTime finishedAt;
  final Duration total;
  final Map<PlaybackStage, Duration> stageOffsets;
  final Map<PlaybackStage, Duration> stageDurations;
  final bool success;
  final String? failureStage;
  final PlaybackLatencyBucket bucket;

  const PlaybackLatencyReport({
    required this.playId,
    required this.videoId,
    required this.startedAt,
    required this.finishedAt,
    required this.total,
    required this.stageOffsets,
    required this.stageDurations,
    required this.success,
    this.failureStage,
    required this.bucket,
  });

  Map<String, dynamic> toJson() => {
        'playId': playId,
        'videoId': videoId,
        'startedAt': startedAt.toIso8601String(),
        'finishedAt': finishedAt.toIso8601String(),
        'totalMs': total.inMilliseconds,
        'stageOffsetsMs': stageOffsets.map((k, v) => MapEntry(k.name, v.inMilliseconds)),
        'stageDurationsMs': stageDurations.map((k, v) => MapEntry(k.name, v.inMilliseconds)),
        'success': success,
        'failureStage': failureStage,
        'bucket': bucket.name,
      };

  @override
  String toString() =>
      'PlaybackLatencyReport(playId=$playId, videoId=$videoId, total=${total.inMilliseconds}ms, bucket=${bucket.name})';
}

class _Session {
  final String playId;
  final String videoId;
  final DateTime startTime;
  final Map<PlaybackStage, DateTime> stageTimes = {};
  final Map<String, String> tags = {};
  ISentrySpan? transaction;
  final Map<PlaybackStage, ISentrySpan> stageSpans = {};
  bool closed = false;

  _Session({
    required this.playId,
    required this.videoId,
    required this.startTime,
    this.transaction,
  });
}

/// Singleton tracker that measures tap-to-audible latency across Dart
/// and native plugin stages.
///
/// Emits Sentry transaction with child spans when DSN is configured,
/// otherwise falls back to breadcrumbs via [ErrorLogger]. Always emits
/// one debug summary line per play.
@lazySingleton
class PlaybackLatencyTracker {
  @factoryMethod
  PlaybackLatencyTracker()
      : _clock = const SystemClock(),
        _enableDebugPrint = true;

  @visibleForTesting
  PlaybackLatencyTracker.withClock(this._clock) : _enableDebugPrint = false;

  final Clock _clock;
  final bool _enableDebugPrint;

  _Session? _active;
  final List<PlaybackLatencyReport> _history = [];
  final StreamController<PlaybackLatencyReport> _reportController =
      StreamController<PlaybackLatencyReport>.broadcast();

  /// Stream of completed reports.
  Stream<PlaybackLatencyReport> get reports => _reportController.stream;

  /// Last completed report, if any.
  PlaybackLatencyReport? get lastReport =>
      _history.isEmpty ? null : _history.last;

  /// Full history (oldest first). Capped at 100 entries.
  List<PlaybackLatencyReport> get history => List.unmodifiable(_history);

  /// Current active playId, if any.
  String? get activePlayId => _active?.playId;
  String? get activeVideoId => _active?.videoId;

  /// Visible for testing: classification tags on the active session.
  @visibleForTesting
  Map<String, String>? get activeTags =>
      (_active != null && !_active!.closed) ? Map.unmodifiable(_active!.tags) : null;

  bool get hasActiveSession => _active != null && !_active!.closed;

  /// Starts a new playback measurement. Any previous unfinished session is
  /// force-finished (failure) so every play produces a breakdown.
  String start({required String videoId, String? quality}) {
    final now = _clock.now();
    // Close previous if dangling
    if (_active != null && !_active!.closed) {
      _finishInternal(success: false, failureStage: 'superseded', endTime: now);
    }
    final playId = _generatePlayId(videoId, now);
    ISentrySpan? transaction;
    try {
      transaction = Sentry.startTransaction(
        'playback:$videoId',
        'playback',
        description: 'tap-to-audible for $videoId',
        startTimestamp: now,
        bindToScope: false,
      );
      transaction.setTag('videoId', videoId);
      if (quality != null) transaction.setTag('quality', quality);
    } catch (_) {
      transaction = null;
    }
    final session = _Session(
      playId: playId,
      videoId: videoId,
      startTime: now,
      transaction: transaction,
    );
    _active = session;
    _markInternal(PlaybackStage.tap, at: now, isStart: true);
    // Breadcrumb for tap (also emitted via mark)
    return playId;
  }

  /// Marks a stage as reached. Returns elapsed from tap, or null if no active session.
  Duration? markStage(PlaybackStage stage, {Map<String, dynamic>? data}) {
    if (_active == null || _active!.closed) return null;
    final now = _clock.now();
    return _markInternal(stage, at: now, data: data);
  }

  /// Marks a stage at explicit timestamp (used for native-reported times).
  Duration? markStageAt(PlaybackStage stage, DateTime timestamp,
      {Map<String, dynamic>? data}) {
    if (_active == null || _active!.closed) return null;
    return _markInternal(stage, at: timestamp, data: data);
  }

  /// Sets a cheap classification tag on the active Sentry playback
  /// transaction (e.g. cacheHit, tierUsed). No-op without an active session.
  void setTag(String name, String value) {
    final session = _active;
    if (session == null || session.closed) return;
    session.tags[name] = value;
    try {
      session.transaction?.setTag(name, value);
    } catch (_) {}
  }

  /// Attaches a native-side timing relayed one-way over the platform channel
  /// (poToken.mint, ladder.client_attempt, rate_limiter.wait_player,
  /// executor.queue_wait) to the active session as transaction data
  /// attributes. Fire-and-forget: dropped when no session is active.
  void markNativeTiming(String name, int durationMs,
      {Map<String, dynamic>? attrs}) {
    final session = _active;
    if (session == null || session.closed) return;
    try {
      final key = 'native_$name';
      // poTokenWasCold classification tag comes from the mint relay.
      final cold = attrs?['cold'];
      if (name == 'poToken.mint' && cold is bool) {
        setTag('poTokenWasCold', cold ? 'true' : 'false');
      }
      final tx = session.transaction;
      if (tx != null && Sentry.isEnabled) {
        tx.setData('${key}_ms', durationMs);
        if (attrs != null) {
          for (final entry in attrs.entries) {
            tx.setData('$key.${entry.key}', entry.value);
          }
        }
      }
    } catch (_) {}
  }

  Duration _markInternal(PlaybackStage stage,
      {required DateTime at, Map<String, dynamic>? data, bool isStart = false}) {
    final session = _active!;
    final already = session.stageTimes[stage];
    if (already != null) {
      // Idempotent per stage: keep earliest occurrence to avoid duplicate later marks skewing metrics.
      return at.difference(session.startTime);
    }
    session.stageTimes[stage] = at;
    final elapsed = at.difference(session.startTime);

    // Emit Sentry child span or breadcrumb fallback
    final stageName = stage.name;
    try {
      if (Sentry.isEnabled && session.transaction != null) {
        // Child span: start = previous stage or session start, end = now
        final previousTime = _previousStageTime(session, stage) ?? session.startTime;
        final span = session.transaction!.startChild(
          'playback.stage.$stageName',
          description: stageName,
          startTimestamp: previousTime,
        );
        span.setData('elapsedMs', elapsed.inMilliseconds);
        if (data != null) {
          for (final entry in data.entries) {
            span.setData(entry.key, entry.value);
          }
        }
        span.finish(endTimestamp: at);
        session.stageSpans[stage] = span;
      } else {
        // Breadcrumb fallback
        ErrorLogger.addBreadcrumb(
          'Playback stage $stageName @ ${elapsed.inMilliseconds}ms',
          category: 'playback.latency',
          data: {
            'videoId': session.videoId,
            'playId': session.playId,
            'stage': stageName,
            'elapsedMs': elapsed.inMilliseconds,
            ...?data,
          },
        );
      }
    } catch (_) {
      // Fallback to breadcrumb on any Sentry error
      try {
        ErrorLogger.addBreadcrumb(
          'Playback stage $stageName @ ${elapsed.inMilliseconds}ms',
          category: 'playback.latency',
          data: {
            'videoId': session.videoId,
            'playId': session.playId,
            'stage': stageName,
            'elapsedMs': elapsed.inMilliseconds,
            ...?data,
          },
        );
      } catch (_) {}
    }

    // If playing stage is reached, auto-finish successfully
    if (stage == PlaybackStage.playing) {
      // Use the same timestamp as the mark for total
      _finishInternal(success: true, endTime: at);
    }
    return elapsed;
  }

  DateTime? _previousStageTime(_Session session, PlaybackStage current) {
    // Find the latest timestamp among stages that are before current in enum order
    final idx = PlaybackStage.values.indexOf(current);
    DateTime? latest;
    for (int i = 0; i < idx; i++) {
      final s = PlaybackStage.values[i];
      final t = session.stageTimes[s];
      if (t != null) {
        if (latest == null || t.isAfter(latest)) latest = t;
      }
    }
    return latest;
  }

  /// Finishes the current playback session explicitly (e.g., on error).
  PlaybackLatencyReport? finish({bool success = true, String? failureStage}) {
    if (_active == null || _active!.closed) return null;
    final now = _clock.now();
    return _finishInternal(success: success, failureStage: failureStage, endTime: now);
  }

  /// Finishes with failure at a given stage.
  PlaybackLatencyReport? finishWithError(Object error, {PlaybackStage? stage}) {
    if (_active == null || _active!.closed) return null;
    final now = _clock.now();
    final stageName = stage?.name ?? error.toString();
    return _finishInternal(success: false, failureStage: stageName, endTime: now);
  }

  PlaybackLatencyReport _finishInternal({
    required bool success,
    String? failureStage,
    required DateTime endTime,
  }) {
    final session = _active!;
    session.closed = true;
    final total = endTime.difference(session.startTime);
    final bucket = bucketFor(total);

    // Compute stage offsets (from tap) and incremental durations
    final offsets = <PlaybackStage, Duration>{};
    final durations = <PlaybackStage, Duration>{};
    DateTime? prev = session.startTime;
    PlaybackStage? prevStage;
    // Iterate in enum order, only for stages that were marked
    for (final stage in PlaybackStage.values) {
      final t = session.stageTimes[stage];
      if (t != null) {
        offsets[stage] = t.difference(session.startTime);
        if (prevStage != null && prev != null) {
          durations[stage] = t.difference(prev);
        } else {
          durations[stage] = t.difference(session.startTime);
        }
        prev = t;
        prevStage = stage;
      }
    }

    // Fill missing stages with negative sentinel? Instead we keep them absent but
    // report will still contain all observed stages. For "full breakdown", ensure
    // at least tap and playing are present if success.

    final report = PlaybackLatencyReport(
      playId: session.playId,
      videoId: session.videoId,
      startedAt: session.startTime,
      finishedAt: endTime,
      total: total,
      stageOffsets: offsets,
      stageDurations: durations,
      success: success,
      failureStage: failureStage,
      bucket: bucket,
    );

    // Emit transaction finish + debug summary
    try {
      if (session.transaction != null) {
        session.transaction!.setData('totalMs', total.inMilliseconds);
        session.transaction!.setData('bucket', bucket.name);
        session.transaction!.setData('success', success);
        if (failureStage != null) session.transaction!.setData('failureStage', failureStage);
        // Re-apply classification tags in case any setTag raced span creation.
        for (final entry in session.tags.entries) {
          session.transaction!.setTag(entry.key, entry.value);
        }
        for (final entry in offsets.entries) {
          session.transaction!.setData('offset_${entry.key.name}_ms', entry.value.inMilliseconds);
        }
        session.transaction!.finish(
          status: success ? SpanStatus.ok() : SpanStatus.internalError(),
          endTimestamp: endTime,
        );
      } else if (!Sentry.isEnabled) {
        // Ensure breadcrumb for finish
        ErrorLogger.addBreadcrumb(
          'Playback ${success ? "success" : "failure"} total ${total.inMilliseconds}ms bucket ${bucket.name}',
          category: 'playback.latency',
          data: {
            'videoId': session.videoId,
            'playId': session.playId,
            'totalMs': total.inMilliseconds,
            'bucket': bucket.name,
            'success': success,
            if (failureStage != null) 'failureStage': failureStage,
          },
        );
      }
    } catch (_) {}

    _emitSummary(report);
    _history.add(report);
    if (_history.length > 100) _history.removeAt(0);
    _reportController.add(report);
    // Clear active so next start creates new
    _active = null;
    return report;
  }

  void _emitSummary(PlaybackLatencyReport report) {
    final offsets = report.stageOffsets;
    final parts = <String>[];
    for (final stage in PlaybackStage.values) {
      final d = offsets[stage];
      if (d != null) {
        parts.add('${stage.name}=${d.inMilliseconds}ms');
      } else {
        parts.add('${stage.name}=—');
      }
    }
    final summary =
        '[PlaybackLatency] playId=${report.playId} videoId=${report.videoId} total=${report.total.inMilliseconds}ms bucket=${report.bucket.name} success=${report.success} breakdown: ${parts.join(", ")}';
    if (_enableDebugPrint) {
      debugPrint(summary);
    } else {
      // In tests, avoid debugPrint noise but still log via ErrorLogger breadcrumb for capture
      ErrorLogger.addBreadcrumb(summary, category: 'playback.latency.summary');
    }
    // Also always log via ErrorLogger for persistent diagnostics
    ErrorLogger.log(summary, category: 'PlaybackLatency');
  }

  static PlaybackLatencyBucket bucketFor(Duration total) {
    final ms = total.inMilliseconds;
    if (ms < 300) return PlaybackLatencyBucket.preResolved;
    if (ms < 1000) return PlaybackLatencyBucket.warm;
    if (ms < 3000) return PlaybackLatencyBucket.cold;
    return PlaybackLatencyBucket.overBudget;
  }

  /// Human-readable bucket description.
  static String describeBucket(PlaybackLatencyBucket bucket, Duration total) {
    switch (bucket) {
      case PlaybackLatencyBucket.preResolved:
        return 'preResolved (<300ms) — cache hit / replay';
      case PlaybackLatencyBucket.warm:
        return 'warm (<1s) — poToken cached, winning client known';
      case PlaybackLatencyBucket.cold:
        return 'cold (<3s) — worst case fresh install';
      case PlaybackLatencyBucket.overBudget:
        return 'overBudget (>=3s) — exceeds worst-case budget';
    }
  }

  /// Returns true if [total] meets the budget for its bucket scenario.
  static bool meetsBudgetForScenario({
    required Duration total,
    required PlaybackLatencyBucket scenario,
  }) {
    switch (scenario) {
      case PlaybackLatencyBucket.preResolved:
        return total.inMilliseconds < 300;
      case PlaybackLatencyBucket.warm:
        return total.inMilliseconds < 1000;
      case PlaybackLatencyBucket.cold:
        return total.inMilliseconds < 3000;
      case PlaybackLatencyBucket.overBudget:
        return false;
    }
  }

  String _generatePlayId(String videoId, DateTime now) {
    return '${videoId}_${now.millisecondsSinceEpoch}_${now.microsecond}';
  }

  @visibleForTesting
  void debugReset() {
    if (_active != null && !_active!.closed) {
      try {
        _active!.transaction?.finish(status: SpanStatus.cancelled());
      } catch (_) {}
    }
    _active = null;
    _history.clear();
  }

  void dispose() {
    _reportController.close();
  }
}
