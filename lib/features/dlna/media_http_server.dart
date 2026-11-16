// lib/features/dlna/media_http_server.dart
//
// Loopback-bound HTTP file server used as the DLNA media source. URLs carry an
// opaque token only: the server resolves tokens through its registry and never
// turns a URL path into a filesystem path.
import 'dart:async';
import 'dart:io';

import '../../core/utils/error_logger.dart';

/// A media item the DLNA renderer can fetch.
class MediaSource {
  /// Absolute path of the file to serve, when this is a file source.
  final String? filePath;

  /// MIME type override; derived from the extension for file sources when
  /// omitted.
  final String? contentType;

  final Future<List<int>> Function()? _loadBytes;

  /// Serves [path] from disk.
  const MediaSource.file(String path, {this.contentType})
      : filePath = path,
        _loadBytes = null;

  /// Serves bytes produced by [loader] (used for in-memory or generated media).
  const MediaSource.bytes(
    Future<List<int>> Function() loader, {
    required this.contentType,
  })  : filePath = null,
        _loadBytes = loader;

  /// True when the source reads from disk.
  bool get isFile => filePath != null;

  Future<List<int>> _bytes() async {
    final loader = _loadBytes;
    if (loader == null) {
      throw StateError('MediaSource has neither a path nor a byte loader.');
    }
    return loader();
  }
}

/// Serves registered [MediaSource]s over HTTP 1.1 with single byte ranges.
///
/// Tokens are registered by the renderer service, capped at [maxEntries] and
/// expire after [tokenTtl]. Every request is answered from the registry; the
/// URL never selects a file on its own.
class MediaHttpServer {
  /// Largest number of tokens kept alive at once.
  final int maxEntries;

  /// How long a token stays valid after registration.
  final Duration tokenTtl;

  final InternetAddress _bindAddress;
  final Map<String, _MediaEntry> _entries = <String, _MediaEntry>{};

  HttpServer? _server;
  StreamSubscription<HttpRequest>? _subscription;
  String _host = InternetAddress.loopbackIPv4.address;

  /// Creates a server. [bindAddress] defaults to all IPv4 interfaces so a LAN
  /// renderer can reach it.
  MediaHttpServer({
    this.maxEntries = 32,
    this.tokenTtl = const Duration(hours: 6),
    InternetAddress? bindAddress,
  })  : assert(maxEntries > 0, 'maxEntries must be positive'),
        _bindAddress = bindAddress ?? InternetAddress.anyIPv4;

  /// Bound port, or `null` before [start].
  int? get port => _server?.port;

  /// True between [start] and [stop].
  bool get isRunning => _server != null;

  /// Starts listening on an ephemeral port. Safe to call twice.
  Future<void> start() async {
    if (_server != null) return;
    try {
      final server = await HttpServer.bind(_bindAddress, 0);
      _server = server;
      _host = await _detectHost();
      _subscription = server.listen(
        (request) {
          unawaited(_handle(request));
        },
        onError: (Object error, StackTrace stackTrace) {
          ErrorLogger.log(
            'DLNA media server socket error',
            error: error,
            stackTrace: stackTrace,
            category: 'DLNA',
          );
        },
      );
    } on SocketException catch (error, stackTrace) {
      ErrorLogger.log(
        'DLNA media server failed to bind',
        error: error,
        stackTrace: stackTrace,
        category: 'DLNA',
      );
      rethrow;
    }
  }

  /// Registers [source] under [token], evicting expired and oldest entries.
  void register(String token, MediaSource source) {
    if (token.isEmpty) {
      throw ArgumentError.value(token, 'token', 'Token must not be empty');
    }
    _entries[token] = _MediaEntry(
      source: source,
      expiresAt: DateTime.now().add(tokenTtl),
    );
    _prune();
  }

  /// Removes [token]; returns whether it was registered and still valid.
  bool unregister(String token) => _entries.remove(token) != null;

  /// Absolute URL a renderer can fetch [token] from.
  Uri uriFor(String token) {
    final server = _server;
    if (server == null) {
      throw StateError('MediaHttpServer.start() must be called first.');
    }
    return Uri(
      scheme: 'http',
      host: _host,
      port: server.port,
      pathSegments: <String>['media', token],
    );
  }

