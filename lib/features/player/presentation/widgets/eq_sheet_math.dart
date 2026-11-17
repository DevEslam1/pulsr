// Pure maths behind the equalizer sheet.
//
// Everything in this file is a deterministic function of its arguments: no
// `BuildContext`, no `setState`, no timers, no widgets, no plugin channels.
// That is what makes the sheet's clamping, rounding and gain-staging
// arithmetic unit-testable without pumping a widget tree.
//
// The formulas are moved verbatim from `_EqualizerSheetState` and
// `_VerticalEqSliderState`; they must not be "improved". Clamp thresholds,
// rounding steps and branch order are part of the audible contract of the
// sheet, so any change here is a behaviour change.
import 'dart:math' as math;

/// Boost deltas at or below this are slider rounding noise, not a
/// GainStagingBudget clamp.
const double boostClampEpsilon = 0.01;

/// Why the custom center-frequency editor refused a band plan.
enum CenterFrequencyIssue {
  /// A field did not parse to a finite number.
  notANumber,

  /// A field fell outside 10 Hz..30 kHz.
  outOfRange,

  /// A field was not strictly above the one before it.
  notAscending,
}

/// Outcome of [EqSheetMath.parseCenterFrequencies]: either the parsed plan or
/// the first rule that rejected it.
class CenterFrequencyParseResult {
  /// Wraps an accepted plan.
  CenterFrequencyParseResult.valid(this.values) : issue = null;

  /// Wraps the first failing rule.
  CenterFrequencyParseResult.invalid(this.issue) : values = null;

  /// Parsed frequencies in band order, or null when rejected.
  final List<double>? values;

  /// The failing rule, or null when accepted.
  final CenterFrequencyIssue? issue;

  /// True when [values] is a usable plan.
  bool get isValid => issue == null;
}

/// Pure helpers shared by the equalizer sheet and its part files.
class EqSheetMath {
  const EqSheetMath._();

  // ---------------------------------------------------------------------------
  // Band plan
  // ---------------------------------------------------------------------------

  /// Band plan length derived from an emitted preset: only 32 and 64 survive,
  /// every other length (including 0 and the 10-band default) collapses to 10.
  ///
  /// Invariant: the result is always one of 10, 32 or 64, so callers can index
  /// a matching frequency list without a second guard.
  static int normalizedBandCount(int presetGainCount) =>
      (presetGainCount == 32 || presetGainCount == 64) ? presetGainCount : 10;

