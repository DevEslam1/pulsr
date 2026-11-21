// lib/features/remote_sources/webdav_fs_provider.dart
//
// P0-1 "remote sources": WebDAV over HTTP/1.1 (dart:io HttpClient).
//
// Listing uses PROPFIND with Depth: 1 and a namespace-tolerant reader (see
// webdav_multistatus.dart); reads use a ranged GET and stream the response
// straight through. TLS certificates are always validated: this provider never
// installs a badCertificateCallback, so a self-signed host fails loudly instead
// of quietly downgrading the connection.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/errors/app_error_base.dart';
import '../../core/utils/error_logger.dart';
import '../../domain/interfaces/remote_fs_provider.dart';
import '../../domain/models/remote_source.dart';
import 'webdav_errors.dart';
import 'webdav_multistatus.dart';

/// WebDAV implementation of [RemoteFsProvider].
class WebDavFsProvider implements RemoteFsProvider {
  /// Creates a provider for [source].
  ///
  /// [username]/[password] come from the credential store; when omitted the
  /// source's own username is used without a password (rare but valid).
  /// [httpClient] is injectable for tests.
  WebDavFsProvider(
    this.source, {
    String? username,
    String? password,
    HttpClient? httpClient,
    Duration timeout = const Duration(seconds: 20),
  })  : _username = username ?? source.username,
        _password = password,
        _timeout = timeout,
        _ownsClient = httpClient == null,
        _client = httpClient ??
            (HttpClient()..connectionTimeout = const Duration(seconds: 20));

  /// Largest PROPFIND body that will be buffered (a directory with ~20k
  /// children still fits; a misbehaving server cannot exhaust memory).
  static const int maxPropfindBodyBytes = 8 * 1024 * 1024;

  @override
  final RemoteSource source;

  final HttpClient _client;
  final bool _ownsClient;
  final String? _username;
  final String? _password;
  final Duration _timeout;

  bool _closed = false;

  /// Lists [path] using `PROPFIND Depth: 1`.
  @override
  Future<List<RemoteEntry>> list(String path) async {
    final body = await _propfind(path, depth: 1);
    return parseMultiStatus(
      body,
      rootPath: source.rootPath,
      requestPath: path,
    );
  }

  /// Returns metadata for [path] using `PROPFIND Depth: 0`.
  @override
  Future<RemoteEntry?> stat(String path) async {
    final body = await _propfind(path, depth: 0);
    final entries = parseMultiStatus(
      body,
      rootPath: source.rootPath,
      requestPath: path,
      keepSelf: true,
    );
    if (entries.isEmpty) return null;
    final wanted = _stripSlashes(path).toLowerCase();
    for (final entry in entries) {
      if (entry.path.toLowerCase() == wanted) return entry;
    }
    return entries.first;
  }