  /// Stops the server, drops every token, and is safe to call repeatedly.
  Future<void> stop() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    final server = _server;
    _server = null;
    _entries.clear();
    if (server != null) await server.close(force: true);
  }

  /// MIME type derived from a file name's extension.
  static String contentTypeFor(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return 'application/octet-stream';
    switch (name.substring(dot + 1).toLowerCase()) {
      case 'mp3':
        return 'audio/mpeg';
      case 'm4a':
      case 'm4b':
      case 'mp4':
        return 'audio/mp4';
      case 'aac':
        return 'audio/aac';
      case 'flac':
        return 'audio/flac';
      case 'wav':
        return 'audio/wav';
      case 'ogg':
      case 'oga':
      case 'opus':
        return 'audio/ogg';
      case 'wma':
        return 'audio/x-ms-wma';
      case 'aiff':
      case 'aif':
        return 'audio/aiff';
      default:
        return 'application/octet-stream';
    }
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      await _dispatch(request);
    } catch (error, stackTrace) {
      ErrorLogger.log(
        'DLNA media request failed',
        error: error,
        stackTrace: stackTrace,
        category: 'DLNA',
      );
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (closeError, closeStack) {
        ErrorLogger.log(
          'DLNA media response close failed',
          error: closeError,
          stackTrace: closeStack,
          category: 'DLNA',
        );
      }
    }
  }

  Future<void> _dispatch(HttpRequest request) async {
    final method = request.method;
    if (method != 'GET' && method != 'HEAD') {
      request.response
        ..statusCode = HttpStatus.methodNotAllowed
        ..headers.set(HttpHeaders.allowHeader, 'GET, HEAD')
        ..headers.set(HttpHeaders.contentLengthHeader, '0');
      await request.response.close();
      return;
    }

    final segments = request.uri.pathSegments;
    if (segments.length != 2 || segments.first != 'media') {
      await _writeEmpty(request.response, HttpStatus.notFound);
      return;
    }

    final entry = _lookup(segments[1]);
    if (entry == null) {
      await _writeEmpty(request.response, HttpStatus.notFound);
      return;
    }

    final source = entry.source;
    final bytes = source.isFile ? null : await source._bytes();
    final size = source.isFile
        ? await File(source.filePath!).length()
        : bytes?.length ?? 0;

    final range = _parseRange(
      request.headers.value(HttpHeaders.rangeHeader),
      size,
    );
    if (range.status == _RangeStatus.unsatisfiable) {
      request.response
        ..statusCode = HttpStatus.requestedRangeNotSatisfiable
        ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..headers.set(HttpHeaders.contentRangeHeader, 'bytes */$size')
        ..headers.set(HttpHeaders.contentLengthHeader, '0');
      await request.response.close();
      return;
    }

    final start = range.status == _RangeStatus.satisfiable ? range.start : 0;
    final end = range.status == _RangeStatus.satisfiable ? range.end : size - 1;
    final length = size == 0 ? 0 : end - start + 1;
    final contentType = source.contentType ??
        (source.filePath == null
            ? 'application/octet-stream'
            : contentTypeFor(source.filePath!));

    final response = request.response
      ..statusCode = range.status == _RangeStatus.satisfiable
          ? HttpStatus.partialContent
          : HttpStatus.ok
      ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..headers.set(HttpHeaders.contentTypeHeader, contentType)
      ..headers.set(HttpHeaders.contentLengthHeader, '$length');
    if (range.status == _RangeStatus.satisfiable) {
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$size',
      );
    }

    if (request.method == 'HEAD' || length == 0) {
      await response.close();
      return;
    }

    if (source.isFile) {
      try {
        await response.addStream(File(source.filePath!).openRead(start, end + 1));
      } on FileSystemException catch (error, stackTrace) {
        ErrorLogger.log(
          'DLNA media file read failed',
          error: error,
          stackTrace: stackTrace,
          category: 'DLNA',
        );
        await response.close();
        return;
      }
    } else {
      final slice = bytes!.sublist(start, end + 1);
      response.add(slice);
    }
    await response.close();
  }

  Future<void> _writeEmpty(HttpResponse response, int statusCode) async {
    response
      ..statusCode = statusCode
      ..headers.set(HttpHeaders.contentLengthHeader, '0');
    await response.close();
  }

  _MediaEntry? _lookup(String token) {
    _prune();
    return _entries[token];
  }

  void _prune() {
    final now = DateTime.now();
    _entries.removeWhere((_, entry) => !entry.expiresAt.isAfter(now));
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  _RangeOutcome _parseRange(String? header, int size) {
    if (header == null || header.isEmpty) return const _RangeOutcome.none();
    if (!header.toLowerCase().startsWith('bytes=')) {
      return const _RangeOutcome.none();
    }
    final spec = header.substring(6).trim();
    if (spec.isEmpty || spec.contains(',')) {
      return const _RangeOutcome.unsatisfiable();
    }
    final dash = spec.indexOf('-');
    if (dash < 0) return const _RangeOutcome.unsatisfiable();

    final startText = spec.substring(0, dash).trim();
    final endText = spec.substring(dash + 1).trim();

    if (startText.isEmpty) {
      final suffix = int.tryParse(endText);
      if (suffix == null || suffix <= 0 || size == 0) {
        return const _RangeOutcome.unsatisfiable();
      }
      final start = suffix >= size ? 0 : size - suffix;
      return _RangeOutcome.satisfiable(start, size - 1);
    }

    final start = int.tryParse(startText);
    if (start == null || start < 0 || start >= size) {
      return const _RangeOutcome.unsatisfiable();
    }
    var end = size - 1;
    if (endText.isNotEmpty) {
      final parsed = int.tryParse(endText);
      if (parsed == null || parsed < start) {
        return const _RangeOutcome.unsatisfiable();
      }
      if (parsed < size) end = parsed;
    }
    return _RangeOutcome.satisfiable(start, end);
  }

  Future<String> _detectHost() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (address.address.startsWith('169.254.')) continue;
          return address.address;
        }
      }
    } on SocketException catch (error, stackTrace) {
      ErrorLogger.log(
        'DLNA media host detection failed',
        error: error,
        stackTrace: stackTrace,
        category: 'DLNA',
      );
    }
    return InternetAddress.loopbackIPv4.address;
  }
}

class _MediaEntry {
  final MediaSource source;
  final DateTime expiresAt;

  const _MediaEntry({required this.source, required this.expiresAt});
}

enum _RangeStatus { none, satisfiable, unsatisfiable }

class _RangeOutcome {
  final _RangeStatus status;
  final int start;
  final int end;

  const _RangeOutcome.none()
      : status = _RangeStatus.none,
        start = 0,
        end = 0;

  const _RangeOutcome.unsatisfiable()
      : status = _RangeStatus.unsatisfiable,
        start = 0,
        end = 0;

  const _RangeOutcome.satisfiable(this.start, this.end)
      : status = _RangeStatus.satisfiable;
}
