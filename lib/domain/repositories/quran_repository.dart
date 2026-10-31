import '../models/quran_metadata.dart';
import '../models/quran_surah.dart';

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

  /// Persists a Quran bookmark. Throws if storage rejects the write.
  Future<void> saveBookmark(QuranBookmark bookmark);

  /// Clears the Quran bookmark for a track. Throws if storage rejects deletion.
  Future<void> clearBookmark(String trackUri);

  /// Returns all persisted Quran bookmarks.
  Future<List<QuranBookmark>> getAllBookmarks();

  /// Returns the canonical catalog of all 114 Surahs.
  List<QuranSurah> getSurahs();

  /// Returns canonical information for a specific Surah by number (1..114).
  QuranSurah? getSurah(int surahNumber);

  /// Returns canonical list of renowned reciters across Riwayahs.
  List<QuranReciter> getReciters();

  /// Returns verified verse texts for a given Surah.
  List<QuranAyahText> getAyahsForSurah(int surahNumber);
}
