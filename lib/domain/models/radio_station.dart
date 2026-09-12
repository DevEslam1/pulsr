// lib/domain/models/radio_station.dart

/// A persisted internet radio / HTTP stream the user can play from the
/// Radio screen. Stations are not files: [url] is an absolute
/// `http(s)://` stream (progressive Icecast/Shoutcast or HLS `.m3u8`).
class RadioStation {
  final String id;
  final String name;
  final String url;
  final String? genre;
  final String? artworkUrl;
  final int? lastPlayed;

  const RadioStation({
    required this.id,
    required this.name,
    required this.url,
    this.genre,
    this.artworkUrl,
    this.lastPlayed,
  });

  /// Builds a station, deriving a stable [id] from [url] so re-adding the
  /// same stream replaces (rather than duplicates) the entry.
  factory RadioStation.create({
    required String name,
    required String url,
    String? genre,
    String? artworkUrl,
    int? lastPlayed,
  }) {
    final normalizedUrl = url.trim();
    final normalizedName =
        name.trim().isEmpty ? _fallbackName(normalizedUrl) : name.trim();
    String? normalizedGenre;
    if (genre != null && genre.trim().isNotEmpty) {
      normalizedGenre = genre.trim();
    }
    return RadioStation(
      id: stationIdForUrl(normalizedUrl),
      name: normalizedName,
      url: normalizedUrl,
      genre: normalizedGenre,
      artworkUrl: artworkUrl,
      lastPlayed: lastPlayed,
    );
  }

  factory RadioStation.fromJson(Map<String, dynamic> json) {
    return RadioStation(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      url: json['url'] as String? ?? '',
      genre: json['genre'] as String?,
      artworkUrl: json['artworkUrl'] as String?,
      lastPlayed: (json['lastPlayed'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'genre': genre,
        'artworkUrl': artworkUrl,
        'lastPlayed': lastPlayed,
      };

  RadioStation copyWith({
    String? name,
    String? url,
    String? genre,
    String? artworkUrl,
    int? lastPlayed,
  }) {
    return RadioStation(
      id: id,
      name: name ?? this.name,
      url: url ?? this.url,
      genre: genre ?? this.genre,
      artworkUrl: artworkUrl ?? this.artworkUrl,
      lastPlayed: lastPlayed ?? this.lastPlayed,
    );
  }

  /// Negative pseudo-song id used when this station is played through the
  /// normal queue. Always `< 0`, so repository cleanup and play-history never
  /// treat it as a real local file.
  int get songId {
    final parsed = int.tryParse(id, radix: 16);
    final hash = parsed ?? _fnv1a(url);
    return -((hash & 0x7fffffff) + 1);
  }

  /// A stable, deterministic id for [url]. FNV-1a keeps the id reproducible
  /// across processes (unlike `String.hashCode`, which is allowed to vary).
  static String stationIdForUrl(String url) {
    return _fnv1a(url.trim().toLowerCase()).toRadixString(16);
  }

  /// True only for absolute `http://` / `https://` URLs with a host.
  /// Local files, relative paths and `ytmusic://` sentinels are rejected.
  static bool isHttpUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return false;
    return (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  static String _fallbackName(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null && uri.host.isNotEmpty) return uri.host;
    return url;
  }

  static int _fnv1a(String input) {
    var hash = 0x811c9dc5;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash;
  }
}
