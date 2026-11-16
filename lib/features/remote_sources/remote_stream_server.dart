// lib/features/remote_sources/remote_stream_server.dart
//
// P0-1 "remote sources": the loopback HTTP bridge that turns any remote
// provider into a seekable URL for the existing player.
//
// GET /stream/<sourceId>/<token>/<base64url path> answers 200 with the whole
// file or 206 with a byte window, reusing the disk cache when the file was
// already downloaded and warming it while a full download streams through.
// Range arithmetic lives in remote_byte_range.dart on purpose: this module does
// not import the DLNA code, so the two cannot drift apart silently.
//
// Every URL carries a 128-bit token generated with [Random.secure] and checked
// on each request. The token is per source, survives a provider replacement
// (seeks keep working) and is revoked by [RemoteStreamServer.unregisterSource]
// or by deleting the source through [RemoteSourceStore], which calls
// [RemoteStreamServer.revokeSource]. A stale URL from a deleted library
// therefore answers 403/404 instead of streaming someone else's file.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../core/errors/app_error_base.dart';
import '../../core/utils/error_logger.dart';
import '../../domain/interfaces/remote_fs_provider.dart';
import '../../domain/models/remote_source.dart';
import 'remote_byte_range.dart';
import 'remote_cache_store.dart';
import 'remote_stream_pump.dart';

/// Loopback HTTP server that exposes providers as playable URLs.
class RemoteStreamServer {
  /// Creates the server. Nothing listens until [start] is awaited.
  ///
  /// [cache] is optional: without it every request reads straight from the
  /// provider.
  RemoteStreamServer({
    RemoteCacheStore? cache,
    this.maxChunkBytes = 128 * 1024,
  })  : _cache = cache,
        _pump = RemoteStreamPump(cache: cache, maxChunkBytes: maxChunkBytes);

  /// Size of the read window used when serving a cached file.
  final int maxChunkBytes;

  final RemoteCacheStore? _cache;
  final RemoteStreamPump _pump;
  final Map<String, RemoteFsProvider> _providers = <String, RemoteFsProvider>{};
  final Map<String, String> _tokens = <String, String>{};

  /// Servers whose socket is accepting connections; used by [revokeSource] so
  /// a deleted library stops streaming even when its owner forgot to call
  /// [unregisterSource].
  static final Set<RemoteStreamServer> _live = <RemoteStreamServer>{};

  HttpServer? _server;
  StreamSubscription<HttpRequest>? _subscription;
  Future<void>? _starting;

  /// Port the server listens on, or `0` before [start].
  int get port => _server?.port ?? 0;

  /// Whether [start] completed and the socket is accepting connections.
  bool get isRunning => _server != null;

  /// Makes [provider] reachable under its source id.
  ///
  /// A previous provider for the same id is replaced and closed: keeping it
  /// alive would leak a socket (FTP) or a native SMB session per song. The
  /// token is deliberately *not* rotated here, so a stream URL the player is
  /// already using keeps working across a provider swap.
  Future<void> registerProvider(RemoteFsProvider provider) async {
    final sourceId = provider.source.id;
    final previous = _providers[sourceId];
    _providers[sourceId] = provider;
    _tokens.putIfAbsent(sourceId, _newToken);
    if (previous != null && !identical(previous, provider)) {
      await _closeQuietly(previous);
    }
  }

  /// Revokes [sourceId]'s token, drops its provider and closes it.
  ///
  /// Call this when a library is deleted or disabled; every URL handed out for
  /// it stops working immediately.
  Future<void> unregisterSource(
    String sourceId, {
    bool closeProvider = true,
  }) async {
    _tokens.remove(sourceId);
    final provider = _providers.remove(sourceId);
    if (closeProvider && provider != null) await _closeQuietly(provider);
  }

  /// Revokes [sourceId] on every live server in this isolate.
  ///
  /// [RemoteSourceStore] calls this after a delete so a deleted library cannot
  /// keep serving a token that was already handed to the player.
  static Future<void> revokeSource(String sourceId) async {
    for (final server in _live.toList(growable: false)) {
      await server.unregisterSource(sourceId);
    }
  }

