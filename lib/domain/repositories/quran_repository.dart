// lib/domain/repositories/quran_repository.dart
import '../models/quran_metadata.dart';

/// Clean interface for Quran catalog and bookmarks.
///
/// If no verified Quran metadata is attached to a track, methods return null
/// rather than guessing or inventing metadata from file names, ensuring pure
/// isolation between ordinary music and Quran mode.
abstract class QuranRepository {
  /// Returns verified Quran metadata for the specified track URI, or null if none exists.
  Future<QuranMetadata?> getMetadataForTrack(String trackUri);

  /// Saves or updates Quran metadata for a track.
  Future<void> saveMetadataForTrack(String trackUri, QuranMetadata metadata);

  /// Removes Quran metadata for a track.
  Future<void> removeMetadataForTrack(String trackUri);

  /// Returns the Quran bookmark for a track, or null if unset.
  Future<QuranBookmark?> getBookmark(String trackUri);

  /// Persists a Quran bookmark.
  Future<void> saveBookmark(QuranBookmark bookmark);

  /// Clears the Quran bookmark for a track.
  Future<void> clearBookmark(String trackUri);

  /// Returns all persisted Quran bookmarks.
  Future<List<QuranBookmark>> getAllBookmarks();
}
