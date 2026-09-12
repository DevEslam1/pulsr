// lib/core/utils/song_classification.dart
import '../../data/db/app_database.dart';

/// Single source of truth for splitting favorites/downloads into Local vs
/// Online buckets. Previously the Library favorites tab and the standalone
/// `/favorites` screen each had their own (diverging) predicate.

/// True when a favorite belongs in the "Online" bucket: a streaming YouTube
/// row with no local file on disk. A downloaded YouTube track (real local
/// path or `content:` URI) stays Local because it plays offline.
bool isOnlineFavorite(SongsTableData s) {
  if (s.source == SongSource.youtube) {
    final hasLocalFile = s.path.isNotEmpty &&
        !s.path.startsWith('ytmusic://') &&
        (s.path.startsWith('content:') || s.isDownloaded == true);
    return !hasLocalFile;
  }
  return s.remoteId != null && s.remoteId!.isNotEmpty;
}

/// True when a local song originated from an online download (used by the
/// Library "Downloaded" tab). Streaming `ytmusic://` sentinels are excluded.
bool isDownloadedOnlineTrack(SongsTableData s) {
  if (s.path.isEmpty || s.path.startsWith('ytmusic://')) return false;
  if (s.isDownloaded == true) return true;
  return s.source == SongSource.local &&
      s.remoteId != null &&
      s.remoteId!.isNotEmpty;
}
