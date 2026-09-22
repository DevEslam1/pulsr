// lib/data/audio/async_lock.dart
// Serialized async execution primitive. Extracted from equalizer_manager.dart
// (fat-file decomposition, gap 01-4) — zero behavior change.

/// Simple async lock for serializing concurrent effect state changes.
/// Prevents race conditions when multiple effects are toggled rapidly.
class AsyncLock {
  Future<void> _chain = Future<void>.value();

  Future<T> lock<T>(Future<T> Function() fn) {
    final future = _chain.then((_) => fn());
    // Chain the next operation to maintain serialization even if this one
    // fails. `whenComplete` rethrows the error into `_chain`, which would poison
    // every later `lock` call; swallow it on the chain while still surfacing it
    // to the caller via the returned future.
    _chain = future.then<void>((_) {}, onError: (Object _) {});
    return future;
  }
}
