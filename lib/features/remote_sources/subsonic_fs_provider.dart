// lib/features/remote_sources/subsonic_fs_provider.dart
//
// P1-8 "network parity": a Navidrome / Subsonic library as a [RemoteFsProvider],
// so the existing browser, loopback stream bridge and cache work unchanged.
//
// The provider owns a virtual tree built from API calls; nothing is indexed on
// disk and ids stay server-side:
//
//   ''                                  artists             (getArtists)
//   artist/<encoded artist id>          albums of that artist (getArtist)
//   album/<encoded album id>            songs of that album  (getAlbum)
//   album/<encoded album id>/song/<id>  one playable track   (stream)
//
// Ids are percent-encoded into a single path segment, so an id that contains
// `/`, `+`, `=` or `&` cannot break the tree, the breadcrumb or the base64
// path handed to the loopback server. Encoding is applied to the id only and
// the same id always produces the same path, which is what makes a cached
// stream URL keep working across remounts.
//
// The song path carries its album as well as its id because `stat` must report
// a size for range requests and the API has no "song by id" call: the album is
// the cheapest place to read the track's metadata from.
import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/errors/app_error_base.dart';
import '../../core/utils/error_logger.dart';
import '../../data/remote/subsonic_client.dart';
import '../../domain/interfaces/remote_fs_provider.dart';
import '../../domain/models/remote_source.dart';

