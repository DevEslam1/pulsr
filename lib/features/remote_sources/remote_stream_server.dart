// lib/features/remote_sources/remote_stream_server.dart
//
// P0-1 "remote sources": the loopback HTTP bridge that turns any remote
// provider into a seekable URL for the existing player.
//
// GET /stream/<sourceId>/<base64url path> answers 200 with the whole file or
// 206 with a byte window, reusing the disk cache when the file was already
// downloaded and warming it while a full download streams through. Range
// arithmetic lives in remote_byte_range.dart on purpose: this module does not
// import the DLNA code, so the two cannot drift apart silently.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  HttpServer? _server;
  StreamSubscription<HttpRequest>? _subscription;
  Future<void>? _starting;

  /// Port the server listens on, or `0` before [start].
  int get port => _server?.port ?? 0;

  /// Whether [start] completed and the socket is accepting connections.
  bool get isRunning => _server != null;

  /// Makes [provider] reachable under its source id.
  void registerProvider(RemoteFsProvider provider) {
    _providers[provider.source.id] = provider;
  }

  /// Removes the provider registered for [sourceId] (the provider is not
  /// closed here; the owner decides its lifetime).
  void unregisterProvider(String sourceId) {
    _providers.remove(sourceId);
  }

  /// Builds the URL a player should open for [path] on [source].
  ///
  /// Throws [StateError] when the server has not been started, because the URL
  /// would carry port 0 and no player could connect to it.
  Uri uriFor(RemoteSource source, String path) {
    if (!isRunning) {
      throw StateError('Await RemoteStreamServer.start() before uriFor().');
    }
    final encoded = base64UrlEncode(utf8.encode(path)).replaceAll('=', '');
    return Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: port,
      pathSegments: <String>['stream', source.id, encoded],
    );
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

  /// Stops listening and closes the registered providers.
  Future<void> stop({bool closeProviders = true}) async {
    final server = _server;
    final subscription = _subscription;
    _server = null;
    _subscription = null;
    await subscription?.cancel();
    if (server != null) await server.close(force: true);
    if (closeProviders) {
      final providers = _providers.values.toList(growable: false);
      _providers.clear();
      for (final provider in providers) {
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
      if (segments.length < 3 || segments.first != 'stream') {
        await _pump.sendText(response, HttpStatus.notFound, 'Not a stream URL.');
        return;
      }
      if (request.method != 'GET' && request.method != 'HEAD') {
        response.headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
        await _pump.sendText(response, HttpStatus.methodNotAllowed, 'GET only.');
        return;
      }
      final sourceId = segments[1];
      final path = _decodePath(segments.sublist(2).join('/'));
      if (path == null) {
        await _pump.sendText(response, HttpStatus.badRequest, 'Bad stream path.');
        return;
      }
      final provider = _providers[sourceId];
      if (provider == null) {
        await _pump.sendText(
          response,
          HttpStatus.notFound,
          'No remote source is registered for this id.',
        );
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
    final cached = await _cache?.lookup(sourceId, path);
    final totalLength = cached != null
        ? await cached.length()
        : (await provider.stat(path))?.sizeBytes;
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
      response.contentLength = totalLength;
    } else {
      response.statusCode = HttpStatus.partialContent;
      response.contentLength = range.length;
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes ${range.start}-${range.end}/$totalLength',
      );
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
        ? await _pump.startCacheWrite(provider.source.id, path)
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