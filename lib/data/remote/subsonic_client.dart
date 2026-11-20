// lib/data/remote/subsonic_client.dart
//
// Navidrome / Subsonic API client (API 1.16.1), pure Dart over an injected
// `http.Client`.
//
// Authentication uses the Subsonic token scheme: every request carries
// `u` (user), `s` (per-request salt), `t = md5(password + salt)`, `v` (protocol
// version), `c` (client name) and `f=json`. The password itself is never sent,
// never put in a URI and never logged. The salt generator is injectable so
// tests can pin the token, and the default uses `Random.secure()`.
//
// Failure codes are stable and safe to branch on:
//   SUBSONIC_CONFIG, SUBSONIC_UNSAFE_TARGET, SUBSONIC_BAD_ID,
//   SUBSONIC_BAD_SONG_ID, SUBSONIC_TIMEOUT, SUBSONIC_NETWORK,
//   SUBSONIC_HTTP_<status>, SUBSONIC_MALFORMED_JSON, SUBSONIC_BAD_RESPONSE,
//   SUBSONIC_API_ERROR, SUBSONIC_API_<code>.
// No message, cause or `toString()` contains the password, the token, the salt
// or a full request URI with its query string.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../../core/errors/app_error_base.dart';
import '../../core/network/remote_target_policy.dart';

/// Generates the per-request salt. Inject a constant in tests.
typedef SubsonicSaltGenerator = String Function();

/// Typed Subsonic failure. [code] is the stable reason code listed above.
class SubsonicError extends AppError {
  /// Numeric `error.code` from the server envelope, when it sent one.
  final int? apiCode;

  /// `error.message` from the server envelope, redacted and truncated.
  final String? apiMessage;

  /// API method that failed, e.g. `getAlbum`.
  final String? method;

  const SubsonicError({
    required super.code,
    required super.userMessage,
    this.apiCode,
    this.apiMessage,
    this.method,
    super.cause,
    super.stackTrace,
  });
}

/// One artist row from `getArtists` or `getArtist`.
final class SubsonicArtist {
  /// Server-side id used by [SubsonicClient.getArtist].
  final String id;

  /// Display name; falls back to [id] when the server omitted it.
  final String name;

  /// Number of albums, `0` when omitted.
  final int albumCount;

  /// Cover-art id used by `getCoverArt`.
  final String? coverArt;

  /// `artistImageUrl`, when advertised.
  final String? imageUrl;

  /// Albums, populated by [SubsonicClient.getArtist] only.
  final List<SubsonicAlbum> albums;

  const SubsonicArtist({
    required this.id,
    required this.name,
    this.albumCount = 0,
    this.coverArt,
    this.imageUrl,
    this.albums = const [],
  });

  @override
  String toString() => 'SubsonicArtist($id "$name", ${albums.length} albums)';
}

/// One album row, with songs populated by [SubsonicClient.getAlbum].
final class SubsonicAlbum {
  /// Server-side id used by [SubsonicClient.getAlbum].
  final String id;

  /// Album title; falls back to [id] when omitted.
  final String name;

  /// Album artist as reported, or an empty string.
  final String artist;

  /// Artist id, when advertised.
  final String? artistId;

  /// Cover-art id used by `getCoverArt`.
  final String? coverArt;

  /// Genre, when advertised.
  final String? genre;

  /// Song count; `songs.length` when the server omitted it.
  final int songCount;

  /// Total duration in seconds, `0` when omitted.
  final int durationSeconds;

  /// Release year, when advertised.
  final int? year;

  /// Tracks, populated by [SubsonicClient.getAlbum] only.
  final List<SubsonicSong> songs;

  const SubsonicAlbum({
    required this.id,
    required this.name,
    this.artist = '',
    this.artistId,
    this.coverArt,
    this.genre,
    this.songCount = 0,
    this.durationSeconds = 0,
    this.year,
    this.songs = const [],
  });

  /// Total duration as a [Duration].
  Duration get duration => Duration(seconds: durationSeconds);

  @override
  String toString() => 'SubsonicAlbum($id "$name", ${songs.length} songs)';
}

/// One track row from an album, playlist or search payload.
final class SubsonicSong {
  /// Server-side id used by [SubsonicClient.streamUrl].
  final String id;

  /// Track title; falls back to [id] when omitted.
  final String title;