/// Subsonic implementation of [RemoteFsProvider].
///
/// Sits next to `WebDavFsProvider` / `FtpFsProvider` / `SmbFsProvider` and is
/// built by `createRemoteProvider`; credentials come from the shared secure
/// credential store, never from the [RemoteSource] record.
class SubsonicFsProvider implements RemoteFsProvider {
  /// Creates a provider for [source].
  ///
  /// [username]/[password] come from the credential store; when [username] is
  /// omitted the source's own login is used. [client] and [saltGenerator] are
  /// injectable for tests.
  SubsonicFsProvider(
    this.source, {
    String? username,
    String? password,
    http.Client? client,
    Duration timeout = const Duration(seconds: 20),
    SubsonicSaltGenerator? saltGenerator,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _timeout = timeout {
    _api = SubsonicClient(
      baseUrl: baseUrlFor(source),
      username: _resolveUsername(source, username),
      password: password ?? '',
      client: _client,
      timeout: timeout,
      saltGenerator: saltGenerator,
      // A library the user configured on the LAN is a deliberate destination:
      // the shared SSRF policy would otherwise refuse its private address.
      allowedHostSuffixes: <String>{source.host.toLowerCase()},
    );
  }

  /// Path segment that introduces an artist.
  static const String artistSegment = 'artist';

  /// Path segment that introduces an album.
  static const String albumSegment = 'album';

  /// Path segment that introduces a track.
  static const String songSegment = 'song';

  @override
  final RemoteSource source;

  final http.Client _client;
  final bool _ownsClient;
  final Duration _timeout;
  late final SubsonicClient _api;
  bool _closed = false;

  /// `(scheme)://(host):(port)(rootPath)` for [source].
  ///
  /// `rootPath` doubles as the server's mount point (`https://host/music`),
  /// which is how a Subsonic instance behind a reverse proxy is addressed.
  static Uri baseUrlFor(RemoteSource source) => Uri(
        scheme: source.useTls ? 'https' : 'http',
        host: source.host,
        port: source.port,
        path: source.rootPath,
      );

  /// Explicit login when the credential store carries one, else the source's.
  ///
  /// A stored pair can have an empty username (a password-only edit), which
  /// must not shadow the name the source record already holds.
  static String _resolveUsername(RemoteSource source, String? username) {
    final explicit = (username ?? '').trim();
    return explicit.isEmpty ? (source.username ?? '').trim() : explicit;
  }

  /// Lists the children of [path].
  @override
  Future<List<RemoteEntry>> list(String path) async {
    final segments = _segments(path);
    try {
      if (segments.isEmpty) {
        final artists = await _api.getArtists();
        return _sorted(<RemoteEntry>[
          for (final artist in artists)
            RemoteEntry(
              path: artistPath(artist.id),
              name: artist.name,
              isDirectory: true,
              artworkUri: _coverArtUri(artist.coverArt),
              artworkCacheKey: _coverArtCacheKey(artist.coverArt),
            ),
        ]);
      }
      if (segments.length == 2 && segments.first == artistSegment) {
        final artistId = _decodeId(segments[1]);
        if (artistId == null) throw _badPath();
        final artist = await _api.getArtist(artistId);
        return _sorted(<RemoteEntry>[
          for (final album in artist.albums)
            RemoteEntry(
              path: albumPath(album.id),
              name: album.name,
              isDirectory: true,
              artworkUri: _coverArtUri(album.coverArt),
              artworkCacheKey: _coverArtCacheKey(album.coverArt),
            ),
        ]);
      }
      if (segments.length == 2 && segments.first == albumSegment) {
        final albumId = _decodeId(segments[1]);
        if (albumId == null) throw _badPath();
        final album = await _api.getAlbum(albumId);
        return _sorted(<RemoteEntry>[
          for (final song in album.songs)
            RemoteEntry(
              path: songPath(album.id, song.id),
              name: _songName(song),
              isDirectory: false,
              sizeBytes: song.sizeBytes,
              artworkUri: _coverArtUri(song.coverArt ?? album.coverArt),
              artworkCacheKey: _coverArtCacheKey(song.coverArt ?? album.coverArt),
            ),
        ]);
      }
      if (segments.first == songSegment || segments.length == 4) {
        throw const RemoteProtocolError(
          code: 'SUBSONIC_NOT_A_FOLDER',
          userMessage: 'That item is a track, not a folder.',
        );
      }
      throw _badPath();
    } on SubsonicError catch (e, st) {
      throw _asRemoteError(e, st);
    }
  }

  /// Reads one object's metadata, or `null` when it no longer exists.
  @override
  Future<RemoteEntry?> stat(String path) async {
    final segments = _segments(path);
    try {
      if (segments.isEmpty) {
        return RemoteEntry(
          path: '',
          name: source.displayName,
          isDirectory: true,
        );
      }
      if (segments.length == 2 && segments.first == artistSegment) {
        final artistId = _decodeId(segments[1]);
        if (artistId == null) return null;
        final artist = await _api.getArtist(artistId);
        return RemoteEntry(
          path: artistPath(artist.id),
          name: artist.name,
          isDirectory: true,
          artworkUri: _coverArtUri(artist.coverArt),
          artworkCacheKey: _coverArtCacheKey(artist.coverArt),
        );
      }
      if (segments.length == 2 && segments.first == albumSegment) {
        final albumId = _decodeId(segments[1]);
        if (albumId == null) return null;
        final album = await _api.getAlbum(albumId);
        return RemoteEntry(
          path: albumPath(album.id),
          name: album.name,
          isDirectory: true,
          artworkUri: _coverArtUri(album.coverArt),
          artworkCacheKey: _coverArtCacheKey(album.coverArt),
        );
      }
      if (segments.length == 4 &&
          segments[0] == albumSegment &&
          segments[2] == songSegment) {
        final albumId = _decodeId(segments[1]);
        final songId = _decodeId(segments[3]);
        if (albumId == null || songId == null) return null;
        final album = await _api.getAlbum(albumId);
        for (final song in album.songs) {
          if (song.id != songId) continue;
          return RemoteEntry(
            path: songPath(album.id, song.id),
            name: _songName(song),
            isDirectory: false,
            sizeBytes: song.sizeBytes,
            artworkUri: _coverArtUri(song.coverArt ?? album.coverArt),
            artworkCacheKey: _coverArtCacheKey(song.coverArt ?? album.coverArt),
          );
        }
        return null;
      }
      return null;
    } on SubsonicError catch (e, st) {
      final mapped = _asRemoteError(e, st);
      // A missing album/artist is a plain miss for stat, not a failure: the
      // caller answers "unknown size" and can still play from the cache.
      if (mapped is RemoteNotFoundError) return null;
      throw mapped;
    }
  }

  /// Streams one track through its signed `stream` URL.
  ///
  /// A `Range` request is sent for every window; a server that ignores it
  /// (200 instead of 206) is handled by skipping [start] bytes locally, as the
  /// [RemoteFsProvider] contract requires.
  @override
  Stream<List<int>> openRead(String path, {int start = 0, int? end}) async* {
    if (start < 0) throw ArgumentError.value(start, 'start', 'must be >= 0');
    if (end != null && end < start) {
      throw ArgumentError.value(end, 'end', 'must be >= start');
    }
    final songId = _songIdFrom(path);
    if (songId == null) {
      throw const RemoteProtocolError(
        code: 'SUBSONIC_NOT_A_FILE',
        userMessage: 'That item is not a playable track.',
      );
    }

    final Uri uri;
    try {
      uri = _api.streamUrl(songId);
    } on SubsonicError catch (e, st) {
      throw _asRemoteError(e, st);
    }

    final fullRead = start == 0 && end == null;
    final request = http.Request('GET', uri);
    if (!fullRead) {
      request.headers[HttpHeaders.rangeHeader] = rangeHeader(start, end);
    }

    final http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(_timeout);
    } on TimeoutException catch (e, st) {
      throw _unreachable('The music server did not answer in time.', e, st);
    } on http.ClientException catch (e, st) {
      throw _unreachable('Could not reach the music server.', e, st);
    } on IOException catch (e, st) {
      throw _unreachable('Could not reach the music server.', e, st);
    }

    if (response.statusCode != 200 && response.statusCode != 206) {
      await _discard(response.stream);
      throw _statusError(response.statusCode);
    }

    final isPartial = response.statusCode == 206;
    var toSkip = isPartial ? 0 : start;
    var remaining = end == null ? -1 : end - start + 1;
    try {
      await for (final chunk in response.stream.timeout(_timeout)) {
        var data = chunk;
        if (toSkip > 0) {
          if (data.length <= toSkip) {
            toSkip -= data.length;
            continue;
          }
          data = data.sublist(toSkip);
          toSkip = 0;
        }
        if (remaining >= 0 && data.length > remaining) {
          data = data.sublist(0, remaining);
        }
        if (remaining >= 0) remaining -= data.length;
        if (data.isNotEmpty) yield data;
        if (remaining == 0) break;
      }
    } on TimeoutException catch (e, st) {
      throw _unreachable(
        'The music server stopped sending data. Check the connection.',
        e,
        st,
      );
    } on http.ClientException catch (e, st) {
      throw _unreachable(
          'The download was interrupted. Please try again.', e, st);
    } on IOException catch (e, st) {
      throw _unreachable(
          'The download was interrupted. Please try again.', e, st);
    }
  }

  /// Pings the server: the cheapest call that proves URL and credentials.
  @override
  Future<bool> testConnection() async {
    final watch = Stopwatch()..start();
    try {
      await _api.ping();
      ErrorLogger.log(
        'Subsonic probe succeeded in ${watch.elapsedMilliseconds} ms',
        category: 'RemoteSources',
        meta: {'authority': source.authority},
      );
      return true;
    } on SubsonicError catch (e, st) {
      ErrorLogger.log(
        'Subsonic probe failed: ${e.code}',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
        meta: {'authority': source.authority},
      );
      return false;
    } catch (e, st) {
      ErrorLogger.log(
        'Subsonic probe failed unexpectedly',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
        meta: {'authority': source.authority},
      );
      return false;
    }
  }

  /// Releases the HTTP client this provider created.
  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _api.close();
    if (_ownsClient) _client.close();
  }

