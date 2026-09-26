import 'dart:math' as math;
import '../../data/audio/audio_effects_channel.dart';

/// Represents a listening exposure session.
class DoseExposureSession {
  final DateTime timestamp;
  final Duration duration;
  final double estimatedDba;

  const DoseExposureSession({
    required this.timestamp,
    required this.duration,
    required this.estimatedDba,
  });

  /// Computes the Sound Dose fraction (where 1.0 = 100% weekly dose) according to EN 62368-1.
  /// Standard: 40 hours at 80 dBA = 1.0 dose (100%).
  /// Halving interval: 3 dB.
  double get doseFraction {
    final hours = duration.inMilliseconds / (1000.0 * 3600.0);
    // Allowed hours at this dBA: T = 40 * 2^((80 - L) / 3)
    // Fraction = hours / T = (hours / 40) * 2^((L - 80) / 3)
    final exponent = (estimatedDba - 80.0) / 3.0;
    final dose = (hours / 40.0) * math.pow(2.0, exponent);
    return math.max(0.0, dose);
  }

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'durationMs': duration.inMilliseconds,
        'estimatedDba': estimatedDba,
      };

  factory DoseExposureSession.fromJson(Map<String, dynamic> json) =>
      DoseExposureSession(
        timestamp: DateTime.parse(json['timestamp'] as String),
        duration: Duration(milliseconds: (json['durationMs'] as num).toInt()),
        estimatedDba: (json['estimatedDba'] as num).toDouble(),
      );
}

/// Service that tracks weekly sound exposure according to EU EN 62368-1 standards.
class SoundDoseTrackerService {
  final AudioEffectsChannel _effectsChannel;
  final List<DoseExposureSession> _sessions = [];

  static const double warningThresholdDose = 0.80; // 80% weekly dose warning
  static const double limitThresholdDose = 1.00; // 100% weekly dose reached

  SoundDoseTrackerService({AudioEffectsChannel? effectsChannel})
      : _effectsChannel = effectsChannel ?? AudioEffectsChannel();

  List<DoseExposureSession> get activeSessions {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    return _sessions.where((s) => s.timestamp.isAfter(cutoff)).toList();
  }

  /// Records an exposure session.
  void recordSession({
    required Duration duration,
    required double estimatedDba,
    DateTime? timestamp,
  }) {
    if (duration <= Duration.zero) return;
    _pruneOldSessions();
    _sessions.add(DoseExposureSession(
      timestamp: timestamp ?? DateTime.now(),
      duration: duration,
      estimatedDba: estimatedDba.clamp(40.0, 115.0),
    ));
  }

  /// Calculates total 7-day sound dose percentage (e.g. 85.5 for 85.5%).
  Future<double> getWeeklyDosePercent() async {
    _pruneOldSessions();
    double localDoseFraction = 0.0;
    for (final s in _sessions) {
      localDoseFraction += s.doseFraction;
    }

    // Sync with native dose tracker if native engine is active
    final nativeDose = await _effectsChannel.getWeeklyDose();
    final combined = math.max(localDoseFraction, nativeDose);
    return combined * 100.0;
  }

  /// Checks if listening session triggers an 80% or 100% sound safety warning.
  Future<String?> checkDoseWarning() async {
    final percent = await getWeeklyDosePercent();
    if (percent >= limitThresholdDose * 100.0) {
      return 'WEEKLY_DOSE_LIMIT_REACHED';
    }
    if (percent >= warningThresholdDose * 100.0) {
      return 'WEEKLY_DOSE_WARNING_80_PERCENT';
    }
    return null;
  }

  /// Resets sound dose tracking.
  Future<void> resetDose() async {
    _sessions.clear();
    await _effectsChannel.resetWeeklyDose();
  }

  void _pruneOldSessions() {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    _sessions.removeWhere((s) => s.timestamp.isBefore(cutoff));
  }
}
