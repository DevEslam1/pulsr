import 'dart:math' as math;

/// Decision produced by [PartySyncController.evaluatePosition].
enum SyncAction {
  /// Within the audible deadband — leave playback alone.
  none,

  /// Jump to the compensated target.
  seek,

  /// The error is real but small: wait for one more tick before acting, so a
  /// single stale frame cannot cause an audible jump.
  watch,
}

/// One sync evaluation, including the numbers that led to it (for the party UI
/// and for tests that must assert behaviour, not just types).
class SyncDecision {
  /// Signed error in ms: positive means this device is audible AHEAD of the room.
  final int errorMs;
  final SyncAction action;
  final int? seekToMs;
  final int strikes;

  const SyncDecision({
    required this.errorMs,
    required this.action,
    this.seekToMs,
    this.strikes = 0,
  });

  bool get acts => action == SyncAction.seek;
}

/// Outcome of planning a start against a server anchor.
class StartPlan {
  final Duration wait;
  final Duration applied;

  const StartPlan({required this.wait, required this.applied});

  /// True when the anchor is in the past or imminently due: start now.
  bool get startImmediately => applied <= Duration.zero;
}

/// Party sync arithmetic.
///
/// Why latency rather than tempo: playback position is extrapolated locally from
/// an anchor between state updates, so a device's sample-clock error contributes
/// roughly 50 ppm — 0.08 ms across a 1.5 s heartbeat, which no rate correction
/// could meaningfully improve. What actually puts members out of agreement is
/// that each device renders sound a different number of milliseconds after the
/// position was produced (Bluetooth can exceed 200 ms). Compensating that term
/// directly is what turns "same position" into "same sound".
class PartySyncController {
  /// Errors inside this band are inaudible on headphones; acting on them would
  /// cause more seeks than drift.
  static const int audibleDeadbandMs = 15;

  /// Beyond this the error is obvious enough to jump for immediately.
  static const int seekThresholdMs = 120;

  /// Grey-band errors need this many consecutive ticks before seeking, so one
  /// late frame does not interrupt playback.
  static const int persistentStrikes = 2;

  /// How often followers re-evaluate. 250 ms bounds transient error well under
  /// the audible threshold while costing one small frame decision per tick.
  static const int reconcileTickMs = 250;

  /// A scheduled start later than this is treated as a stale or bogus anchor and
  /// performed immediately instead of leaving the listener silent.
  static const int maxScheduledStartWaitMs = 2000;

  /// Anchors closer than this are not worth arming a timer for; the timer
  /// resolution would be the larger error.
  static const int minScheduledStartWaitMs = 12;

  int _strikes = 0;

  void reset() => _strikes = 0;

  int get strikes => _strikes;

  /// Converts the host's reported RENDER position into the room's AUDIBLE
  /// timeline. Sound from the host arrives `hostOutputLatencyMs` after that
  /// position was rendered, so the room time it corresponds to is later by the
  /// same amount. Without this term every follower converges onto the host's
  /// speaker delay instead of onto the music.
  static int audibleAnchorPositionMs({
    required int hostRenderPositionMs,
    required int hostOutputLatencyMs,
  }) =>
      math.max(0, hostRenderPositionMs + math.max(0, hostOutputLatencyMs));

  /// The render position a member must be at so that its *heard* audio sits at
  /// [roomPositionMs]. A device with output latency plays slightly in the past.
  static int targetRenderPositionMs({
    required int roomPositionMs,
    required int outputLatencyMs,
  }) =>
      math.max(0, roomPositionMs - math.max(0, outputLatencyMs));

  /// Signed error: positive means this device is audible ahead of the room.
  static int signedErrorMs({
    required int localRenderMs,
    required int roomPositionMs,
    required int outputLatencyMs,
  }) =>
      localRenderMs -
      targetRenderPositionMs(
          roomPositionMs: roomPositionMs, outputLatencyMs: outputLatencyMs);

  /// Classifies an error and tracks consecutive grey-band strikes.
  SyncDecision evaluatePosition({
    required int localRenderMs,
    required int roomPositionMs,
    required int outputLatencyMs,
    int? durationMs,
  }) {
    final error = signedErrorMs(
      localRenderMs: localRenderMs,
      roomPositionMs: roomPositionMs,
      outputLatencyMs: outputLatencyMs,
    );
    final magnitude = error.abs();

    if (magnitude <= audibleDeadbandMs) {
      _strikes = 0;
      return SyncDecision(errorMs: error, action: SyncAction.none);
    }

    // Never seek past the end of the track: a follower that overshoots by more
    // than the remaining time should stop at the duration instead.
    final target = targetRenderPositionMs(
        roomPositionMs: roomPositionMs, outputLatencyMs: outputLatencyMs);
    final clampedTarget = durationMs != null && durationMs > 0
        ? math.min(target, durationMs)
        : target;

    if (magnitude > seekThresholdMs) {
      _strikes = 0;
      return SyncDecision(
        errorMs: error,
        action: SyncAction.seek,
        seekToMs: clampedTarget,
      );
    }

    _strikes++;
    if (_strikes >= persistentStrikes) {
      _strikes = 0;
      return SyncDecision(
        errorMs: error,
        action: SyncAction.seek,
        seekToMs: clampedTarget,
      );
    }
    return SyncDecision(
        errorMs: error, action: SyncAction.watch, strikes: _strikes);
  }

  /// Plans a start for the server's anchor instant.
  ///
  /// The server deliberately schedules `PlayLeadMs` into the future so all
  /// members can arm a single start. Acting on arrival instead throws that away,
  /// which is why a state frame that reaches one device 80 ms later than another
  /// produced an 80 ms audible offset no seek could justify.
  static StartPlan planStart({
    required int anchorServerMs,
    required int nowServerMs,
    int maxWaitMs = maxScheduledStartWaitMs,
  }) {
    final leadMs = anchorServerMs - nowServerMs;
    if (leadMs <= 0) {
      return const StartPlan(wait: Duration.zero, applied: Duration.zero);
    }
    if (leadMs > maxWaitMs) {
      // Treat an absurd lead as "start now" rather than silently going mute.
      return StartPlan(
        wait: Duration(milliseconds: leadMs),
        applied: Duration.zero,
      );
    }
    if (leadMs < minScheduledStartWaitMs) {
      return StartPlan(
        wait: Duration(milliseconds: leadMs),
        applied: Duration(milliseconds: leadMs),
      );
    }
    return StartPlan(
        wait: Duration(milliseconds: leadMs),
        applied: Duration(milliseconds: leadMs));
  }
}