  /// Index of the band whose center frequency is nearest [targetHz].
  ///
  /// Invariant: always returns a usable index — `0` for an empty [freqs] (the
  /// caller clamps into its own gains list) and otherwise the index of the
  /// smallest absolute difference. Ties keep the lower index, because the scan
  /// only replaces the current best on a *strictly* smaller difference.
  static int findClosestBand(List<double> freqs, double targetHz) {
    if (freqs.isEmpty) return 0;
    int best = 0;
    double bestDiff = (freqs[0] - targetHz).abs();
    for (int i = 1; i < freqs.length; i++) {
      final diff = (freqs[i] - targetHz).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = i;
      }
    }
    return best;
  }

  /// Gain read by a macro dial: the gain of the band closest to [targetHz],
  /// clamped to +/-12 dB.
  ///
  /// Invariant: `0.0` for an empty [gains]; the index is clamped into [gains]
  /// so a frequency plan longer than the gains list cannot throw.
  static double macroGain(
    List<double> gains,
    List<double> freqs,
    double targetHz,
  ) {
    if (gains.isEmpty) return 0.0;
    final idx = findClosestBand(freqs, targetHz);
    return gains[idx.clamp(0, gains.length - 1)].clamp(-12.0, 12.0);
  }

  // ---------------------------------------------------------------------------
  // Formatting (labels and semantics values)
  // ---------------------------------------------------------------------------

  /// Trimmed frequency text: integers drop the decimal, everything else keeps
  /// exactly one (the custom-frequency editor's initial field text).
  static String formatFrequencyText(double hz) =>
      hz == hz.roundToDouble() ? hz.toStringAsFixed(0) : hz.toStringAsFixed(1);

  /// Band label in the sheet's `62` / `62.5` / `8K` / `8.5K` style.
  ///
  /// Invariant: below 1 kHz the label is [formatFrequencyText]; at or above it
  /// the value folds to kilo-hertz and keeps a decimal only when the kilo value
  /// is fractional. Non-finite input is deliberately unguarded — every caller
  /// passes a center frequency from the active band plan.
  static String formatHz(double hz) {
    if (hz >= 1000) {
      final k = hz / 1000.0;
      final s =
          k == k.roundToDouble() ? k.toStringAsFixed(0) : k.toStringAsFixed(1);
      return '${s}K';
    }
    return formatFrequencyText(hz);
  }

  /// Signed one-decimal dB label (`+3.5 dB`, `-12.0 dB`, `0.0 dB`).
  ///
  /// Invariant: the sign is emitted only for values strictly above zero, so
  /// zero reads as plain `0.0 dB` and negatives keep their own minus.
  static String formatGainDb(double gain) =>
      '${gain > 0 ? '+' : ''}${gain.toStringAsFixed(1)} dB';

  // ---------------------------------------------------------------------------
  // Gain staging
  // ---------------------------------------------------------------------------

  /// True when GainStagingBudget actually reduced the requested volume boost.
  ///
  /// Invariant: the comparison is strict, so a delta of exactly
  /// [boostClampEpsilon] is *not* a clamp — slider rounding noise must never
  /// raise the "boost was reduced" warning.
  static bool isBoostClamped({
    required double requestedBoost,
    required double effectiveBoost,
  }) =>
      requestedBoost - effectiveBoost > boostClampEpsilon;

  /// Largest band gain, or `0.0` for an empty plan.
  ///
  /// Invariant: an all-cut curve stays negative (this mirrors
  /// `gains.reduce((a, b) => a > b ? a : b)`, it does not fold to zero), which
  /// is what the clip-risk estimate relies on.
  static double peakGain(List<double> gains) =>
      gains.isEmpty ? 0.0 : gains.reduce((a, b) => a > b ? a : b);

  /// Preamp that cancels the largest positive boost, or `0.0` when the curve
  /// boosts nothing.
  ///
  /// Invariant: the scan is seeded at `0.0`, so a curve made only of cuts
  /// returns `0.0` (no attenuation) rather than the largest negative gain.
  static double autoPreampFor(List<double> gains) {
    double maxBoost = 0.0;
    for (final g in gains) {
      if (g > maxBoost) maxBoost = g;
    }
    return maxBoost > 0.0 ? -maxBoost : 0.0;
  }

  /// Automatic preamp headroom shown next to the manual preamp.
  ///
  /// Invariant: `0.0` unless the EQ is enabled *and* some band boosts by more
  /// than 1.5 dB; when engaged the result lies in -6.0..0.0 dB. The blend is
  /// 65% peak + 35% RMS of the positive bands, so a broad boost is trimmed
  /// less aggressively than a single narrow spike.
  static double autoHeadroomDb(
    List<double> gains, {
    required bool isEqEnabled,
  }) {
    final maxBoost = peakGain(gains);
    if (!isEqEnabled || maxBoost <= 1.5) return 0.0;
    double sumPosSq = 0.0;
    int posCount = 0;
    for (final g in gains) {
      if (g > 0.0) {
        sumPosSq += g * g;
        posCount++;
      }
    }
    final rmsBoost = posCount > 0 ? math.sqrt(sumPosSq / posCount) : maxBoost;
    final effectiveBoost = 0.65 * maxBoost + 0.35 * rmsBoost;
    return -((effectiveBoost - 1.5) * 0.55).clamp(0.0, 6.0);
  }

  /// True when the manual preamp plus the peak boost plus the automatic
  /// headroom land above 0 dBFS, i.e. the sheet should warn about clipping.
  static bool hasClipRisk({
    required double preampDb,
    required List<double> gains,
    required bool isEqEnabled,
  }) =>
      preampDb +
          peakGain(gains) +
          autoHeadroomDb(gains, isEqEnabled: isEqEnabled) >
      0.0;

  /// Haptic tick index for a macro dial: one step per 0.5 dB across the
  /// -12..+12 dB range (0..48), so a drag fires a single haptic per step.
  static int hapticStepFor(double value) => ((value + 12.0) * 2).round();

  // ---------------------------------------------------------------------------
  // Macro-dial weighting (non-10-band plans)
  // ---------------------------------------------------------------------------

  /// Shelf weight applied to the bass macro at [hz]: 1.0 at DC tapering to a
  /// 0.2 floor at 280 Hz. Callers gate on `hz <= 250`.
  static double bassMacroWeight(double hz) =>
      (1.0 - (hz / 280.0)).clamp(0.2, 1.0);

  /// Bell weight applied to the mid macro at [hz]: 1.0 at 1 kHz falling by 0.5
  /// per octave to a 0.3 floor. Callers gate on 250 Hz..3.5 kHz.
  static double midMacroWeight(double hz) {
    final octDist = (math.log(hz / 1000.0) / math.ln2).abs();
    return (1.0 - (octDist / 2.0)).clamp(0.3, 1.0);
  }

  /// Shelf weight applied to the treble macro at [hz]: 0.4 floor at 3 kHz
  /// rising linearly to 1.0 at 13 kHz. Callers gate on `hz >= 3.5 kHz`.
  static double trebleMacroWeight(double hz) =>
      ((hz - 3000.0) / 10000.0).clamp(0.4, 1.0);

  // ---------------------------------------------------------------------------
  // Vertical band slider
  // ---------------------------------------------------------------------------

  /// One-decimal-quantised gain — the value pushed to the native engine.
  static double roundGain(double gain) => double.parse(gain.toStringAsFixed(1));

  /// Gain for a vertical drag at [localY] inside a track [totalHeight] tall.
  ///
  /// Invariant: returns null when the track collapses (`totalHeight` at or
  /// below the two 12 px margins) so the caller can ignore the gesture;
  /// otherwise the fraction is measured from the bottom, clamped to the track,
  /// mapped onto [min]..[max] and quantised via [roundGain].
  static double? gainFromPointerY(
    double localY,
    double totalHeight, {
    required double min,
    required double max,
    double topMargin = 12.0,
    double bottomMargin = 12.0,
  }) {
    final trackHeight = totalHeight - topMargin - bottomMargin;
    if (trackHeight <= 0) return null;
    final clampedY = (localY - topMargin).clamp(0.0, trackHeight);
    final fraction = 1.0 - (clampedY / trackHeight);
    final newGain = min + fraction * (max - min);
    return roundGain(newGain);
  }

  /// Gain after a semantic +-1 dB step: clamped to [min]..[max], then
  /// quantised to one decimal.
  static double adjustedGain(
    double gain,
    double delta, {
    required double min,
    required double max,
  }) =>
      roundGain((gain + delta).clamp(min, max));

  /// Gain clamped to [min]..[max] *without* quantisation — the value used for
  /// the next semantic increase/decrease step.
  static double clampGain(
    double gain, {
    required double min,
    required double max,
  }) =>
      gain.clamp(min, max);

  // ---------------------------------------------------------------------------
  // Custom center frequencies
  // ---------------------------------------------------------------------------

  /// Validates the custom-center-frequency editor: every field must parse to a
  /// finite number in 10..30000 Hz and the plan must ascend strictly.
  ///
  /// Invariant: the whole plan is rejected on the FIRST failing rule in the
  /// order the dialog reports it — a non-numeric field anywhere wins over any
  /// range/order problem, then the lowest-index range violation, then the
  /// lowest-index ordering violation.
  static CenterFrequencyParseResult parseCenterFrequencies(
    List<String> texts,
  ) {
    final parsed = <double>[];
    for (final text in texts) {
      final v = double.tryParse(text);
      if (v == null || !v.isFinite) {
        return CenterFrequencyParseResult.invalid(
          CenterFrequencyIssue.notANumber,
        );
      }
      parsed.add(v);
    }
    for (var i = 0; i < parsed.length; i++) {
      if (parsed[i] < 10 || parsed[i] > 30000) {
        return CenterFrequencyParseResult.invalid(
          CenterFrequencyIssue.outOfRange,
        );
      }
      if (i > 0 && parsed[i] <= parsed[i - 1]) {
        return CenterFrequencyParseResult.invalid(
          CenterFrequencyIssue.notAscending,
        );
      }
    }
    return CenterFrequencyParseResult.valid(parsed);
  }
}
