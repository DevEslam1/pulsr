// lib/data/audio/player_telemetry_counters.dart
/// Lightweight in-memory telemetry counters for the audio player stack (Phase 6).
class PlayerTelemetryCounters {
  PlayerTelemetryCounters._();

  static int initStepsSkipped = 0;
  static int positionSaveFailures = 0;
  static int crossfadeCancels = 0;
  static int duckStateRecoveries = 0;

  static final Map<String, int> streamResolveFailures = {};
  static final Map<String, int> autoResumeDecisions = {};

  static void incrementStreamResolveFailure(String errorClass) {
    streamResolveFailures[errorClass] = (streamResolveFailures[errorClass] ?? 0) + 1;
  }

  static void recordAutoResumeDecision({required bool resumed, required String reason}) {
    final key = '${resumed ? "resumed" : "blocked"}:$reason';
    autoResumeDecisions[key] = (autoResumeDecisions[key] ?? 0) + 1;
  }

  static void resetForTesting() {
    initStepsSkipped = 0;
    positionSaveFailures = 0;
    crossfadeCancels = 0;
    duckStateRecoveries = 0;
    streamResolveFailures.clear;
    autoResumeDecisions.clear();
  }
}
