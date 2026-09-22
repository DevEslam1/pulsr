// lib/domain/interfaces/lyrics_provider_interface.dart
// FIX-A2: Dependency inversion interface for lyrics providers
import '../models/lyrics_line.dart';

/// Contract for fetching synchronized or plain lyrics from remote lyrics sources.
abstract class ILyricsProvider {
  /// Fetches lyrics matching [trackName], [artistName], and optional metadata.
  Future<LyricsResult?> fetchLyrics({
    required String trackName,
    required String artistName,
    String? albumName,
    int? durationSeconds,
  });
}