  /// Album title, when advertised.
  final String? album;

  /// Album id, when advertised.
  final String? albumId;

  /// Track artist, when advertised.
  final String? artist;

  /// Cover-art id used by `getCoverArt`.
  final String? coverArt;

  /// Genre, when advertised.
  final String? genre;

  /// File suffix, e.g. `flac`.
  final String? suffix;

  /// MIME type, when advertised.
  final String? contentType;

  /// Server-side path, when advertised.
  final String? path;

  /// Duration in seconds, `0` when omitted.
  final int durationSeconds;

  /// Track number within its disc.
  final int? track;

  /// Disc number for multi-disc albums.
  final int? discNumber;

  /// Release year.
  final int? year;

  /// Bitrate in kbit/s, when advertised.
  final int? bitRateKbps;

  /// File size in bytes, when advertised.
  final int? sizeBytes;

  /// True when the entry is a folder rather than a track.
  final bool isDirectory;

  const SubsonicSong({
    required this.id,
    required this.title,
    this.album,
    this.albumId,
    this.artist,
    this.coverArt,
    this.genre,
    this.suffix,
    this.contentType,
    this.path,
    this.durationSeconds = 0,
    this.track,
    this.discNumber,
    this.year,
    this.bitRateKbps,
    this.sizeBytes,
    this.isDirectory = false,
  });

  /// Duration as a [Duration].
  Duration get duration => Duration(seconds: durationSeconds);

  @override
  String toString() => 'SubsonicSong($id "$title")';
}

/// One playlist row; `songs` is populated by [SubsonicClient.getPlaylist].
final class SubsonicPlaylist {
  /// Server-side id used by [SubsonicClient.getPlaylist].
  final String id;

  /// Playlist name; falls back to [id] when omitted.
  final String name;

  /// Owner username, or an empty string.
  final String owner;

  /// Free-form comment, when advertised.
  final String? comment;

  /// Cover-art id used by `getCoverArt`.
  final String? coverArt;

  /// True when the playlist is shared.
  final bool isPublic;

  /// Song count; `songs.length` when the server omitted it.
  final int songCount;

  /// Total duration in seconds, `0` when omitted.
  final int durationSeconds;

  /// Entries, populated by [SubsonicClient.getPlaylist] only.
  final List<SubsonicSong> songs;

  const SubsonicPlaylist({
    required this.id,
    required this.name,
    this.owner = '',
    this.comment,
    this.coverArt,
    this.isPublic = false,
    this.songCount = 0,
    this.durationSeconds = 0,
    this.songs = const [],
  });

  /// Total duration as a [Duration].
  Duration get duration => Duration(seconds: durationSeconds);

  @override
  String toString() => 'SubsonicPlaylist($id "$name", ${songs.length} songs)';
}

/// Result of a Subsonic `search3` query, grouping matches across entity types.
final class SubsonicSearchResult {
  /// Matching artists.
  final List<SubsonicArtist> artists;

  /// Matching albums.
  final List<SubsonicAlbum> albums;

  /// Matching songs.
  final List<SubsonicSong> songs;

  const SubsonicSearchResult({
    this.artists = const [],
    this.albums = const [],
    this.songs = const [],
  });

  /// True when the search produced no results in any category.
  bool get isEmpty => artists.isEmpty && albums.isEmpty && songs.isEmpty;

  /// True when at least one artist, album or song matched.
  bool get isNotEmpty => !isEmpty;

  /// Total count across all result types.
  int get totalCount => artists.length + albums.length + songs.length;

  @override
  String toString() =>
      'SubsonicSearchResult(${artists.length} artists, ${albums.length} albums, ${songs.length} songs)';
}

/// Client for one Navidrome / Subsonic server.
final class SubsonicClient {
  /// Subsonic protocol version sent as `v`.
  static const String defaultProtocolVersion = '1.16.1';

  /// Client name sent as `c`.
  static const String defaultClientName = 'Pulsr';

  final Uri _baseUrl;
  final String _basePath;
  final String _username;
  final String _password;
  final String _version;
  final String _clientName;
  final SubsonicSaltGenerator _saltGenerator;
  final http.Client _client;
  final bool _ownsClient;
  final Duration _timeout;
  final Set<String> _allowedHostSuffixes;

