// F4: Adaptive quality during playback (switch bitrate mid-track).
import 'dart:async';

/// Quality ladder from lowest to highest bandwidth.
const List<String> kQualityLadder = ['low', 'medium', 'high'];

int qualityRank(String q) {
  final i = kQualityLadder.indexOf(q.toLowerCase());
  return i < 0 ? 1 : i;
}

/// Pure policy: decides target quality from recent observations.
/// Kept side-effect free so it is unit-testable; the handler applies
/// the decision by re-resolving the stream and hot-swapping the source.
class AdaptiveQualityPolicy {
  final int underrunThreshold;
  final int healthyThreshold;

  int _consecutiveUnderruns = 0;
  int _consecutiveHealthy = 0;

  AdaptiveQualityPolicy({this.underrunThreshold = 2, this.healthyThreshold = 4});

  /// Returns a new quality when a switch is advised, else null.
  String? onBufferUnderrun(String current) {
    _consecutiveHealthy = 0;
    _consecutiveUnderruns++;
    if (_consecutiveUnderruns >= underrunThreshold) {
      _consecutiveUnderruns = 0;
      final rank = qualityRank(current);
      if (rank > 0) return kQualityLadder[rank - 1];
    }
    return null;
  }

  String? onHealthyWindow(String current) {
    _consecutiveUnderruns = 0;
    _consecutiveHealthy++;
    if (_consecutiveHealthy >= healthyThreshold) {
      _consecutiveHealthy = 0;
      final rank = qualityRank(current);
      if (rank < kQualityLadder.length - 1) {
        return kQualityLadder[rank + 1];
      }
    }
    return null;
  }

  void reset() {
    _consecutiveUnderruns = 0;
    _consecutiveHealthy = 0;
  }
}

/// Runtime controller wiring the policy to handler callbacks.
class AdaptiveQualityManager {
  final AdaptiveQualityPolicy policy;
  bool enabled;
  String currentQuality;
  final Future<void> Function(String newQuality)? onSwitchRequested;
  DateTime? _lastSwitchAt;
  final Duration cooldown;

  final StreamController<String> _switchSubject =
      StreamController<String>.broadcast();
  Stream<String> get onSwitch => _switchSubject.stream;

  AdaptiveQualityManager({
    AdaptiveQualityPolicy? policy,
    this.enabled = true,
    this.currentQuality = 'high',
    this.onSwitchRequested,
    this.cooldown = const Duration(seconds: 20),
  }) : policy = policy ?? AdaptiveQualityPolicy();

  bool get _cooledDown =>
      _lastSwitchAt == null ||
      DateTime.now().difference(_lastSwitchAt!) >= cooldown;

  Future<String?> reportUnderrun() async {
    if (!enabled) return null;
    // Keep feeding observations into the policy even during cooldown so the
    // counters reflect reality; only the *apply* is gated on the cooldown.
    // Returning early before touching the policy discarded every event that
    // arrived inside the window, resetting progress toward a step decision.
    final next = policy.onBufferUnderrun(currentQuality);
    if (next != null && _cooledDown) return _apply(next);
    return null;
  }

  Future<String?> reportHealthy() async {
    if (!enabled) return null;
    final next = policy.onHealthyWindow(currentQuality);
    if (next != null && _cooledDown) return _apply(next);
    return null;
  }

  Future<String?> _apply(String next) async {
    final previous = currentQuality;
    _lastSwitchAt = DateTime.now();
    policy.reset();
    try {
      await onSwitchRequested?.call(next);
    } catch (_) {
      // The hot-swap/re-resolve failed. Stay truthful about the quality that
      // is actually playing: committing `next` here made every later ladder
      // decision (qualityRank, step-up ceiling) reason against a quality we
      // never reached, and the failed switch would never be retried.
      currentQuality = previous;
      _lastSwitchAt = null; // Reset so retry is not blocked by cooldown
      return null;
    }
    currentQuality = next;
    if (!_switchSubject.isClosed) _switchSubject.add(next);
    return next;
  }

  void setQuality(String q) {
    currentQuality = q;
    policy.reset();
  }

  void dispose() => _switchSubject.close();
}
