// lib/domain/models/ytm_track.dart
import '../../data/db/app_database.dart';

/// A YouTube Music search result, before it has any row in the database.
class YtmTrack {
  final String videoId;
  final String title;
  final String artist;
  final Duration duration;
  final String? artworkUrl;

  const YtmTrack({
    required this.videoId,
    required this.title,
    required this.artist,
    required this.duration,
    this.artworkUrl,
  });

  /// The `songs.path` sentinel for this track. Nothing on disk backs it, so
  /// every path-derived feature has to skip rows whose source is not local.
  String get pathSentinel => 'ytmusic://$videoId';

  /// Deterministic negative primary key, so the same video always maps to the
  /// same row without a lookup. MediaStore ids are always positive, so the two
  /// id spaces cannot overlap.
  ///
  /// A video id carries 66 bits and this keeps 62, so a collision between two
  /// different videos is possible in principle; the insert path has to treat a
  /// primary-key conflict as "pick another id" rather than assume a duplicate.
  int get songId {
    var hash = 0xcbf29ce484222325; // FNV-1a 64-bit offset basis
    for (final unit in videoId.codeUnits) {
      hash ^= unit;
      hash *= 0x100000001b3; // FNV prime; Dart wraps on overflow
    }
    final magnitude = hash & 0x3FFFFFFFFFFFFFFF;
    return -(magnitude == 0 ? 1 : magnitude);
  }

  /// The in-memory `songs` row for this result. It is not persisted at search
  /// time, but has the exact shape a downloaded/streamed row would, so the same
  /// object drives [SongTile], playback, and the eventual insert. `albumId` /
  /// `artistId` stay null so album/artist browse never shows a phantom entry.
  SongsTableData toSongData() => SongsTableData(
        id: songId,
        title: title,
        artist: artist,
        album: '',
        durationMs: duration.inMilliseconds,
        path: pathSentinel,
        source: SongSource.youtube,
        remoteId: videoId,
        remoteArtworkUrl: artworkUrl,
        isFavorite: false,
        isMissing: false,
        isDownloaded: false,
        playCount: 0,
        lastPositionMs: 0,
      );

  Map<String, dynamic> toJson() => {
        'videoId': videoId,
        'title': title,
        'artist': artist,
        'durationMs': duration.inMilliseconds,
        'artworkUrl': artworkUrl,
      };

  factory YtmTrack.fromJson(Map<String, dynamic> json) => YtmTrack(
        videoId: json['videoId'] as String? ?? '',
        title: json['title'] as String? ?? 'Unknown Title',
        artist: json['artist'] as String? ?? 'Unknown Artist',
        duration:
            Duration(milliseconds: (json['durationMs'] as num?)?.toInt() ?? 0),
        artworkUrl: json['artworkUrl'] as String?,
      );