  /// Builds the URL a player should open for [path] on [source].
  ///
  /// Throws [StateError] when the server has not been started, because the URL
  /// would carry port 0 and no player could connect to it.
  Uri uriFor(RemoteSource source, String path) {
    if (!isRunning) {
      throw StateError('Await RemoteStreamServer.start() before uriFor().');
    }
    final token = _tokens[source.id] ??= _newToken();
    final encoded = base64UrlEncode(utf8.encode(path)).replaceAll('=', '');
    return Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: port,
      pathSegments: <String>['stream', source.id, token, encoded],
    );
  }

  /// A fresh 128-bit URL segment from the platform CSPRNG.
  static String _newToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Starts listening on an ephemeral loopback port; safe to call twice.
  Future<void> start() async {
    if (_server != null) return;
    final existing = _starting;
    if (existing != null) {
      await existing;
      return;
    }
    final future = _bind();
    _starting = future;
    try {
      await future;
    } finally {
      _starting = null;
    }
  }

  Future<void> _bind() async {
    try {
      final server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
        shared: false,
      );
      server.autoCompress = false;
      _server = server;
      _live.add(this);
      _subscription = server.listen(
        _handleRequest,
        onError: (Object error, StackTrace stackTrace) {
          ErrorLogger.log(
            'Remote stream server socket error',
            error: error,
            stackTrace: stackTrace,
            category: 'RemoteSources',
          );
        },
      );
    } on SocketException catch (e, st) {
      ErrorLogger.log(
        'Could not bind the remote stream server to loopback',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
      );
      rethrow;
    }
  }

  /// Stops listening, revokes every token and closes registered providers.
  Future<void> stop({bool closeProviders = true}) async {
    final server = _server;
    final subscription = _subscription;
    _server = null;
    _subscription = null;
    _live.remove(this);
    await subscription?.cancel();
    if (server != null) await server.close(force: true);
    _tokens.clear();
    if (closeProviders) {
      final providers = _providers.values.toList(growable: false);
      _providers.clear();
      for (final provider in providers) {
        await _closeQuietly(provider);
      }
    }
  }

  Future<void> _closeQuietly(RemoteFsProvider provider) async {
    try {
      await provider.close();
    } catch (e, st) {
      ErrorLogger.log(
        'Remote provider did not close cleanly',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
        meta: {'authority': provider.source.authority},
      );
    }
  }

  /// Parses a `Range: bytes=` header against [totalLength].
  ///
  /// Supports `start-end`, `start-` and `-suffix`. A syntactically valid header
  /// that points past the end of the file marks [unsatisfiable] so the caller
  /// can answer 416 instead of silently sending the whole file.
  /// Parses a Range header against [totalLength].
  ///
  /// Delegates to [parseRemoteRangeHeader]; every branch is covered by the
  /// range unit tests.
  static RemoteRangeParseResult parseRangeHeader(
    String? header, {
    required int totalLength,
  }) =>
      parseRemoteRangeHeader(header, totalLength: totalLength);

  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.contentType = ContentType.binary;
    try {
      final segments = request.uri.pathSegments;
      if (segments.length < 4 || segments.first != 'stream') {
        await _pump.sendText(response, HttpStatus.notFound, 'Not a stream URL.');
        return;
      }
      if (request.method != 'GET' && request.method != 'HEAD') {
        response.headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
        await _pump.sendText(response, HttpStatus.methodNotAllowed, 'GET only.');
        return;
      }
      if (segments.any(_isTraversalSegment)) {
        await _pump.sendText(
          response,
          HttpStatus.badRequest,
          'Bad stream path.',
        );
        return;
      }
      final sourceId = segments[1];
      final token = segments[2];
      final provider = _providers[sourceId];
      if (provider == null) {
        await _pump.sendText(
          response,
          HttpStatus.notFound,
          'No remote source is registered for this id.',
        );
        return;
      }
      final expected = _tokens[sourceId];
      if (expected == null || !_tokensMatch(token, expected)) {
        await _pump.sendText(
          response,
          HttpStatus.forbidden,
          'Invalid stream token.',
        );
        return;
      }
      final path = _decodePath(segments.sublist(3).join('/'));
      if (path == null || _hasTraversal(path)) {
        await _pump.sendText(response, HttpStatus.badRequest, 'Bad stream path.');
        return;
      }
      await _serve(request, response, provider, path);
    } on RemoteAuthError catch (e) {
      ErrorLogger.log(
        'Remote stream request was rejected: ${e.code}',
        error: e,
        category: 'RemoteSources',
      );
      await _pump.sendText(response, HttpStatus.forbidden, e.userMessage);
    } on RemoteNotFoundError catch (e) {
      await _pump.sendText(response, HttpStatus.notFound, e.userMessage);
    } on RemoteUnavailableError catch (e, st) {
      ErrorLogger.log(
        'Remote stream request could not reach the server: ${e.code}',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
      );
      await _pump.sendText(response, HttpStatus.badGateway, e.userMessage);
    } on RemoteProtocolError catch (e, st) {
      ErrorLogger.log(
        'Remote stream request failed in the protocol layer: ${e.code}',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
      );
      await _pump.sendText(response, HttpStatus.badGateway, e.userMessage);
    } catch (e, st) {
      ErrorLogger.log(
        'Remote stream request failed unexpectedly',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
      );
      await _pump.sendText(response, HttpStatus.internalServerError, 'Stream failed.');
    }
  }

  Future<void> _serve(
    HttpRequest request,
    HttpResponse response,
    RemoteFsProvider provider,
    String path,
  ) async {
    final sourceId = provider.source.id;
    // One stat per request is the price of never serving stale audio: the
    // cache entry carries the validators from the download, and a server-side
    // change (re-encoded file, replaced track) invalidates it here. A cached
    // file is still playable when the library is temporarily unreachable.
    final cachedFile = await _cache?.lookup(sourceId, path);
    RemoteEntry? stat;
    try {
      stat = await provider.stat(path);
    } on AppError catch (e, st) {
      if (cachedFile == null) rethrow;
      ErrorLogger.log(
        'Remote stat failed; serving the cached copy of this file',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
        meta: {'authority': provider.source.authority},
      );
    }
    final cached = cachedFile == null
        ? null
        : await _cache!.lookup(
            sourceId,
            path,
            etag: stat?.etag,
            modifiedAt: stat?.modifiedAt,
          );
    final cachedLength = cached != null ? await cached.length() : null;
    final totalLength = cachedLength ?? stat?.sizeBytes;
    final headOnly = request.method == 'HEAD';
    if (totalLength == null || totalLength <= 0) {
      // The size is unknown (or the file is empty): serve the body directly and
      // skip range handling, because a 206 without a total is not valid.
      response.statusCode = HttpStatus.ok;
      if (headOnly) {
        await response.close();
        return;
      }
      await _pump.sendFromProvider(response, provider, path);
      return;
    }
    final parsed = parseRangeHeader(
      request.headers.value(HttpHeaders.rangeHeader),
      totalLength: totalLength,
    );
    if (parsed.unsatisfiable) {
      response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes */$totalLength',
      );
      await response.close();
      return;
    }
    final range = parsed.range;
    if (range == null) {
      response.statusCode = HttpStatus.ok;
    } else {
      response.statusCode = HttpStatus.partialContent;
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes ${range.start}-${range.end}/$totalLength',
      );
    }
    // Content-Length is only promised when a local file proves the byte count
    // (or for HEAD, where a metadata answer cannot truncate a body). A live
    // provider stream is framed as chunked: a server that reports a size but
    // sends fewer bytes would otherwise leave the player waiting forever.
    if (cached != null) {
      response.contentLength = range?.length ?? cachedLength!;
    } else if (headOnly) {
      response.contentLength = range?.length ?? totalLength;
    }
    if (headOnly) {
      await response.close();
      return;
    }
    if (cached != null) {
      await _pump.sendFile(response, cached, range);
      return;
    }
    final sink = range == null
        ? await _pump.startCacheWrite(
            provider.source.id,
            path,
            etag: stat?.etag,
            modifiedAt: stat?.modifiedAt,
          )
        : null;
    await _pump.sendFromProvider(
      response,
      provider,
      path,
      start: range?.start ?? 0,
      end: range?.end,
      sink: sink,
    );
  }

  /// True for a `.`/`..` segment or a percent-encoded spelling of `..`.
  static bool _isTraversalSegment(String segment) {
    if (segment.isEmpty) return false;
    if (segment == '.') return false;
    if (segment == '..') return true;
    try {
      return Uri.decodeComponent(segment) == '..';
    } on ArgumentError {
      return true;
    } on FormatException {
      return true;
    }
  }

  /// True when [path] contains a `..` segment after base64 decoding.
  static bool _hasTraversal(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.split('/').any(_isTraversalSegment);
  }

  /// Constant-time-ish comparison so a token cannot be discovered byte by byte.
  static bool _tokensMatch(String candidate, String expected) {
    if (candidate.length != expected.length) return false;
    var diff = 0;
    for (var i = 0; i < candidate.length; i++) {
      diff |= candidate.codeUnitAt(i) ^ expected.codeUnitAt(i);
    }
    return diff == 0;
  }

  String? _decodePath(String encoded) {
    if (encoded.isEmpty) return '';
    try {
      final padded = encoded.padRight((encoded.length + 3) & ~3, '=');
      return utf8.decode(base64Url.decode(padded));
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }
}