  /// Searches the Subsonic library for artists, albums and tracks matching [query].
  Future<SubsonicSearchResult> search(
    String query, {
    int artistCount = 20,
    int artistOffset = 0,
    int albumCount = 20,
    int albumOffset = 0,
    int songCount = 50,
    int songOffset = 0,
  }) async {
    try {
      return await _api.search3(
        query,
        artistCount: artistCount,
        artistOffset: artistOffset,
        albumCount: albumCount,
        albumOffset: albumOffset,
        songCount: songCount,
        songOffset: songOffset,
      );
    } on SubsonicError catch (e, st) {
      throw _asRemoteError(e, st);
    }
  }

  /// Builds a signed cover art URI for [coverArtId], or `null` if blank or unresolvable.
  Uri? getCoverArtUrl(String? coverArtId, {int? size}) {
    if (coverArtId == null || coverArtId.trim().isEmpty) return null;
    try {
      return _api.getCoverArtUrl(coverArtId, size: size);
    } on SubsonicError {
      return null;
    }
  }

  /// Canonical, stable cache key for cover art that does NOT rotate with ephemeral
  /// salts or tokens (§8.5), enabling persistent image caching.
  String? getCoverArtCacheKey(String? coverArtId, {int? size}) {
    if (coverArtId == null || coverArtId.trim().isEmpty) return null;
    return _api.getCoverArtCacheKey(coverArtId, size: size);
  }

  String? _coverArtUri(String? coverArtId, {int? size}) =>
      getCoverArtUrl(coverArtId, size: size)?.toString();

  String? _coverArtCacheKey(String? coverArtId, {int? size}) =>
      getCoverArtCacheKey(coverArtId, size: size);