  static YtmTrack? fromChannel(Map<Object?, Object?> map) {
    final videoId = map['videoId'] as String?;
    final title = map['title'] as String?;
    if (videoId == null || videoId.isEmpty || title == null || title.isEmpty) {
      return null;
    }
    return YtmTrack(
      videoId: videoId,
      title: title,
      artist: (map['artist'] as String?)?.trim().isNotEmpty == true
          ? (map['artist'] as String).trim()
          : 'Unknown Artist',
      duration:
          Duration(milliseconds: (map['durationMs'] as num?)?.toInt() ?? 0),
      artworkUrl: (map['artworkUrl'] as String?)?.trim().isNotEmpty == true
          ? (map['artworkUrl'] as String).trim()
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is YtmTrack && other.videoId == videoId;

  @override
  int get hashCode => videoId.hashCode;

  @override
  String toString() => 'YtmTrack($videoId, $title, $artist)';
}

/// A resolved, directly playable audio URL. These expire within hours and are
/// bound to the requesting IP, so they must never be persisted.
class YtmStream {
  final String videoId;
  final String url;
  final String mimeType;

  /// File extension the stream would have on disk, e.g. `m4a`. Downloads can
  /// only be tagged when this is `m4a`.
  final String container;
  final int bitrateKbps;
  final Duration duration;
  final String title;
  final String artist;
  final String? artworkUrl;
  final String? userAgent;
  final String? cookies;
  final int? expiresAt;

  const YtmStream({
    required this.videoId,
    required this.url,
    required this.mimeType,
    required this.container,
    required this.bitrateKbps,
    required this.duration,
    required this.title,
    required this.artist,
    this.artworkUrl,
    this.userAgent,
    this.cookies,
    this.expiresAt,
  });

  bool get isTaggable => container == 'm4a';

  DateTime? get expiresAtDateTime =>
      expiresAt != null ? DateTime.fromMillisecondsSinceEpoch(expiresAt!) : null;

  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().millisecondsSinceEpoch >= expiresAt!;
  }

  bool isExpiringSoon([Duration threshold = const Duration(minutes: 5)]) {
    if (expiresAt == null) return false;
    final deadline = DateTime.fromMillisecondsSinceEpoch(expiresAt!);
    return DateTime.now().add(threshold).isAfter(deadline);
  }

  /// Epoch millis stamped on a googlevideo URL, or null if it carries no stamp.
  ///
  /// Every playable URL carries one, as `?expire=<epoch-seconds>` or as an
  /// `/expire/<epoch-seconds>/` path segment. Not every producer of a
  /// [YtmStream] fills [expiresAt] though — the NewPipe fallback path and the
  /// remote backend both omit it — and with it null `isExpired` and
  /// `isExpiringSoon` answer false forever, so a dead URL is served as fresh.
  static int? expiryFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      var raw = uri.queryParameters['expire'];
      if (raw == null) {
        final segments = uri.pathSegments;
        final index = segments.indexOf('expire');
        if (index >= 0 && index + 1 < segments.length) {
          raw = segments[index + 1];
        }
      }
      final epochSeconds = int.tryParse(raw ?? '');
      if (epochSeconds != null && epochSeconds > 0) {
        return epochSeconds * 1000;
      }
    } catch (_) {}
    return null;
  }

  /// This stream with a trustworthy [expiresAt].
  ///
  /// Not every producer fills it — the NewPipe fallback and the remote backend
  /// both omit it — and with it null, [isExpired] and [isExpiringSoon] answer
  /// false forever, so a dead URL is handed out as fresh and the download's
  /// proactive re-resolve never fires. A value that is plainly epoch *seconds*
  /// (anything before 1973 in millis) is scaled up rather than believed, since
  /// read as millis it would instead mark every stream permanently expired.
  YtmStream withResolvedExpiry() {
    var stamp = expiresAt;
    if (stamp != null && stamp > 0 && stamp < 100000000000) {
      stamp *= 1000;
    }
    stamp ??= expiryFromUrl(url);
    if (stamp == expiresAt) return this;
    return YtmStream(
      videoId: videoId,
      url: url,
      mimeType: mimeType,
      container: container,
      bitrateKbps: bitrateKbps,
      duration: duration,
      title: title,
      artist: artist,
      artworkUrl: artworkUrl,
      userAgent: userAgent,
      cookies: cookies,
      expiresAt: stamp,
    );
  }

  static YtmStream? fromChannel(Map<Object?, Object?> map) {
    final videoId = map['videoId'] as String?;
    final url = map['url'] as String?;
    if (videoId == null || url == null || url.isEmpty) return null;
    return YtmStream(
      videoId: videoId,
      url: url,
      mimeType: (map['mimeType'] as String?) ?? 'audio/mp4',
      container: (map['container'] as String?) ?? '',
      bitrateKbps: (map['bitrateKbps'] as num?)?.toInt() ?? 0,
      duration:
          Duration(milliseconds: (map['durationMs'] as num?)?.toInt() ?? 0),
      title: (map['title'] as String?) ?? '',
      artist: (map['artist'] as String?) ?? 'Unknown Artist',
      artworkUrl: (map['artworkUrl'] as String?)?.trim().isNotEmpty == true
          ? (map['artworkUrl'] as String).trim()
          : null,
      userAgent: map['userAgent'] as String?,
      cookies: map['cookies'] as String?,
      expiresAt: (map['expiresAt'] as num?)?.toInt() ?? expiryFromUrl(url),
      // The native side is free to send its stamp in either unit — NewPipe reads
      // `expire` straight off the URL, which is epoch *seconds*. Read as millis
      // that is January 1971, so every stream would be born expired and the URL
      // cache would refuse to store it.
    ).withResolvedExpiry();
  }

  @override
  String toString() => 'YtmStream($videoId, $container, ${bitrateKbps}kbps)';
}
