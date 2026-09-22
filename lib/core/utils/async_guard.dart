// lib/core/utils/async_guard.dart

/// Lightweight generation counter to guard asynchronous operations against
/// stale completions and races.
class AsyncGuard {
  int _gen = 0;

  /// Advances the generation and returns the new token.
  int next() => ++_gen;

  /// True if [gen] matches the current active generation.
  bool isValid(int gen) => gen == _gen;

  /// Invalidates all in-flight tokens by bumping the generation.
  void invalidate() => _gen++;

  /// The current generation token.
  int get currentGen => _gen;
}
