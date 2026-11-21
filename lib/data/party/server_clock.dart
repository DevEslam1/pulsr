// lib/data/party/server_clock.dart

/// This device's offset from the party server's clock.
///
/// Follows NTP-style clock synchronization over WebSocket ping/pong messages:
/// ```
/// offsetMs   = serverMs - (t0 + t1) / 2
/// roundTrip  = t1 - t0
/// ```
///
/// Tracks a sliding window of up to 12 samples with a 2-minute TTL (120,000ms).
/// The sample with the minimum round-trip time is selected to eliminate asymmetric
/// radio delay jitter.
class ServerClock {
  static const int windowSize = 12;
  static const int sampleTtlMs = 120000;

  final int Function() _localNowMs;

  final List<_ClockSample> _samples = [];
  final Set<int> _pendingPings = <int>{};

  int? _offsetMs;
  int _roundTripMs = 0;

  ServerClock({int Function()? localNowMs})
      : _localNowMs = localNowMs ?? _defaultMonotonicNowMs;

  static final Stopwatch _stopwatch = Stopwatch()..start();

  static int _defaultMonotonicNowMs() {
    return _stopwatch.elapsedMilliseconds;
  }

  /// True once at least one round-trip ping/pong has completed.
  bool get synced => _offsetMs != null;

  /// Current best offset in milliseconds: `serverMs - localMs`.
  int? get offsetMs => _offsetMs;

  /// Round trip time in milliseconds of the chosen best sample.
  int get roundTripMs => _roundTripMs;

  /// This device's monotonic millisecond timestamp.
  int nowMs() => _localNowMs();

  /// Server clock time estimated from local monotonic time + offset.
  /// Null until synced.
  int? serverNowMs() {
    final offset = _offsetMs;
    if (offset == null) return null;
    return _localNowMs() + offset;
  }

  /// Registers an outgoing ping timestamp into the in-flight ping set.
  void registerPing(int sentAtLocalMs) {
    _pendingPings.add(sentAtLocalMs);
    if (_pendingPings.length > 50) {
      _pendingPings.remove(_pendingPings.first);
    }
  }

  /// True if [sentAtLocalMs] is currently in the in-flight ping set.
  bool hasPendingPing(int sentAtLocalMs) => _pendingPings.contains(sentAtLocalMs);

  /// Records a ping/pong round trip.
  ///
  /// [sentAtLocalMs]: local timestamp when ping left (t0)
  /// [serverMs]: server's timestamp from pong body
  /// [receivedAtLocalMs]: local timestamp when pong arrived (t1)
  void record(int sentAtLocalMs, int serverMs, int receivedAtLocalMs) {
    if (receivedAtLocalMs < sentAtLocalMs) return;
    final roundTrip = receivedAtLocalMs - sentAtLocalMs;
    if (roundTrip > 5000) return;
    if (!_pendingPings.remove(sentAtLocalMs)) return;

    final midpoint = sentAtLocalMs + (roundTrip ~/ 2);
    final offset = serverMs - midpoint;

    _samples.add(_ClockSample(
      offsetMs: offset,
      roundTripMs: roundTrip,
      takenAtMs: receivedAtLocalMs,
    ));

    while (_samples.length > windowSize) {
      _samples.removeAt(0);
    }

    final cutoff = receivedAtLocalMs - sampleTtlMs;
    final usable = _samples.where((s) => s.takenAtMs >= cutoff).toList();
    final candidates =
        usable.isNotEmpty ? usable : List<_ClockSample>.from(_samples);

    if (candidates.isEmpty) return;

    _ClockSample best = candidates.first;
    for (int i = 1; i < candidates.length; i++) {
      if (candidates[i].roundTripMs < best.roundTripMs) {
        best = candidates[i];
      }
    }

    _offsetMs = best.offsetMs;
    _roundTripMs = best.roundTripMs;
  }

  /// Clears all samples and resets sync status.
  void reset() {
    _samples.clear();
    _pendingPings.clear();
    _offsetMs = null;
    _roundTripMs = 0;
  }
}

class _ClockSample {
  final int offsetMs;
  final int roundTripMs;
  final int takenAtMs;

  const _ClockSample({
    required this.offsetMs,
    required this.roundTripMs,
    required this.takenAtMs,
  });
}
