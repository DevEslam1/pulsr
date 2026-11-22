// lib/core/utils/track_display_info.dart
import '../../data/db/app_database.dart';
import 'metadata_placeholders.dart';

/// Clean UI representation for a track's title and artist.
///
/// Implements smart `Artist - Title` fallback: when a track's ID3 `artist`
/// metadata is empty or `"Unknown Artist"` and the title contains `" - "`
/// (e.g., `"Mohamed Hamaki - Bahareya"`), parses and displays the song title
/// (`Bahareya`) and artist (`Mohamed Hamaki`) cleanly in the UI without mutating
/// the underlying entity/file.
class TrackDisplayInfo {
  final String title;
  final String artist;

  const TrackDisplayInfo({
    required this.title,
    required this.artist,
  });

  /// Resolves the displayed title and artist.
  factory TrackDisplayInfo.resolve({
    required String rawTitle,
    required String? rawArtist,
  }) {
    final cleanArtist = rawArtist?.trim() ?? '';
    final isArtistUnknown = cleanArtist.isEmpty ||
        cleanArtist.toLowerCase() == 'unknown artist' ||
        cleanArtist.toLowerCase() == '<unknown>' ||
        MetadataPlaceholders.isUnknownArtist(cleanArtist);

    if (isArtistUnknown && rawTitle.contains(' - ')) {
      final sepIndex = rawTitle.indexOf(' - ');
      final parsedArtist = rawTitle.substring(0, sepIndex).trim();
      final parsedTitle = rawTitle.substring(sepIndex + 3).trim();

      if (parsedArtist.isNotEmpty && parsedTitle.isNotEmpty) {
        return TrackDisplayInfo(
          title: parsedTitle,
          artist: parsedArtist,
        );
      }
    }

    return TrackDisplayInfo(
      title: rawTitle,
      artist: rawArtist ?? '',
    );
  }

  /// Convenience factory from [SongsTableData].
  factory TrackDisplayInfo.fromSong(SongsTableData song) {
    return TrackDisplayInfo.resolve(
      rawTitle: song.title,
      rawArtist: song.artist,
    );
  }
}