  /// Streams [path] with a ranged `GET`.
  @override
  Stream<List<int>> openRead(String path, {int start = 0, int? end}) async* {
    if (start < 0) throw ArgumentError.value(start, 'start', 'must be >= 0');
    if (end != null && end < start) {
      throw ArgumentError.value(end, 'end', 'must be >= start');
    }
    final fullRead = start == 0 && end == null;
    final response = await _send(
      'GET',
      path,
      headers: fullRead
          ? null
          : {HttpHeaders.rangeHeader: _rangeHeader(start, end)},
    );
    await _throwForStatus(response, path);
    final isPartial = response.statusCode == HttpStatus.partialContent;
    var toSkip = isPartial ? 0 : start;
    var remaining = end == null ? -1 : end - start + 1;
    try {
      await for (final chunk in response.timeout(_timeout)) {
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
      ErrorLogger.log(
        'WebDAV read stalled',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
        meta: {'authority': source.authority},
      );
      throw RemoteUnavailableError(
        code: 'REMOTE_TIMEOUT',
        userMessage: 'The server stopped sending data. Check the connection.',
        cause: e,
        stackTrace: st,
      );
    } on IOException catch (e, st) {
      ErrorLogger.log(
        'WebDAV read failed mid-stream',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
        meta: {'authority': source.authority},
      );
      throw RemoteUnavailableError(
        code: 'REMOTE_STREAM_BROKEN',
        userMessage: 'The download was interrupted. Please try again.',
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Issues a Depth: 0 PROPFIND against the root and reports success.
  @override
  Future<bool> testConnection() async {
    final watch = Stopwatch()..start();
    try {
      await _propfind('', depth: 0);
      ErrorLogger.log(
        'WebDAV probe succeeded in ${watch.elapsedMilliseconds} ms',
        category: 'RemoteSources',
        meta: {'authority': source.authority},
      );
      return true;
    } on AppError catch (e, st) {
      ErrorLogger.log(
        'WebDAV probe failed: ${e.code}',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
        meta: {'authority': source.authority},
      );
      return false;
    } catch (e, st) {
      ErrorLogger.log(
        'WebDAV probe failed unexpectedly',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
        meta: {'authority': source.authority},
      );
      return false;
    }
  }

  /// Releases the underlying HttpClient if owned.
  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (_ownsClient) {
      _client.close(force: true);
    }
  }

  /// Parses a WebDAV `multistatus` document into entries relative to [rootPath].
  ///
  /// Delegates to [parseWebDavMultiStatus]; kept here as the entry point callers
  /// and tests already use.
  static List<RemoteEntry> parseMultiStatus(
    String xml, {
    required String rootPath,
    required String requestPath,
    bool keepSelf = false,
  }) {
    return parseWebDavMultiStatus(
      xml,
      rootPath: rootPath,
      requestPath: requestPath,
      keepSelf: keepSelf,
    );
  }

  /// Builds the `Range` header value for a byte window.
  static String rangeHeader(int start, int? end) => _rangeHeader(start, end);

  static String _rangeHeader(int start, int? end) =>
      end == null ? 'bytes=$start-' : 'bytes=$start-$end';

  Future<String> _propfind(String path, {required int depth}) async {
    final response = await _send(
      'PROPFIND',
      path,
      depth: depth,
      body: _propfindBody,
      headers: const {'Content-Type': 'application/xml; charset=utf-8'},
    );
    await _throwForStatus(response, path);
    final body = await _readBody(response);
    if (body.trim().isEmpty) {
      throw const RemoteProtocolError(
        code: 'WEBDAV_EMPTY_MULTISTATUS',
        userMessage:
            'The server returned an empty answer. WebDAV may be disabled.',
      );
    }
    return body;
  }

  Future<HttpClientResponse> _send(
    String method,
    String path, {
    int? depth,
    String? body,
    Map<String, String>? headers,
  }) async {
    final uri = _uriFor(path);
    HttpClientRequest request;
    try {
      request = await _client.openUrl(method, uri).timeout(_timeout);
    } on TimeoutException catch (e, st) {
      throw _unreachable('The server did not answer in time.', e, st);
    } on HandshakeException catch (e, st) {
      throw RemoteUnavailableError(
        code: 'REMOTE_TLS_ERROR',
        userMessage:
            'Secure connection failed. The certificate may be invalid or '
            'self-signed.',
        cause: e,
        stackTrace: st,
      );
    } on SocketException catch (e, st) {
      throw _unreachable('Could not reach ${source.authority}.', e, st);
    }
    final authorization = _authorizationHeader;
    if (authorization != null) {
      request.headers.set(HttpHeaders.authorizationHeader, authorization);
    }
    if (depth != null) {
      request.headers.set('Depth', '$depth');
    }
    headers?.forEach((name, value) => request.headers.set(name, value));
    if (body != null) {
      final bytes = utf8.encode(body);
      request.headers.contentLength = bytes.length;
      request.add(bytes);
    }
    try {
      return await request.close().timeout(_timeout);
    } on TimeoutException catch (e, st) {
      throw _unreachable('The server did not answer in time.', e, st);
    } on HandshakeException catch (e, st) {
      throw RemoteUnavailableError(
        code: 'REMOTE_TLS_ERROR',
        userMessage: 'Secure connection failed: the certificate was rejected.',
        cause: e,
        stackTrace: st,
      );
    } on SocketException catch (e, st) {
      throw _unreachable('Could not reach ${source.authority}.', e, st);
    } on HttpException catch (e, st) {
      throw RemoteUnavailableError(
        code: 'REMOTE_HTTP_TRANSPORT',
        userMessage: 'The connection was closed before the reply arrived.',
        cause: e,
        stackTrace: st,
      );
    }
  }

  Future<String> _readBody(HttpClientResponse response) async {
    final bytes = <int>[];
    try {
      await for (final chunk in response.timeout(_timeout)) {
        bytes.addAll(chunk);
        if (bytes.length > maxPropfindBodyBytes) {
          throw const RemoteProtocolError(
            code: 'WEBDAV_OVERSIZED',
            userMessage: 'The folder listing is too large to read.',
          );
        }
      }
    } on TimeoutException catch (e, st) {
      throw _unreachable('The server stopped answering.', e, st);
    } on IOException catch (e, st) {
      throw RemoteUnavailableError(
        code: 'REMOTE_TRANSPORT',
        userMessage: 'The reply was cut off. Please try again.',
        cause: e,
        stackTrace: st,
      );
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  Future<void> _throwForStatus(HttpClientResponse response, String path) async {
    final status = response.statusCode;
    if (status >= 200 && status < 300) return;
    // Drain the body so the connection is returned to the pool.
    try {
      await response.drain<void>().timeout(_timeout);
    } catch (e, st) {
      ErrorLogger.log(
        'Could not drain a WebDAV error body',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
        meta: {'status': status},
      );
    }
    ErrorLogger.log(
      'WebDAV request failed with HTTP $status',
      category: 'RemoteSources',
      meta: {'authority': source.authority, 'path': path},
    );
    throw webDavStatusError(status, path: path);
  }

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
      code: 'REMOTE_UNREACHABLE',
      userMessage: message,
      cause: cause,
      stackTrace: stackTrace,
    );
  }

  String? get _authorizationHeader {
    final user = _username;
    if (user == null || user.isEmpty) return null;
    final password = _password;
    final hasPassword = password != null && password.isNotEmpty;
    final token = base64Encode(
      utf8.encode('$user:${hasPassword ? password : ''}'),
    );
    return 'Basic $token';
  }

  Uri _uriFor(String path) {
    final segments = <String>[];
    void addSegments(String value) {
      for (final segment in value.split('/')) {
        if (segment.isEmpty || segment == '.') continue;
        if (_isTraversalSegment(segment)) {
          throw const RemoteProtocolError(
            code: 'WEBDAV_PATH_TRAVERSAL',
            userMessage: 'That path is not allowed.',
          );
        }
        segments.add(segment);
      }
    }

    addSegments(source.rootPath);
    addSegments(path);
    return Uri(
      scheme: source.useTls ? 'https' : 'http',
      host: source.host,
      port: source.port,
      pathSegments: segments.isEmpty ? const [''] : segments,
    );
  }

  /// Rejects `..` in either literal or percent-encoded form.
  static bool _isTraversalSegment(String segment) {
    if (segment == '..') return true;
    try {
      return Uri.decodeComponent(segment) == '..';
    } on ArgumentError {
      return true;
    } on FormatException {
      return true;
    }
  }

  static String _stripSlashes(String value) {
    var result = value;
    while (result.startsWith('/')) {
      result = result.substring(1);
    }
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  static const String _propfindBody = '<?xml version="1.0" encoding="utf-8"?>'
      '<d:propfind xmlns:d="DAV:"><d:prop>'
      '<d:resourcetype/><d:getcontentlength/>'
      '<d:getlastmodified/><d:getetag/>'
      '</d:prop></d:propfind>';
}
