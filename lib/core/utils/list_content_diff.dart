// lib/core/utils/list_content_diff.dart
//
// O(1) "did this list's content visibly change?" check for Bloc buildWhen
// gates on freezed states.
//
// WHY THIS EXISTS: freezed 3.2 `copyWith` does not preserve list reference
// identity â€” even a no-argument `state.copyWith()` returns a state whose
// `@Default([])` list fields are NEW instances (verified by
// test/tmp_gate_probe_test.dart). Therefore `!identical(a.list, b.list)` is
// always true after any copyWith, which silently defeats every identity-based
// buildWhen and causes full-screen rebuilds on high-frequency ticks.
//
// Semantics: length catches append/remove/clear; first/last catches replace-all
// with different content. Known accepted miss: a same-length reorder whose
// first AND last elements are unchanged (rare; consumers that need exact order
// watch their own dedicated state slices).
bool listContentDiffers<T>(Iterable<T> a, Iterable<T> b) {
  if (identical(a, b)) return false;
  if (a.length != b.length) return true;
  if (a.isEmpty) return false;
  return a.first != b.first || a.last != b.last;
}