  /// Creates a client for [baseUrl] (e.g. `https://music.example.com`, or a
  /// server mounted under a path such as `https://host/music`).
  ///
  /// [allowedHostSuffixes] is forwarded to [RemoteTargetPolicy]: a server on
  /// the LAN must be listed explicitly, because its address is private.
  /// [saltGenerator] is injectable for deterministic tests. No credential is
  /// included in any exception or in [toString].
  SubsonicClient({
    required Uri baseUrl,
    required String username,
    required String password,
    http.Client? client,
    Duration timeout = const Duration(seconds: 20),
    String version = defaultProtocolVersion,
    String clientName = defaultClientName,
    SubsonicSaltGenerator? saltGenerator,
    Set<String> allowedHostSuffixes = const {},
  })  : _baseUrl = _validatedBaseUrl(baseUrl, allowedHostSuffixes),
        _basePath = _normalizedBasePath(baseUrl.path),
        _username = username,
        _password = password,
        _version = version,
        _clientName = clientName,
        _saltGenerator = saltGenerator ?? _secureSalt,
        _client = client ?? http.Client(),
        _ownsClient = client == null,
        _timeout = timeout,
        _allowedHostSuffixes = allowedHostSuffixes {
    if (username.trim().isEmpty) {
      throw const SubsonicError(
        code: 'SUBSONIC_CONFIG',
        userMessage: 'A Subsonic username is required.',
      );
    }
  }

  /// Releases the HTTP client when this instance created it.
  void close() {
    if (_ownsClient) _client.close();
  }

  /// Verifies credentials and connectivity.
  Future<void> ping() async {
    await _call('ping');
  }

  /// Lists every artist, flattened across the server's index buckets.
  Future<List<SubsonicArtist>> getArtists() async {
    final envelope = await _call('getArtists');
    final container = _asMap(envelope['artists']);
    if (container == null) return const [];
    final artists = <SubsonicArtist>[];
    final indexes = container['index'];
    if (indexes is List) {
      for (final index in indexes) {
        final bucket = _asMap(index);
        final entries = bucket?['artist'];
        if (entries is List) {
          for (final entry in entries) {
            final artist = _artistFrom(entry);
            if (artist != null) artists.add(artist);
          }
        }
      }
    }
    return artists;
  }

  /// Reads one artist and its albums.
  Future<SubsonicArtist> getArtist(String id) async {
    final artistId = _requiredId(id, 'getArtist');
    final envelope = await _call('getArtist', {'id': artistId});
    final map = _asMap(envelope['artist']);
    if (map == null) {
      throw SubsonicError(
        code: 'SUBSONIC_BAD_RESPONSE',
        userMessage: 'The music server did not return that artist.',
        method: 'getArtist',
      );
    }
    final artist = _artistFrom(map, includeAlbums: true);
    if (artist == null) {
      throw SubsonicError(
        code: 'SUBSONIC_BAD_RESPONSE',
        userMessage: 'The music server returned an artist without an id.',
        method: 'getArtist',
      );
    }
    return artist;
  }

  /// Reads one album and its songs.
  Future<SubsonicAlbum> getAlbum(String id) async {
    final albumId = _requiredId(id, 'getAlbum');
    final envelope = await _call('getAlbum', {'id': albumId});
    final map = _asMap(envelope['album']);
    if (map == null) {
      throw SubsonicError(
        code: 'SUBSONIC_BAD_RESPONSE',
        userMessage: 'The music server did not return that album.',
        method: 'getAlbum',
      );
    }
    final album = _albumFrom(map, includeSongs: true);
    if (album == null) {
      throw SubsonicError(
        code: 'SUBSONIC_BAD_RESPONSE',
        userMessage: 'The music server returned an album without an id.',
        method: 'getAlbum',
      );
    }
    return album;
  }

  /// Lists playlists without their entries.
  Future<List<SubsonicPlaylist>> getPlaylists() async {
    final envelope = await _call('getPlaylists');
    final container = _asMap(envelope['playlists']);
    final entries = container?['playlist'];
    if (entries is! List) return const [];
    final playlists = <SubsonicPlaylist>[];
    for (final entry in entries) {
      final playlist = _playlistFrom(entry);
      if (playlist != null) playlists.add(playlist);
    }
    return playlists;
  }

