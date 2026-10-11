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
  /// Hosts that resolve to localhost / link-local / private ranges are also
  /// rejected so a station can never be pointed at the device or its network.
  static bool isHttpUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return false;
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    final host = uri.host;
    if (host.isEmpty) return false;
    return !_isUnsafeHost(host);
  }

  /// Rejects loopback, link-local, unique-local, unspecified, CGNAT and
  /// RFC 1918 hosts, including IPv4 addresses embedded in IPv6 mapped
  /// (`::ffff:192.168.1.1`, `::ffff:7f00:1`) or compatible forms.
  static bool _isUnsafeHost(String host) {
    final lower = host.toLowerCase();
    if (lower == 'localhost' || lower.endsWith('.local')) return true;

    if (lower.contains(':')) {
      const loopbacks = {'::', '::1', '0:0:0:0:0:0:0:0', '0:0:0:0:0:0:0:1'};
      if (loopbacks.contains(lower)) return true;
      final embedded = _embeddedIpv4(lower);
      if (embedded != null) return _isUnsafeIpv4(embedded);
      final firstGroup = lower.split(':').first;
      final value = int.tryParse(firstGroup, radix: 16);
      if (value != null) {
        // fc00::/7 (unique local) and fe80::/10 (link-local)
        if ((value & 0xfe00) == 0xfc00) return true;
        if ((value & 0xffc0) == 0xfe80) return true;
      }
      return false;
    }

    return _isUnsafeIpv4(lower);
  }

  /// Extracts the embedded IPv4 address from an IPv6 mapped/compatible host
  /// (`::ffff:a.b.c.d`, `::ffff:hhhh:hhhh`, `::a.b.c.d`) or returns null when
  /// the host is a genuine IPv6 address.
  static String? _embeddedIpv4(String lower) {
    final groups = lower.split(':');
    var marker = -1;
    for (var i = 0; i < groups.length; i++) {
      if (groups[i] == 'ffff') {
        marker = i;
        break;
      }
    }
    final prefixEnd = marker == -1 ? groups.length - 1 : marker;
    for (var i = 0; i < prefixEnd; i++) {
      final group = groups[i];
      if (group.isNotEmpty && int.tryParse(group, radix: 16) != 0) return null;
    }
    final rest = groups.sublist(marker == -1 ? groups.length - 1 : marker + 1);
    if (rest.length == 1) {
      return rest.first.contains('.') ? rest.first : null;
    }
    if (rest.length != 2) return null;
    final high = int.tryParse(rest[0].padLeft(4, '0'), radix: 16);
    final low = int.tryParse(rest[1].padLeft(4, '0'), radix: 16);
    if (high == null || low == null || high > 0xffff || low > 0xffff) {
      return null;
    }
    return '${(high >> 8) & 0xff}.${high & 0xff}.${(low >> 8) & 0xff}.${low & 0xff}';
  }

  static bool _isUnsafeIpv4(String host) {
    final parts = host.split('.');
    if (parts.length != 4) return false;
    final octets = <int>[];
    for (final part in parts) {
      final value = int.tryParse(part);
      if (value == null || value < 0 || value > 255) return false;
      octets.add(value);
    }
    final a = octets[0];
    final b = octets[1];
    if (a == 0) return true; // 0.0.0.0/8 (unspecified)
    if (a == 127) return true; // 127.0.0.0/8
    if (a == 10) return true; // 10.0.0.0/8
    if (a == 172 && b >= 16 && b <= 31) return true; // 172.16.0.0/12
    if (a == 192 && b == 168) return true; // 192.168.0.0/16
    if (a == 169 && b == 254) return true; // 169.254.0.0/16
    if (a == 100 && b >= 64 && b <= 127) return true; // 100.64.0.0/10 (CGNAT)
    return false;
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
