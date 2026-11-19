// lib/domain/models/remote_source.dart
//
// P0-1 "remote sources": the persisted description of a network music library
// (WebDAV / FTP / SMB / Subsonic / UPnP) plus one directory entry inside it.
//
// Pure Dart (no Flutter, no plugins) so the model is unit-testable without a
// binding. Secrets are deliberately absent: the password lives in
// RemoteCredentialsStore under the source id, and [RemoteSource] never carries
// a credential slot of its own (an old `credentialKey` field was never read by
// the store and has been removed).
import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Transport family of a [RemoteSource].
enum RemoteSourceKind {
  /// WebDAV over HTTP(S), browsed with PROPFIND / GET.
  webdav(wireName: 'webdav', defaultPort: 443, requiresRootShare: false),

  /// Plain FTP, browsed with a passive-mode control connection.
  ftp(wireName: 'ftp', defaultPort: 21, requiresRootShare: false),

  /// SMB2/3 (Windows file sharing), served by the native Android plugin.
  smb(wireName: 'smb', defaultPort: 445, requiresRootShare: true),

  /// Navidrome / Subsonic / Airsonic, browsed through the JSON API.
  subsonic(wireName: 'subsonic', defaultPort: 443, requiresRootShare: false),

  /// A DLNA media server found over SSDP.
  ///
  /// Discovered rather than typed in by hand (see [isDiscovered]); for this
  /// kind [RemoteSource.rootPath] carries the ContentDirectory control path,
  /// because a UPnP library has no filesystem root and its tree is addressed
  /// by object ids. [RemoteSource.host], [port] and [useTls] describe that
  /// control endpoint the same way they do for WebDAV.
  upnp(wireName: 'upnp', defaultPort: 80, requiresRootShare: false);

  const RemoteSourceKind({
    required this.wireName,
    required this.defaultPort,
    required this.requiresRootShare,
  });

  /// Stable token used in JSON. Never rename: persisted files depend on it.
  final String wireName;

  /// Port pre-filled by the editor for a new source of this kind.
  final int defaultPort;

  /// Whether [RemoteSource.rootPath] must name a share (SMB) rather than a
  /// directory tree (WebDAV / FTP).
  final bool requiresRootShare;

  /// Whether the add/edit form can create a source of this kind by hand.
  ///
  /// UPnP libraries are discovered over SSDP: their control URL cannot be
  /// typed in, so the editor omits this kind while the discovered record is
  /// still persisted and browsable.
  bool get isDiscovered => this == RemoteSourceKind.upnp;

  /// Parses a [wireName] token, returning `null` for anything unknown so a
  /// store can skip a corrupted entry instead of failing the whole load.
  static RemoteSourceKind? tryParse(Object? raw) {
    if (raw is! String) return null;
    final normalized = raw.trim().toLowerCase();
    for (final kind in values) {
      if (kind.wireName == normalized) return kind;
    }
    return null;
  }
}

/// One configured remote library.
///
/// [rootPath] is normalized to a leading slash with no trailing slash
/// (`'/'` means "the server root"); SMB sources use it as `/<share>/<subdir>`.
/// Paths handed to a provider are relative to that root, so `''` is the root
/// directory itself.
class RemoteSource {
  /// Creates a source from already-validated values.
  ///
  /// Prefer [RemoteSource.create] when the values come from user input: it
  /// normalizes the host/root and rejects an invalid port.
  RemoteSource({
    required this.id,
    required this.kind,
    required this.displayName,
    required this.host,
    required this.port,
    required this.createdAt,
    String rootPath = '/',
    this.useTls = false,
    this.username,
  }) : rootPath = normalizeRootPath(rootPath);

  /// Builds a source from raw editor input, normalizing the host and root.
  ///
  /// Throws [ArgumentError] when the host is empty or the port is outside
  /// `1..65535`. A missing [id] is derived from the endpoint, so re-adding the
  /// same library replaces the existing entry instead of duplicating it.
  factory RemoteSource.create({
    required RemoteSourceKind kind,
    required String displayName,
    required String host,
    required int port,
    String rootPath = '/',
    bool useTls = false,
    String? username,
    String? id,
    DateTime? createdAt,
  }) {
    final normalizedHost = normalizeHost(host);
    final hostError = validateHost(normalizedHost);
    if (hostError != null) {
      throw ArgumentError.value(host, 'host', hostError);
    }
    final portError = validatePort(port);
    if (portError != null) {
      throw ArgumentError.value(port, 'port', portError);
    }
    final normalizedRoot = normalizeRootPath(rootPath);
    final trimmedName = displayName.trim();
    return RemoteSource(
      id: id ??
          computeId(
            kind: kind,
            host: normalizedHost,
            port: port,
            rootPath: normalizedRoot,
          ),
      kind: kind,
      displayName: trimmedName.isEmpty ? normalizedHost : trimmedName,
      host: normalizedHost,
      port: port,
      rootPath: normalizedRoot,
      useTls: useTls,
      username: _nullIfBlank(username),
      createdAt: createdAt ?? DateTime.now(),
    );
  }