  /// Reads one playlist and its entries.
  Future<SubsonicPlaylist> getPlaylist(String id) async {
    final playlistId = _requiredId(id, 'getPlaylist');
    final envelope = await _call('getPlaylist', {'id': playlistId});
    final map = _asMap(envelope['playlist']);
    if (map == null) {
      throw SubsonicError(
        code: 'SUBSONIC_BAD_RESPONSE',
        userMessage: 'The music server did not return that playlist.',
        method: 'getPlaylist',
      );
    }
    final playlist = _playlistFrom(map, includeSongs: true);
    if (playlist == null) {
      throw SubsonicError(
        code: 'SUBSONIC_BAD_RESPONSE',
        userMessage: 'The music server returned a playlist without an id.',
        method: 'getPlaylist',
      );
    }
    return playlist;
  }

  /// Builds the playable stream URI for [songId].
  ///
  /// The URI carries the same salt/token auth parameters as an API call, is
  /// percent-encoded exactly once (no `%25` double-encoding) and is re-checked
  /// against [RemoteTargetPolicy] before it is returned.
  Uri streamUrl(String songId) {
    final id = songId.trim();
    if (id.isEmpty) {
      throw const SubsonicError(
        code: 'SUBSONIC_BAD_SONG_ID',
        userMessage: 'A song id is required to build a stream URL.',
      );
    }
    final signed = _sign('stream', {'id': id});
    final verdict = RemoteTargetPolicy.classify(
      signed.uri.toString(),
      allowedHostSuffixes: _allowedHostSuffixes,
    );
    if (verdict != RemoteTargetVerdict.allowed) {
      throw const SubsonicError(
        code: 'SUBSONIC_UNSAFE_TARGET',
        userMessage: 'The music server address is not allowed.',
        method: 'stream',
      );
    }
    return signed.uri;
  }

  /// Builds the cover art URI for [coverArtId].
  ///
  /// Optional [size] scales the image to a square of size*size pixels.
  /// The URI carries the same salt/token auth parameters as an API call and
  /// is checked against [RemoteTargetPolicy].
  Uri getCoverArtUrl(String coverArtId, {int? size}) {
    final id = coverArtId.trim();
    if (id.isEmpty) {
      throw const SubsonicError(
        code: 'SUBSONIC_BAD_ID',
        userMessage: 'A cover art id is required to build a cover art URL.',
        method: 'getCoverArt',
      );
    }
    final params = <String, String>{
      'id': id,
      if (size != null && size > 0) 'size': size.toString(),
    };
    final signed = _sign('getCoverArt', params);
    final verdict = RemoteTargetPolicy.classify(
      signed.uri.toString(),
      allowedHostSuffixes: _allowedHostSuffixes,
    );
    if (verdict != RemoteTargetVerdict.allowed) {
      throw const SubsonicError(
        code: 'SUBSONIC_UNSAFE_TARGET',
        userMessage: 'The music server address is not allowed.',
        method: 'getCoverArt',
      );
    }
    return signed.uri;
  }

  /// Returns a canonical, stable cache key for cover art that does NOT change
  /// with each salt/token rotation (§8.5), enabling persistent image caches.
  String getCoverArtCacheKey(String coverArtId, {int? size}) {
    final id = coverArtId.trim();
    if (id.isEmpty) return '';
    final sizeSegment = size != null && size > 0 ? '&size=$size' : '';
    final portSegment = _baseUrl.hasPort ? ':${_baseUrl.port}' : '';
    return 'subsonic://${_baseUrl.host}$portSegment$_basePath/rest/getCoverArt?id=$id$sizeSegment';
  }

