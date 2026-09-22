// lib/domain/interfaces/artwork_resolver_interface.dart
// FIX-A2: Dependency inversion interface for artwork caching and resolution
import 'dart:typed_data';

/// Contract for resolving, retrieving, and caching audio artwork bytes across sources.
abstract class IArtworkResolver {
  /// Resolves the raw artwork bytes for a local [songId] or [remoteArtworkUrl].
  Future<Uint8List?> resolveArtwork({required int songId, String? remoteArtworkUrl});

  /// Retrieves an in-memory cached artwork byte array if present, or null.
  Uint8List? getCachedArtwork(String key);

  /// Caches raw artwork [bytes] in memory identified by [key].
  void putCachedArtwork(String key, Uint8List bytes);

  /// Clears all in-memory cached artwork.
  void clearCache();
}
