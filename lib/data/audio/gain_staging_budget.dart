// lib/data/audio/gain_staging_budget.dart

/// One gain stage's contribution to the output level, in dB. Positive values
/// are boosts that consume headroom; negative values (e.g. a negative AutoEQ
/// preamp) hand headroom back to the budget.
class GainStage {
  final String label;
  final double gainDb;
  const GainStage(this.label, this.gainDb);
}

/// Pure gain-staging / clipping-budget calculator.
///
/// Generalises the single-stage clipping cap in [ReplayGainMath.apply] — which
/// limits ONE gain multiplier so (volume x gain x peak) stays under an
/// inter-sample headroom ceiling — to the WHOLE DSP chain. Every active boost
/// stage (EQ preamp, ReplayGain preamp, bass boost, volume boost, loudness
/// contour, saturation, dynamic bass, sub-crossover, …) is summed in dB and the
/// sum is held at or below a shared [defaultHeadroomCeilingDb]. A boost setter
/// asks for the budget still available and clamps its request to it, so
/// stacking effects can never push the composite gain into clipping — the flaw
/// in the old volume-boost check, which only budgeted the headphone preamp.
class GainStagingBudget {
  const GainStagingBudget._();

  /// Shared output headroom ceiling (dB). Mirrors the +6 dB cap that was
  /// previously hard-coded inside the volume-boost setter.
  static const double defaultHeadroomCeilingDb = 6.0;

  // Conservative worst-case boosts (dB) attributed to an *enabled* stage whose
  // exact runtime gain cannot be read back. Deliberately on the high side so
  // the budget errs toward clamping, never toward clipping ("unknown ⇒ max").
  // The native broadband/bass boosts are hard-capped at 1000 mB = 10 dB.
  static const double maxBassBoostDb = 10.0;
  static const double maxVolumeBoostDb = 10.0;
  static const double maxLoudnessContourDb = 6.0;
  static const double maxSaturationDb = 3.0;
  static const double maxDynamicBassDb = 6.0;
  static const double maxSubCrossoverDb = 6.0;

  /// Net committed gain (dB) across [stages]; non-finite stages are ignored.
  static double totalGainDb(Iterable<GainStage> stages) {
    var sum = 0.0;
    for (final s in stages) {
      if (s.gainDb.isFinite) sum += s.gainDb;
    }
    return sum;
  }

  /// Boost (dB) still available for a new/adjusted stage given the gains
  /// already committed by [committedStages]. Never negative.
  static double remainingBudgetDb(
    Iterable<GainStage> committedStages, {
    double headroomCeilingDb = defaultHeadroomCeilingDb,
  }) {
    final remaining = headroomCeilingDb - totalGainDb(committedStages);
    return remaining.isFinite && remaining > 0.0 ? remaining : 0.0;
  }

  /// Clamps a positive [requestedBoostDb] so the composite chain stays within
  /// [headroomCeilingDb]. Non-positive / non-finite requests resolve to 0.
  static double clampBoostDb({
    required double requestedBoostDb,
    required Iterable<GainStage> committedStages,
    double headroomCeilingDb = defaultHeadroomCeilingDb,
  }) {
    if (!requestedBoostDb.isFinite || requestedBoostDb <= 0.0) return 0.0;
    final budget = remainingBudgetDb(
      committedStages,
      headroomCeilingDb: headroomCeilingDb,
    );
    return requestedBoostDb <= budget ? requestedBoostDb : budget;
  }

  /// Builds a stage contributing [maxDb] scaled by a normalized [intensity]
  /// (0..1). A disabled stage contributes 0; a null / non-finite intensity
  /// assumes the full [maxDb] — the conservative "unknown ⇒ max" default.
  static GainStage scaledStage(
    String label, {
    required bool enabled,
    required double maxDb,
    double? intensity,
  }) {
    if (!enabled) return GainStage(label, 0.0);
    final factor = (intensity == null || !intensity.isFinite)
        ? 1.0
        : intensity.clamp(0.0, 1.0).toDouble();
    return GainStage(label, maxDb * factor);
  }
}