  /// Searches the server for artists, albums and songs matching [query]
  /// via Subsonic `search3`.
  Future<SubsonicSearchResult> search3(
    String query, {
    int artistCount = 20,
    int artistOffset = 0,
    int albumCount = 20,
    int albumOffset = 0,
    int songCount = 50,
    int songOffset = 0,
    String? musicFolderId,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const SubsonicSearchResult();

    final params = <String, String>{
      'query': trimmed,
      if (artistCount > 0) 'artistCount': artistCount.toString(),
      if (artistOffset > 0) 'artistOffset': artistOffset.toString(),
      if (albumCount > 0) 'albumCount': albumCount.toString(),
      if (albumOffset > 0) 'albumOffset': albumOffset.toString(),
      if (songCount > 0) 'songCount': songCount.toString(),
      if (songOffset > 0) 'songOffset': songOffset.toString(),
      if (musicFolderId != null && musicFolderId.trim().isNotEmpty)
        'musicFolderId': musicFolderId.trim(),
    };

    final envelope = await _call('search3', params);
    final container = _asMap(envelope['searchResult3']) ??
        _asMap(envelope['searchResult2']);
    if (container == null) return const SubsonicSearchResult();

    final artists = <SubsonicArtist>[];
    final artistEntries = container['artist'];
    if (artistEntries is List) {
      for (final entry in artistEntries) {
        final artist = _artistFrom(entry);
        if (artist != null) artists.add(artist);
      }
    } else if (artistEntries != null) {
      final artist = _artistFrom(artistEntries);
      if (artist != null) artists.add(artist);
    }

    final albums = <SubsonicAlbum>[];
    final albumEntries = container['album'];
    if (albumEntries is List) {
      for (final entry in albumEntries) {
        final album = _albumFrom(entry);
        if (album != null) albums.add(album);
      }
    } else if (albumEntries != null) {
      final album = _albumFrom(albumEntries);
      if (album != null) albums.add(album);
    }

    final songs = <SubsonicSong>[];
    final songEntries = container['song'];
    if (songEntries is List) {
      for (final entry in songEntries) {
        final song = _songFrom(entry);
        if (song != null) songs.add(song);
      }
    } else if (songEntries != null) {
      final song = _songFrom(songEntries);
      if (song != null) songs.add(song);
    }

    return SubsonicSearchResult(
      artists: artists,
      albums: albums,
      songs: songs,
    );
  }

  Future<Map<String, dynamic>> _call(
    String method, [
    Map<String, String> params = const {},
  ]) async {
    final signed = _sign(method, params);
    final http.Response response;
    try {
      response = await _client.get(signed.uri,
          headers: const {'Accept': 'application/json'}).timeout(_timeout);
    } on TimeoutException catch (error, stackTrace) {
      throw SubsonicError(
        code: 'SUBSONIC_TIMEOUT',
        userMessage: 'The music server did not answer in time.',
        method: method,
        cause: error,
        stackTrace: stackTrace,
      );
    } on SocketException catch (error, stackTrace) {
      throw SubsonicError(
        code: 'SUBSONIC_NETWORK',
        userMessage: 'Could not reach the music server.',
        method: method,
        cause: error.message,
        stackTrace: stackTrace,
      );
    } on http.ClientException catch (error, stackTrace) {
      throw SubsonicError(
        code: 'SUBSONIC_NETWORK',
        userMessage: 'Could not reach the music server.',
        method: method,
        cause: _redact(error.message, signed.auth),
        stackTrace: stackTrace,
      );
    }

    if (response.statusCode != 200) {
      throw SubsonicError(
        code: 'SUBSONIC_HTTP_${response.statusCode}',
        userMessage: 'The music server rejected the request '
            '(HTTP ${response.statusCode}).',
        method: method,
      );
    }

    final Object? decoded;
    try {
      decoded =
          jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
    } on FormatException catch (error, stackTrace) {
      throw SubsonicError(
        code: 'SUBSONIC_MALFORMED_JSON',
        userMessage: 'The music server returned data that is not JSON.',
        method: method,
        cause: _redact(error.message, signed.auth),
        stackTrace: stackTrace,
      );
    }

    final root = _asMap(decoded);
    final envelope = root == null ? null : _asMap(root['subsonic-response']);
    if (envelope == null) {
      throw SubsonicError(
        code: 'SUBSONIC_BAD_RESPONSE',
        userMessage: 'The music server sent an unusable response.',
        method: method,
      );
    }

    final apiError = _asMap(envelope['error']);
    if (apiError != null) {
      final code = _asInt(apiError['code']);
      final message = _asString(apiError['message']);
      final safeMessage = message == null
          ? 'The music server rejected the request.'
          : _redact(message, signed.auth);
      throw SubsonicError(
        code: code == null ? 'SUBSONIC_API_ERROR' : 'SUBSONIC_API_$code',
        userMessage: safeMessage,
        apiCode: code,
        apiMessage: safeMessage,
        method: method,
      );
    }

    final status = _asString(envelope['status']);
    if (status == null) {
      throw SubsonicError(
        code: 'SUBSONIC_BAD_RESPONSE',
        userMessage: 'The music server sent an unusable response.',
        method: method,
      );
    }
    if (status.toLowerCase() != 'ok') {
      throw SubsonicError(
        code: 'SUBSONIC_API_ERROR',
        userMessage: 'The music server rejected the request.',
        apiMessage: _redact(status, signed.auth),
        method: method,
      );
    }
    return envelope;
  }

  _SignedRequest _sign(String method, Map<String, String> params) {
    final salt = _saltGenerator();
    if (salt.isEmpty) {
      throw const SubsonicError(
        code: 'SUBSONIC_CONFIG',
        userMessage: 'The salt generator returned an empty salt.',
      );
    }
    final auth = <String, String>{
      'u': _username,
      't': md5.convert(utf8.encode('$_password$salt')).toString(),
      's': salt,
      'v': _version,
      'c': _clientName,
      'f': 'json',
    };
    final path = '$_basePath/rest/$method.view';
    final uri = _baseUrl.replace(
      path: path,
      queryParameters: <String, String>{...auth, ...params},
    );
    return _SignedRequest(uri, auth);
  }

  /// Removes credential values from a message and bounds its length, so a
  /// server echo or an exception can never carry a token into a log.
  String _redact(String message, Map<String, String> auth) {
    var safe = message;
    for (final secret in <String>[
      if (_password.length >= 3) _password,
      if ((auth['t'] ?? '').length >= 3) auth['t']!,
      if ((auth['s'] ?? '').length >= 3) auth['s']!,
    ]) {
      safe = safe.replaceAll(secret, '***');
    }
    safe = safe.replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
    return safe.length <= 300 ? safe : '${safe.substring(0, 300)}…';
  }

  String _requiredId(String id, String method) {
    final trimmed = id.trim();
    if (trimmed.isEmpty) {
      throw SubsonicError(
        code: 'SUBSONIC_BAD_ID',
        userMessage: 'A server id is required.',
        method: method,
      );
    }
    return trimmed;
  }

  static SubsonicArtist? _artistFrom(
    Object? value, {
    bool includeAlbums = false,
  }) {
    final map = _asMap(value);
    if (map == null) return null;
    final id = _asString(map['id'])?.trim();
    if (id == null || id.isEmpty) return null;
    final albums = <SubsonicAlbum>[];
    final entries = map['album'];
    if (includeAlbums && entries is List) {
      for (final entry in entries) {
        final album = _albumFrom(entry);
        if (album != null) albums.add(album);
      }
    }
    final name = _asString(map['name']) ?? _asString(map['artist']);
    return SubsonicArtist(
      id: id,
      name: name == null || name.trim().isEmpty ? id : name.trim(),
      albumCount: _asInt(map['albumCount']) ?? albums.length,
      coverArt: _asString(map['coverArt']),
      imageUrl: _asString(map['artistImageUrl']),
      albums: albums,
    );
  }

  static SubsonicAlbum? _albumFrom(Object? value, {bool includeSongs = false}) {
    final map = _asMap(value);
    if (map == null) return null;
    final id = _asString(map['id'])?.trim();
    if (id == null || id.isEmpty) return null;
    final songs =
        includeSongs ? _songList(map['song']) : const <SubsonicSong>[];
    final name = _asString(map['name']) ?? _asString(map['title']);
    final artist = _asString(map['artist']) ?? _asString(map['albumArtist']);
    return SubsonicAlbum(
      id: id,
      name: name == null || name.trim().isEmpty ? id : name.trim(),
      artist: artist?.trim() ?? '',
      artistId: _asString(map['artistId']),
      coverArt: _asString(map['coverArt']),
      genre: _asString(map['genre']),
      songCount: _asInt(map['songCount']) ?? songs.length,
      durationSeconds: _asInt(map['duration']) ?? 0,
      year: _asInt(map['year']),
      songs: songs,
    );
  }

  static SubsonicPlaylist? _playlistFrom(
    Object? value, {
    bool includeSongs = false,
  }) {
    final map = _asMap(value);
    if (map == null) return null;
    final id = _asString(map['id'])?.trim();
    if (id == null || id.isEmpty) return null;
    final songs = includeSongs
        ? _songList(map['entry'] ?? map['song'])
        : const <SubsonicSong>[];
    final name = _asString(map['name']) ?? _asString(map['title']);
    return SubsonicPlaylist(
      id: id,
      name: name == null || name.trim().isEmpty ? id : name.trim(),
      owner: _asString(map['owner'])?.trim() ?? '',
      comment: _asString(map['comment']),
      coverArt: _asString(map['coverArt']),
      isPublic: _asBool(map['public']) ?? false,
      songCount: _asInt(map['songCount']) ?? songs.length,
      durationSeconds: _asInt(map['duration']) ?? 0,
      songs: songs,
    );
  }

  static List<SubsonicSong> _songList(Object? value) {
    if (value is! List) return const [];
    final songs = <SubsonicSong>[];
    for (final entry in value) {
      final song = _songFrom(entry);
      if (song != null) songs.add(song);
    }
    return songs;
  }

  static SubsonicSong? _songFrom(Object? value) {
    final map = _asMap(value);
    if (map == null) return null;
    final id = _asString(map['id'])?.trim();
    if (id == null || id.isEmpty) return null;
    final title = _asString(map['title'])?.trim();
    return SubsonicSong(
      id: id,
      title: title == null || title.isEmpty ? id : title,
      album: _asString(map['album']),
      albumId: _asString(map['albumId']) ?? _asString(map['parent']),
      artist: _asString(map['artist']),
      coverArt: _asString(map['coverArt']),
      genre: _asString(map['genre']),
      suffix: _asString(map['suffix']),
      contentType: _asString(map['contentType']),
      path: _asString(map['path']),
      durationSeconds: _asInt(map['duration']) ?? 0,
      track: _asInt(map['track']),
      discNumber: _asInt(map['discNumber']),
      year: _asInt(map['year']),
      bitRateKbps: _asInt(map['bitRate']),
      sizeBytes: _asInt(map['size']),
      isDirectory: _asBool(map['isDir']) ?? false,
    );
  }

  static Uri _validatedBaseUrl(Uri baseUrl, Set<String> allowlist) {
    final scheme = baseUrl.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      throw const SubsonicError(
        code: 'SUBSONIC_CONFIG',
        userMessage: 'The music server address must be an http(s) URL.',
      );
    }
    if (baseUrl.host.trim().isEmpty) {
      throw const SubsonicError(
        code: 'SUBSONIC_CONFIG',
        userMessage: 'The music server address is missing a host.',
      );
    }
    if (baseUrl.userInfo.isNotEmpty) {
      throw const SubsonicError(
        code: 'SUBSONIC_CONFIG',
        userMessage: 'Put credentials in the login fields, not in the URL.',
      );
    }
    if (baseUrl.hasQuery || baseUrl.hasFragment) {
      throw const SubsonicError(
        code: 'SUBSONIC_CONFIG',
        userMessage: 'The music server address must not carry a query or '
            'fragment.',
      );
    }
    final verdict = RemoteTargetPolicy.classify(
      baseUrl.toString(),
      allowedHostSuffixes: allowlist,
    );
    if (verdict != RemoteTargetVerdict.allowed) {
      throw const SubsonicError(
        code: 'SUBSONIC_UNSAFE_TARGET',
        userMessage: 'The music server address is not allowed.',
      );
    }
    return baseUrl;
  }

  /// `/music/` -> `/music`, `/rest/` -> ``, `/` -> ``.
  static String _normalizedBasePath(String path) {
    var normalized = path;
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    if (normalized == '/rest') return '';
    if (normalized.endsWith('/rest')) {
      normalized = normalized.substring(0, normalized.length - 5);
    }
    return normalized;
  }

  /// 8 random bytes as hex; does not depend on the platform clock.
  static String _secureSalt() {
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < 8; i++) {
      buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  static Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static String? _asString(Object? value) {
    if (value is String) return value;
    if (value is num) return value.toString();
    return null;
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static bool? _asBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1') return true;
      if (normalized == 'false' || normalized == '0') return false;
    }
    return null;
  }

  @override
  String toString() => 'SubsonicClient(${_baseUrl.host})';
}

/// A URI plus the auth parameters used to sign it, for redaction.
final class _SignedRequest {
  const _SignedRequest(this.uri, this.auth);

  final Uri uri;
  final Map<String, String> auth;
}