  /// Restores a source from [toJson] output.
  ///
  /// Throws [FormatException] when the record is unusable (unknown kind,
  /// malformed host or port) so callers can skip that single entry.
  factory RemoteSource.fromJson(Map<String, dynamic> json) {
    final kind = RemoteSourceKind.tryParse(json['kind']);
    if (kind == null) {
      throw FormatException('Unsupported remote source kind: ${json['kind']}');
    }
    final host = normalizeHost(json['host'] as String? ?? '');
    final hostError = validateHost(host);
    if (hostError != null) throw FormatException(hostError);
    final rawPort = json['port'];
    final port = rawPort is num ? rawPort.toInt() : kind.defaultPort;
    final portError = validatePort(port);
    if (portError != null) throw FormatException(portError);
    final createdAtMs = json['createdAt'];
    return RemoteSource(
      id: json['id'] as String? ?? '',
      kind: kind,
      displayName: json['displayName'] as String? ?? host,
      host: host,
      port: port,
      rootPath: normalizeRootPath(json['rootPath'] as String? ?? '/'),
      useTls: json['useTls'] as bool? ?? false,
      username: _nullIfBlank(json['username'] as String?),
      createdAt: createdAtMs is num
          ? DateTime.fromMillisecondsSinceEpoch(createdAtMs.toInt())
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  /// Stable identifier; derived from the endpoint when not supplied.
  final String id;

  /// Transport family.
  final RemoteSourceKind kind;

  /// User-facing name shown in lists and breadcrumbs.
  final String displayName;

  /// Hostname or IP literal without scheme or port (IPv6 without brackets).
  final String host;

  /// TCP port in `1..65535`.
  final int port;

  /// Absolute directory inside the server; `'/'` for the server root.
  final String rootPath;

  /// Whether WebDAV should use `https` (ignored by FTP / SMB).
  final bool useTls;

  /// Login name, `null` for anonymous access.
  final String? username;

  /// Creation timestamp, used only to keep list ordering stable.
  final DateTime createdAt;

  /// `host:port`, handy for list subtitles and error messages. IPv6 literals
  /// are bracketed so the result is unambiguous.
  String get authority =>
      isIpv6Literal(host) ? '[$host]:$port' : '$host:$port';

  /// Whether [host] is a syntactic IPv6 literal (no brackets).
  static bool isIpv6Literal(String host) {
    final value = normalizeHost(host).toLowerCase();
    if (!value.contains(':') || value.contains(' ')) return false;
    if (!RegExp(r'^[0-9a-f:.]+$').hasMatch(value)) return false;
    if (value.contains(':::')) return false;
    final compression = value.indexOf('::');
    if (compression != -1 && value.indexOf('::', compression + 2) != -1) {
      return false;
    }
    final groups = value.split(':').where((part) => part.isNotEmpty).toList();
    var ipv4Groups = 0;
    for (var i = 0; i < groups.length; i++) {
      final group = groups[i];
      if (group.contains('.')) {
        // A dotted tail is only legal in the final 32 bits.
        if (i != groups.length - 1) return false;
        final octets = group.split('.');
        if (octets.length != 4) return false;
        for (final octet in octets) {
          final parsed = int.tryParse(octet);
          if (parsed == null || parsed < 0 || parsed > 255) return false;
        }
        ipv4Groups = 1;
        continue;
      }
      if (group.length > 4) return false;
      if (int.tryParse(group, radix: 16) == null) return false;
    }
    final groupCount = groups.length + ipv4Groups;
    if (compression == -1) return groupCount == 8;
    return groupCount < 8;
  }

  /// Whether this record can be used to open a connection.
  bool get isValid => validationError == null;

  /// Human-readable reason this record is unusable, or `null` when valid.
  String? get validationError {
    final hostError = validateHost(host);
    if (hostError != null) return hostError;
    return validatePort(port);
  }

  /// Returns a copy with the given fields replaced (values are re-normalized).
  RemoteSource copyWith({
    String? id,
    RemoteSourceKind? kind,
    String? displayName,
    String? host,
    int? port,
    String? rootPath,
    bool? useTls,
    String? username,
    bool clearUsername = false,
    DateTime? createdAt,
  }) {
    return RemoteSource(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      displayName: displayName ?? this.displayName,
      host: host == null ? this.host : normalizeHost(host),
      port: port ?? this.port,
      rootPath: rootPath ?? this.rootPath,
      useTls: useTls ?? this.useTls,
      username: clearUsername ? null : (username ?? this.username),
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Serializes this source. Never contains a password.
  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.wireName,
        'displayName': displayName,
        'host': host,
        'port': port,
        'rootPath': rootPath,
        'useTls': useTls,
        if (username != null) 'username': username,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  @override
  String toString() => 'RemoteSource(${kind.wireName}, $authority$rootPath)';

  /// Deterministic id for an endpoint, so duplicates replace each other.
  static String computeId({
    required RemoteSourceKind kind,
    required String host,
    required int port,
    required String rootPath,
  }) {
    final seed = '${kind.wireName}|${host.toLowerCase()}|$port|$rootPath';
    final digest = sha256.convert(utf8.encode(seed)).toString();
    return 'rs_${digest.substring(0, 16)}';
  }

  /// Trims a host, dropping any pasted scheme, path or IPv6 brackets.
  static String normalizeHost(String raw) {
    var host = raw.trim();
    final schemeIndex = host.indexOf('://');
    if (schemeIndex != -1) host = host.substring(schemeIndex + 3);
    final slashIndex = host.indexOf('/');
    if (slashIndex != -1) host = host.substring(0, slashIndex);
    if (host.startsWith('[') && host.endsWith(']')) {
      host = host.substring(1, host.length - 1);
    }
    return host.trim();
  }

  /// Normalizes a directory to `/a/b` form (`'/'` for the root).
  static String normalizeRootPath(String raw) {
    var value = raw.trim().replaceAll('\\', '/');
    if (value.isEmpty) return '/';
    if (!value.startsWith('/')) value = '/$value';
    while (value.length > 1 && value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  /// Returns an error message for [host], or `null` when acceptable.
  ///
  /// A colon is only legal inside a real IPv6 literal; `nas.local:80` still
  /// means "the port belongs in the port field".
  static String? validateHost(String host) {
    final value = normalizeHost(host);
    if (value.isEmpty) return 'Host is required.';
    if (value.contains(' ')) return 'Host must not contain spaces.';
    if (value.contains(':') && !isIpv6Literal(value)) {
      return 'Enter the port in the port field, not in the host.';
    }
    return null;
  }

  /// Returns an error message for [port], or `null` when acceptable.
  static String? validatePort(int port) {
    if (port < 1 || port > 65535) return 'Port must be between 1 and 65535.';
    return null;
  }

  static String? _nullIfBlank(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}

/// A single file or folder inside a [RemoteSource].
///
/// [path] is relative to the source root and uses `/` separators; [name] is the
/// last path segment. [sizeBytes] is `null` when the server does not report a
/// size (FTP `LIST` without a size column, for example).
class RemoteEntry {
  /// Creates an entry. [path] is normalized to have no leading slash.
  const RemoteEntry({
    required this.path,
    required this.name,
    required this.isDirectory,
    this.sizeBytes,
    this.modifiedAt,
    this.etag,
    this.artworkUri,
  });

  /// Restores an entry from [toJson] output.
  factory RemoteEntry.fromJson(Map<String, dynamic> json) {
    final modifiedMs = json['modifiedAt'];
    return RemoteEntry(
      path: _stripLeadingSlash(json['path'] as String? ?? ''),
      name: json['name'] as String? ?? '',
      isDirectory: json['isDirectory'] as bool? ?? false,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt(),
      modifiedAt: modifiedMs is num
          ? DateTime.fromMillisecondsSinceEpoch(modifiedMs.toInt())
          : null,
      etag: json['etag'] as String?,
      artworkUri: json['artworkUri'] as String?,
    );
  }

  /// Path relative to the source root (`''` is the root directory).
  final String path;

  /// Display name (last path segment).
  final String name;

  /// Whether this entry is a folder that can be browsed into.
  final bool isDirectory;

  /// Size in bytes, or `null` when unknown.
  final int? sizeBytes;

  /// Last modification time, or `null` when the server omits it.
  final DateTime? modifiedAt;

  /// Server-supplied validator, used as a cache key component when present.
  final String? etag;

  /// Optional artwork/cover art URI string for display in UI.
  final String? artworkUri;

  /// Serializes this entry for the cache index and provider channel payloads.
  Map<String, dynamic> toJson() => {
        'path': path,
        'name': name,
        'isDirectory': isDirectory,
        if (sizeBytes != null) 'sizeBytes': sizeBytes,
        if (modifiedAt != null) 'modifiedAt': modifiedAt!.millisecondsSinceEpoch,
        if (etag != null) 'etag': etag,
        if (artworkUri != null) 'artworkUri': artworkUri,
      };

  /// Sorts folders before files, then by name ignoring case.
  static int compare(RemoteEntry a, RemoteEntry b) {
    if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  @override
  String toString() =>
      'RemoteEntry($path, dir=$isDirectory, size=$sizeBytes)';

  static String _stripLeadingSlash(String value) {
    var path = value.trim().replaceAll('\\', '/');
    while (path.startsWith('/')) {
      path = path.substring(1);
    }
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return path;
  }
}
