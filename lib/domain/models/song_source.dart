// lib/domain/models/song_source.dart

/// Allowed values for song sources.
abstract final class SongSource {
  /// A file indexed by MediaStore. `path` points at the filesystem.
  static const String local = 'local';

  /// A YouTube track that has no local file yet. `path` holds a
  /// `ytmusic://<videoId>` sentinel, so any path-based feature must skip it.
  static const String youtube = 'youtube';

  /// A live internet radio HTTP / HTTPS stream. `path` holds the stream URL.
  static const String radio = 'radio';

  /// A finite file on a configured network library (SMB / WebDAV / FTP / SFTP)
  /// served to the player through the loopback proxy. `path` holds that
  /// loopback HTTP URL.
  ///
  /// Deliberately distinct from [radio]: the stream has a fixed length and
  /// supports byte ranges, so pause keeps its position, resume continues from
  /// that position and seeking works in both directions. It is also not local —
  /// there is no file on this device — so every path-derived action (tag edit,
  /// artwork extraction, scanner enrich, export) must skip it.
  static const String remote = 'remote';

  /// Every source whose bytes are fetched over the network at play time.
  /// Path-derived local-file features must skip all of them.
  static const Set<String> networkSources = <String>{youtube, radio, remote};

  /// Whether [source] is a live, unbounded stream (no stable position, no
  /// seeking). Only [radio] qualifies; a net-library file is finite.
  static bool isLive(String? source) => source == radio;

  /// Whether [source] is a network-backed source (no local file on disk).
  static bool isNetwork(String? source) =>
      source != null && networkSources.contains(source);

  /// Whether [source] is a file indexed on this device — the only source whose
  /// `path` can be opened directly by the filesystem/tag/artwork code.
  static bool hasLocalFile(String? source) => source == local;
}
