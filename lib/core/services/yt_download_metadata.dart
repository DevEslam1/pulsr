// lib/core/services/yt_download_metadata.dart
import 'package:drift/drift.dart' show Value;

import '../../data/db/app_database.dart';
import '../../domain/models/ytm_track.dart';
import '../utils/error_logger.dart';
import '../utils/metadata_placeholders.dart';

/// Repairs a queued download's metadata from the resolved stream.
///
/// A search/browse row can carry placeholder metadata even though the stream
/// resolver already knows the real author and title. Using that answer keeps
/// tags, the saved file name, the library fallback and the download tile out of
/// "Unknown Artist" territory.
class YtDownloadMetadataResolver {
  static SongsTableData resolve(SongsTableData song, YtmStream stream) {
    var effective = song;
    var changed = false;

    final streamTitle = stream.title.trim();
    final streamArtist = stream.artist.trim();

    if (MetadataPlaceholders.isUnknownTitle(effective.title) &&
        MetadataPlaceholders.isRealTitle(streamTitle)) {
      effective = effective.copyWith(title: streamTitle);
      changed = true;
    }
    if (MetadataPlaceholders.isUnknownArtist(effective.artist) &&
        MetadataPlaceholders.isRealArtist(streamArtist)) {
      effective = effective.copyWith(artist: streamArtist);
      changed = true;
    }
    if (effective.durationMs <= 0 && stream.duration.inMilliseconds > 0) {
      effective =
          effective.copyWith(durationMs: stream.duration.inMilliseconds);
      changed = true;
    }
    final streamArt = (stream.artworkUrl ?? '').trim();
    if ((effective.remoteArtworkUrl ?? '').trim().isEmpty &&
        streamArt.isNotEmpty) {
      effective = effective.copyWith(remoteArtworkUrl: Value(streamArt));
      changed = true;
    }
    if (changed) {
      ErrorLogger.addBreadcrumb(
        'Download metadata recovered from stream: ${song.remoteId}',
        category: 'download',
        data: {'artist': effective.artist, 'title': effective.title},
      );
    }
    return effective;
  }
}
