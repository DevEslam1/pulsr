import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import '../../data/audio/audio_effects_channel.dart';
import '../constants/prefs_keys.dart';

/// One read of the dose state, with everything the UI is allowed to claim.
class DoseSnapshot {
  /// Native 7-day rolling dose, where 1.0 == the EN 62368-1 reference of 40 h
  /// at 80 dBA. The native per-block accumulator is the only source of truth.
  final double weeklyDose;

  /// User budget as a fraction of that reference (0.25 .. 1.0).
  final double budget;

  /// True when the engine is attenuating because the budget is spent.
  final bool attenuationActive;

  const DoseSnapshot({
    required this.weeklyDose,
    required this.budget,
    required this.attenuationActive,
  });

  /// Fraction of the *budget* consumed, not of the reference: at a 25 % budget
  /// the limit lands after a quarter of the reference dose.
  double get usedFraction =>
      SoundDoseTrackerService.budgetUsedFraction(weeklyDose: weeklyDose, budget: budget);

  /// How long playback must stay off before the engine releases attenuation,
  /// or null when the limit is not currently engaged.
  Duration? get quietTimeUntilClear =>
      SoundDoseTrackerService.quietTimeUntilClear(weeklyDose: weeklyDose, budget: budget);
}

/// Weekly sound-dose budget.
///
/// The dose accumulator and the attenuation itself live in the native engine
/// (AudioDspEngine::processSafetyStage), which engages at
/// `headphoneSafety.doseThreshold` and fades over ~20 ms. This service does not
/// re-implement that model — it maps a user budget onto the same threshold, so
/// there is exactly one limiter deciding what the listener hears.
class SoundDoseTrackerService {
  final AudioEffectsChannel _effectsChannel;

  static const double minBudget = 0.25;
  static const double maxBudget = 1.0;
  static const double defaultBudget = 1.0;

  /// Selectable budgets, expressed as a fraction of the EN 62368-1 reference.
  static const List<double> budgetTiers = [0.25, 0.5, 0.75, 1.0];

  /// True-peak ceiling the engine holds while the limit is engaged. Kept here so
  /// the sheet and the fallback path cannot drift apart.
  static const double safetyCeilingDb = -6.0;

  /// The native stage releases at 95 % of its engagement threshold (hysteresis
  /// in AudioDspEngine::processSafetyStage), so the budget is not the point where
  /// sound comes back — this is.
  static const double releaseFraction = 0.95;

  /// Native 7-day rolling window: dose decays per block with
  /// `1 - frames / (604800 * sampleRate)`, i.e. exponentially with tau = 604800 s.
  static const double decayTauSeconds = 604800.0;

  SoundDoseTrackerService({AudioEffectsChannel? effectsChannel})
      : _effectsChannel = effectsChannel ?? AudioEffectsChannel();

  /// Snaps any stored or incoming value onto a supported tier. A budget of 0
  /// would silence output through the safety stage, and one above 1.0 would
  /// never engage, so both are refused rather than passed through.
  static double normalizeBudget(double raw) {
    if (!raw.isFinite) return defaultBudget;
    double best = budgetTiers.first;
    double bestDistance = double.infinity;
    for (final tier in budgetTiers) {
      final distance = (tier - raw).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = tier;
      }
    }
    return best;
  }

  static double budgetUsedFraction({
    required double weeklyDose,
    required double budget,
  }) {
    if (!weeklyDose.isFinite || weeklyDose <= 0.0) return 0.0;
    final safeBudget = normalizeBudget(budget);
    return (weeklyDose / safeBudget).clamp(0.0, 10.0);
  }

  static bool isLimitEngaged({
    required double weeklyDose,
    required double budget,
  }) =>
      weeklyDose.isFinite && weeklyDose >= normalizeBudget(budget);

  /// Time of silence needed for the native hysteresis to release, or null when
  /// nothing is engaged. Derived from the engine's own decay constant, so it
  /// describes the real behaviour rather than an optimistic guess.
  static Duration? quietTimeUntilClear({
    required double weeklyDose,
    required double budget,
  }) {
    final safeBudget = normalizeBudget(budget);
    final releaseAt = safeBudget * releaseFraction;
    if (!weeklyDose.isFinite || weeklyDose <= releaseAt) return null;
    final seconds = decayTauSeconds * math.log(weeklyDose / releaseAt);
    if (!seconds.isFinite || seconds <= 0.0) return null;
    return Duration(seconds: seconds.round());
  }

  double readPersistedBudget(SharedPreferences prefs) =>
      normalizeBudget(prefs.getDouble(PrefsKeys.audioDoseBudget) ?? defaultBudget);

  Future<void> applyBudget({
    required double budget,
    required bool safetyEnabled,
  }) async {
    final normalized = normalizeBudget(budget);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(PrefsKeys.audioDoseBudget, normalized);
    await _effectsChannel.setHeadphoneSafetyParams(
      enabled: safetyEnabled,
      doseThreshold: normalized,
      safetyCeilingDb: safetyCeilingDb,
    );
  }

  /// Re-applies the saved safety switch and budget to the native engine.
  ///
  /// The native defaults are "stage off, threshold 1.0", and the plugin's own
  /// fields reset every process, so without this the budget only exists while
  /// the safety sheet is open. [enabled] defaults to false to match the engine:
  /// it never silently turns protection on for someone who never chose it.
  Future<void> applyPersistedState() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(PrefsKeys.headphoneSafetyEnabled) ?? false;
    await _effectsChannel.setHeadphoneSafetyParams(
      enabled: enabled,
      doseThreshold: readPersistedBudget(prefs),
      safetyCeilingDb: safetyCeilingDb,
    );
  }

  Future<DoseSnapshot> read() async {
    final prefs = await SharedPreferences.getInstance();
    final budget = readPersistedBudget(prefs);
    final weeklyDose = await _effectsChannel.getWeeklyDose();
    final attenuationActive = await _effectsChannel.isSafetyAttenuationActive();
    return DoseSnapshot(
      weeklyDose: weeklyDose,
      budget: budget,
      attenuationActive: attenuationActive,
    );
  }

  Future<void> resetDose() async {
    await _effectsChannel.resetWeeklyDose();
  }
}
