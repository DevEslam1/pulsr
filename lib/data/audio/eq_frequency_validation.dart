// lib/data/audio/eq_frequency_validation.dart

/// Pure validation for user-supplied EQ center-frequency tables.
///
/// Returns true only when [frequencies] contains exactly [expectedLength]
/// entries and every entry is finite and strictly positive. Kept free of any
/// [EqualizerManager] instance state so all band plans (10/32/64) share one
/// definition of a valid frequency table.
bool isValidCustomFrequencyList(
  List<double> frequencies,
  int expectedLength,
) {
  if (frequencies.length != expectedLength) return false;
  for (final f in frequencies) {
    if (!f.isFinite || f <= 0) return false;
  }
  return true;
}
