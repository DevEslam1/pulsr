// lib/core/services/ytm_circuit_breaker.dart
import '../errors/ytm_error_classifier.dart';

/// Per-signal circuit breaker + metrics for the YTM resolve chain.
///
/// The resolve chain in `YtmService` already has bot/video cooldowns; this
/// adds what it lacks: bounded per-signal failure counts, explicit cooldown
/// windows per signal, and observable metrics for debugging Google's
/// cat-and-mouse breaks. No XDM/backend dependency — on-device only.
///
/// Constructed directly by [YtmService] (not DI-registered), so it carries no
/// `@singleton` annotation.
class YtmCircuitBreaker {
  static const int maxConsecutiveFailures = 3;

  static const Map<YtmBlockSignal, Duration> cooldowns = {
    YtmBlockSignal.botChallenge: Duration(minutes: 5),
    YtmBlockSignal.poTokenInvalid: Duration(seconds: 30),
    YtmBlockSignal.rateLimited: Duration(minutes: 2),
    YtmBlockSignal.ipBlocked: Duration(minutes: 10),
    YtmBlockSignal.clientDeprecated: Duration(seconds: 30),
    YtmBlockSignal.sabrEnforced: Duration(seconds: 30),
    YtmBlockSignal.signatureDecipherFailed: Duration(minutes: 1),
    YtmBlockSignal.networkUnavailable: Duration(seconds: 10),
    YtmBlockSignal.geoBlocked: Duration.zero,
    YtmBlockSignal.signInRequired: Duration.zero,
    YtmBlockSignal.videoGone: Duration.zero,
  };

  final Map<YtmBlockSignal, int> _consecutiveFailures = {};
  final Map<YtmBlockSignal, DateTime> _openUntil = {};
  final Map<YtmBlockSignal, int> _totalFailures = {};
  int _totalSuccesses = 0;

  /// The wall clock is injectable so the half-open transition (F2) can be
  /// exercised without waiting out a real cooldown window in a test.
  YtmCircuitBreaker([DateTime Function()? now]) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  /// False when this signal's breaker is open (still cooling down).
  bool shouldAllow(YtmBlockSignal signal) {
    final until = _openUntil[signal];
    if (until == null) return true;
    if (_now().isAfter(until)) {
      _openUntil.remove(signal);
      // F2: a half-open breaker starts its failure budget over. Leaving the
      // tripped count in place meant a single failure after the cooldown
      // re-opened the window for its full length, so one bad resolve per
      // cooldown latched the signal shut for good instead of requiring
      // `maxConsecutiveFailures` fresh failures.
      _consecutiveFailures.remove(signal);
      return true;
    }
    return false;
  }

  /// Record a classified failure; opens the breaker past the threshold.
  void recordFailure(YtmBlockSignal signal) {
    _totalFailures.update(signal, (v) => v + 1, ifAbsent: () => 1);
    // Transient network failures (SocketException, YTM_OFFLINE/TIMEOUT) should
    // NOT trip the circuit breaker. They are caused by brief connectivity
    // interruptions, not by YouTube blocking this IP/client. Opening the breaker
    // on network blips silenced the native resolve tiers for 10 seconds per blip
    // — enough to cover the start of the next song and produce the symptom of
    // "no connection after ~2 songs" even though the internet was working fine.
    // Total-failure accounting still increments above for diagnostics.
    if (signal == YtmBlockSignal.networkUnavailable) return;
    final n = (_consecutiveFailures[signal] ?? 0) + 1;
    _consecutiveFailures[signal] = n;
    if (n >= maxConsecutiveFailures) {
      final window = cooldowns[signal] ?? const Duration(minutes: 2);
      if (window > Duration.zero) {
        _openUntil[signal] = _now().add(window);
      }
    } else if (signal == YtmBlockSignal.botChallenge ||
        signal == YtmBlockSignal.ipBlocked) {
      // First bot/IP hit still cools briefly to avoid burning client matrix.
      final window = cooldowns[signal] ?? const Duration(minutes: 5);
      _openUntil[signal] = _now().add(window);
    }
  }

  void recordSuccess() {
    _totalSuccesses++;
    _consecutiveFailures.clear();
  }

  /// Snapshot for logs/diagnostics UI. Keys are signal names.
  Map<String, dynamic> metrics() => {
        'successes': _totalSuccesses,
        'failures': {for (final e in _totalFailures.entries) e.key.name: e.value},
        'open': {
          for (final e in _openUntil.entries)
            if (_now().isBefore(e.value)) e.key.name: e.value.toIso8601String(),
        },
      };

  /// Classify [error] and record it; returns the info for recovery mapping.
  YtmErrorInfo classifyAndRecord(Object error, [String? traceId]) {
    final info = YtmErrorClassifier.classify(error, traceId);
    if (info.signal != null) recordFailure(info.signal!);
    return info;
  }
}
