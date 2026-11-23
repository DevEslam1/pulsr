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
  /// provider. [statTtl] bounds how long one provider stat may answer for the
  /// same path; [clock] is injectable so tests can move time without waiting.
  RemoteStreamServer({
    RemoteCacheStore? cache,
    this.maxChunkBytes = 128 * 1024,
    this.statTtl = const Duration(seconds: 5),
    DateTime Function()? clock,
  })  : _cache = cache,
        _clock = clock ?? DateTime.now,
        _pump = RemoteStreamPump(cache: cache, maxChunkBytes: maxChunkBytes);

  /// Size of the read window used when serving a cached file.
  final int maxChunkBytes;

  /// How long one provider stat may answer requests for the same path.
  ///
  /// A player opens a stream once and then seeks in it, so one path is statted
  /// several times within a second; each of those is a round trip (FTP) or a
  /// metadata request (WebDAV/SMB) for a file that cannot change in between.
  /// Five seconds removes almost all of that traffic while still noticing a
  /// replaced track quickly, and a disk cache commit or delete shortens it
  /// further (see [_statFor]). `Duration.zero` disables the memo entirely.
  final Duration statTtl;

  /// Bound on memoized stats before expired ones are pruned.
  static const int _statCacheSoftLimit = 256;

  final RemoteCacheStore? _cache;
  final RemoteStreamPump _pump;
  final DateTime Function() _clock;
  final Map<String, RemoteFsProvider> _providers = <String, RemoteFsProvider>{};
  final Map<String, String> _tokens = <String, String>{};
  final Set<String> _pinnedStreamKeys = <String>{};

  /// Recent provider stats, keyed like the disk cache ([RemoteCacheStore.keyFor]).
  final Map<String, _StatMemo> _statCache = <String, _StatMemo>{};

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

  /// Whether a provider is registered for [sourceId].
  bool hasProvider(String sourceId) => _providers.containsKey(sourceId);

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
    // The replacement may be a different backend (another share, another
    // account), so nothing statted through the previous one is reusable.
    _forgetStats(sourceId);
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
    _forgetStats(sourceId);
    _pinnedStreamKeys.removeWhere((key) => key.startsWith('$sourceId/'));
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
  /// When [pin] is true, the stream server pins the cache entry atomically
  /// when caching begins during streaming. Throws [StateError] when the server
  /// has not been started, because the URL would carry port 0 and no player
  /// could connect to it.
  Uri uriFor(RemoteSource source, String path, {bool pin = false}) {
    if (!isRunning) {
      throw StateError('Await RemoteStreamServer.start() before uriFor().');
    }
    final key = RemoteCacheStore.keyFor(source.id, path);
    if (pin) {
      _pinnedStreamKeys.add(key);
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
    _statCache.clear();
    _pinnedStreamKeys.clear();
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
    } on IOException catch (e) {
      ErrorLogger.log(
        'Remote stream client closed the socket: $e',
        category: 'RemoteSources',
      );
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

  /// Infers an audio `Content-Type` from [path]'s extension when recognized.
  static ContentType contentTypeForPath(String path) {
    final trimmed = path.trim().toLowerCase();
    final dot = trimmed.lastIndexOf('.');
    if (dot < 0 || dot == trimmed.length - 1) return ContentType.binary;
    switch (trimmed.substring(dot + 1)) {
      case 'mp3':
        return ContentType('audio', 'mpeg');
      case 'flac':
        return ContentType('audio', 'flac');
      case 'm4a':
      case 'm4b':
      case 'mp4':
        return ContentType('audio', 'mp4');
      case 'aac':
        return ContentType('audio', 'aac');
      case 'ogg':
      case 'oga':
        return ContentType('audio', 'ogg');
      case 'opus':
        return ContentType('audio', 'opus');
      case 'wav':
        return ContentType('audio', 'wav');
      case 'wma':
        return ContentType('audio', 'x-ms-wma');
      case 'aiff':
      case 'aif':
        return ContentType('audio', 'aiff');
      case 'alac':
        return ContentType('audio', 'alac');
      case 'dsf':
        return ContentType('audio', 'dsf');
      case 'dff':
        return ContentType('audio', 'x-dff');
      case 'wv':
        return ContentType('audio', 'x-wavpack');
      default:
        return ContentType.binary;
    }
  }

  Future<void> _serve(
    HttpRequest request,
    HttpResponse response,
    RemoteFsProvider provider,
    String path,
  ) async {
    response.headers.contentType = contentTypeForPath(path);
    final sourceId = provider.source.id;
    // Stat first, then one cache lookup carrying those validators: a cached
    // copy can only be judged stale once the server's current etag/mtime is
    // known, and asking the cache before the stat cost a second lookup on every
    // hit. When the library is unreachable the lookup runs without validators
    // ("did not say" keeps the entry), so a cached file stays playable.
    RemoteEntry? stat;
    AppError? statFailure;
    StackTrace? statStackTrace;
    try {
      stat = await _statFor(provider, path);
    } on AppError catch (e, st) {
      statFailure = e;
      statStackTrace = st;
    }
    final cached = await _cache?.lookup(
      sourceId,
      path,
      etag: stat?.etag,
      modifiedAt: stat?.modifiedAt,
    );
    if (statFailure != null) {
      if (cached == null) {
        // Nothing to fall back on: report the failure as the request expects.
        Error.throwWithStackTrace(statFailure, statStackTrace!);
      }
      ErrorLogger.log(
        'Remote stat failed; serving the cached copy of this file',
        error: statFailure,
        stackTrace: statStackTrace,
        category: 'RemoteSources',
        meta: {'authority': provider.source.authority},
      );
    }
    final cachedLength = cached != null ? await cached.length() : null;
    final totalLength = cachedLength ?? stat?.sizeBytes;
    final headOnly = request.method == 'HEAD';
    if (totalLength == null) {
      // The size is unknown: serve the body directly and skip range handling,
      // because a 206 without a total is not valid.
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
    final cacheKey = RemoteCacheStore.keyFor(sourceId, path);
    final shouldPin = _pinnedStreamKeys.remove(cacheKey);
    final sink = range == null
        ? await _pump.startCacheWrite(
            sourceId,
            path,
            etag: stat?.etag,
            modifiedAt: stat?.modifiedAt,
            pin: shouldPin,
          )
        : null;
    await _pump.sendFromProvider(
      response,
      provider,
      path,
      start: range?.start ?? 0,
      end: range?.end,
      sink: sink,
      expectedLength: range?.length ?? totalLength,
    );
  }

  /// Provider stat for [provider]/[path], reused for [statTtl].
  ///
  /// The memo is keyed exactly like the disk cache ([RemoteCacheStore.keyFor])
  /// and remembers [RemoteCacheStore.changeStamp], so a commit, an eviction or
  /// a delete forces the next request to ask the provider again instead of
  /// reusing a size/validators snapshot for bytes that just changed on disk.
  Future<RemoteEntry?> _statFor(RemoteFsProvider provider, String path) async {
    final key = RemoteCacheStore.keyFor(provider.source.id, path);
    final memo = _freshStat(key);
    if (memo != null) return memo.entry;
    // Read before the stat: a cache change that lands while the stat is in
    // flight must not be mistaken for the state the stat was taken in.
    final stamp = _changeStampOrNull();
    final stat = await provider.stat(path);
    _rememberStat(key, stat, stamp);
    return stat;
  }

  /// The disk cache's change stamp, or `null` when it cannot be read.
  ///
  /// `null` means "no invalidation information": memos are then bounded by
  /// [statTtl] alone, which is still better than statting on every seek.
  int? _changeStampOrNull() {
    try {
      return _cache?.changeStamp;
    } catch (e, st) {
      ErrorLogger.log(
        'Remote cache change stamp could not be read; stats expire by TTL only',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
      );
      return null;
    }
  }

  /// The memoized stat for [key] while it is still fresh, else `null`.
  ///
  /// Reading the memo is an optimisation only, so a surprise here is logged and
  /// answered by a direct stat rather than failing the request.
  _StatMemo? _freshStat(String key) {
    final memo = _statCache[key];
    if (memo == null) return null;
    try {
      if (memo.isFresh(_clock(), statTtl, _changeStampOrNull())) return memo;
    } catch (e, st) {
      ErrorLogger.log(
        'Remote stat cache could not be read; doing a direct stat',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
      );
    }
    _statCache.remove(key);
    return null;
  }

  /// Remembers [stat] for [key], stamped with [stamp].
  ///
  /// A provider that reports a miss is not memoized: the file may appear
  /// shortly (an upload finishing, a folder being synced) and the next request
  /// must see it.
  void _rememberStat(String key, RemoteEntry? stat, int? stamp) {
    if (stat == null) {
      _statCache.remove(key);
      return;
    }
    try {
      _pruneStats();
      _statCache[key] = _StatMemo(stat, _clock(), stamp);
    } catch (e, st) {
      ErrorLogger.log(
        'Remote stat cache could not be written; serving without it',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
      );
    }
  }

  /// Drops expired memos once the map grows past [_statCacheSoftLimit].
  void _pruneStats() {
    if (_statCache.length < _statCacheSoftLimit) return;
    final now = _clock();
    _statCache.removeWhere((_, memo) => !memo.isFreshFor(now, statTtl));
  }

  /// Forgets every memo of [sourceId]; used when its provider changes hands.
  void _forgetStats(String sourceId) {
    final prefix = '$sourceId/';
    _statCache.removeWhere((key, _) => key.startsWith(prefix));
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

/// One provider stat, remembered for [RemoteStreamServer.statTtl].
class _StatMemo {
  const _StatMemo(this.entry, this.takenAt, this.stamp);

  /// What the provider reported.
  final RemoteEntry entry;

  /// When the stat was taken, from the server's injectable clock.
  final DateTime takenAt;

  /// [RemoteCacheStore.changeStamp] when the stat started, or `null` without a
  /// cache.
  final int? stamp;

  /// Whether this memo is younger than [ttl].
  bool isFreshFor(DateTime now, Duration ttl) =>
      ttl > Duration.zero && now.difference(takenAt) < ttl;

  /// Whether the request may be answered from this memo.
  bool isFresh(DateTime now, Duration ttl, int? currentStamp) =>
      isFreshFor(now, ttl) && stamp == currentStamp;
}