  /// Path of the artist with [id].
  static String artistPath(String id) => '$artistSegment/${_encodeId(id)}';

  /// Path of the album with [id].
  static String albumPath(String id) => '$albumSegment/${_encodeId(id)}';

  /// Path of one track inside its album.
  static String songPath(String albumId, String songId) =>
      '$albumSegment/${_encodeId(albumId)}/$songSegment/${_encodeId(songId)}';

  /// `Range` header value for a byte window.
  static String rangeHeader(int start, int? end) =>
      end == null ? 'bytes=$start-' : 'bytes=$start-$end';

  /// Splits [path] into non-empty segments.
  static List<String> _segments(String path) =>
      path.split('/').where((segment) => segment.isNotEmpty).toList();

  /// Encodes one id into a single path segment.
  static String _encodeId(String id) => Uri.encodeComponent(id);

  /// Decodes a path segment, or `null` when it is not valid percent-encoding.
  static String? _decodeId(String segment) {
    try {
      return Uri.decodeComponent(segment);
    } on ArgumentError {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// Song id addressed by [path], or `null` for anything but a song path.
  static String? _songIdFrom(String path) {
    final segments = _segments(path);
    if (segments.length != 4) return null;
    if (segments[0] != albumSegment || segments[2] != songSegment) return null;
    return _decodeId(segments[3]);
  }

  static String _songName(SubsonicSong song) => song.title;

  static List<RemoteEntry> _sorted(List<RemoteEntry> entries) =>
      entries..sort(RemoteEntry.compare);

  static const RemoteProtocolError _pathError = RemoteProtocolError(
    code: 'SUBSONIC_BAD_PATH',
    userMessage: 'That folder is not part of this library.',
  );

  static RemoteProtocolError _badPath() => _pathError;

  RemoteUnavailableError _unreachable(
    String message,
    Object cause,
    StackTrace stackTrace,
  ) {
    ErrorLogger.log(
      message,
      error: cause,
      stackTrace: stackTrace,
      category: 'RemoteSources',
      meta: {'authority': source.authority},
    );
    return RemoteUnavailableError(
      code: 'SUBSONIC_UNREACHABLE',
      userMessage: message,
      cause: cause,
      stackTrace: stackTrace,
    );
  }

  AppError _statusError(int status) {
    ErrorLogger.log(
      'Subsonic stream failed with HTTP $status',
      category: 'RemoteSources',
      meta: {'authority': source.authority},
    );
    if (status == 401 || status == 403) {
      return const RemoteAuthError(
        code: 'SUBSONIC_AUTH',
        userMessage: 'The music server rejected these credentials.',
      );
    }
    if (status == 404) {
      return const RemoteNotFoundError(
        code: 'SUBSONIC_NOT_FOUND',
        userMessage: 'This track is no longer on the server.',
      );
    }
    if (status == 416) {
      return const RemoteProtocolError(
        code: 'SUBSONIC_RANGE_UNSATISFIABLE',
        userMessage: 'The requested part of the file is outside its size.',
      );
    }
    if (status >= 500) {
      return RemoteUnavailableError(
        code: 'SUBSONIC_SERVER_ERROR',
        userMessage: 'The music server reported an error ($status). '
            'Try again later.',
      );
    }
    return RemoteProtocolError(
      code: 'SUBSONIC_HTTP_$status',
      userMessage: 'The music server rejected the request ($status).',
    );
  }

  /// Converts a client failure into the typed family the stream bridge knows.
  static AppError _asRemoteError(SubsonicError error, StackTrace stackTrace) {
    final apiCode = error.apiCode;
    if (apiCode == 40 || apiCode == 41 || apiCode == 50) {
      return RemoteAuthError(
        code: 'SUBSONIC_AUTH',
        userMessage: error.userMessage,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    if (apiCode == 70) {
      return RemoteNotFoundError(
        code: 'SUBSONIC_NOT_FOUND',
        userMessage: error.userMessage,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    if (error.code == 'SUBSONIC_TIMEOUT' || error.code == 'SUBSONIC_NETWORK') {
      return RemoteUnavailableError(
        code: 'SUBSONIC_UNREACHABLE',
        userMessage: error.userMessage,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    return RemoteProtocolError(
      code: error.code,
      userMessage: error.userMessage,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static Future<void> _discard(Stream<List<int>> stream) async {
    try {
      await stream.drain<void>();
    } on Object {
      // The body is being thrown away; a failed drain has no consequence.
    }
  }
}
