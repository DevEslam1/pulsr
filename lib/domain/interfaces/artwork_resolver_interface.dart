// lib/domain/interfaces/artwork_resolver_interface.dart
// FIX-A2: Dependency inversion interface for artwork caching and resolution
import 'dart:typed_data';

/// Contract for resolving, retrieving, and caching audio artwork bytes across
/// sources.
///
/// Failure semantics:
/// - [resolveArtwork] returns `null` when no artwork exists for the requested
///   key. "Not found" is modelled as `null`, never as a thrown exception.
///   Implementations may still throw for genuine I/O or platform faults and
///   callers must treat those as transport failures, not as "no artwork".
/// - [getCachedArtwork] returns `null` on a cache miss; it never throws.
///
/// Cache lifecycle & capacity:
/// - The in-memory cache is bounded (dual-tier strong LRU + weak references;
///   see ADR 004). Entries may be evicted at any time, so a `null` result is
///   not an error. The cache is not persisted across process restarts; use
///   [clearCache] to drop all in-memory entries (e.g. on low-memory pressure or
///   privacy sign-out).
abstract class IArtworkResolver {
  /// Resolves the raw artwork bytes for a local [songId] or [remoteArtworkUrl].
  ///
  /// Returns `null` when no artwork is found. May throw only for unexpected
  /// transport/platform failures.
  Future<Uint8List?> resolveArtwork(
      {required int songId, String? remoteArtworkUrl});

  /// Retrieves an in-memory cached artwork byte array if present, or `null`.
  Uint8List? getCachedArtwork(String key);

  /// Caches raw artwork [bytes] in memory identified by [key].
  void putCachedArtwork(String key, Uint8List bytes);

  /// Clears all in-memory cached artwork. Never throws.
  void clearCache();
}
