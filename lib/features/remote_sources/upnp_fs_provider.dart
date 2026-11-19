// lib/features/remote_sources/upnp_fs_provider.dart
//
// P1-8 "network parity": a DLNA / UPnP media server as a [RemoteFsProvider].
//
// UPnP has no filesystem: a server exposes a tree of objects addressed by an
// opaque id, and only audio items carry a playable resource URI. The provider
// maps that tree onto the paths the browser and the loopback stream bridge
// already understand:
//
//   ''            the root container (`0`)
//   c/<id>        one container, addressed by its object id
//   i/<id>        one item, addressed by its object id
//
// Both id forms are percent-encoded into a single segment. The resource URI is
// resolved with a `BrowseMetadata` call when a track is opened (and remembered
// in a small cache) instead of being embedded in the path: devices rotate
// signed resource URLs, and a path that outlives one would stop playing.
//
// The provider is built from a persisted [RemoteSource] whose `rootPath` is the
// ContentDirectory control path (see [controlUrlFor]); discovery fills that in
// from the device description.
import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/errors/app_error_base.dart';
import '../../core/utils/error_logger.dart';
import '../../data/remote/upnp_content_directory.dart';
import '../../domain/interfaces/remote_fs_provider.dart';
import '../../domain/models/remote_source.dart';

/// UPnP ContentDirectory implementation of [RemoteFsProvider].
class UpnpFsProvider implements RemoteFsProvider {
  /// Creates a provider for [source] talking to [controlUrl].
  ///
  /// [client] is injectable for tests; when omitted the provider creates and
  /// closes its own. [allowedHostSuffixes] is the explicit LAN allowlist: the
  /// device's own host is always added, because a media server legitimately
  /// serves from a private address.
  UpnpFsProvider(
    this.source, {
    required Uri controlUrl,
    http.Client? client,
    Duration timeout = const Duration(seconds: 20),
    Set<String> allowedHostSuffixes = const {},
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _timeout = timeout {
    _controlUrl = _validatedControlUrl(controlUrl);
    _allowedHosts = <String>{
      ...allowedHostSuffixes,
      source.host.toLowerCase(),
      _controlUrl.host.toLowerCase(),
    };
    _directory = UpnpContentDirectory(
      client: _client,
      timeout: timeout,
      allowedHostSuffixes: _allowedHosts,
    );
  }

  /// Path segment that introduces a container.
  static const String containerSegment = 'c';

  /// Path segment that introduces an item.
  static const String itemSegment = 'i';

  /// Upper bound on remembered resource URIs (one per opened track).
  static const int maxCachedResources = 512;

  @override
  final RemoteSource source;

  final http.Client _client;
  final bool _ownsClient;
  final Duration _timeout;
  late final Uri _controlUrl;
  late final Set<String> _allowedHosts;
  late final UpnpContentDirectory _directory;
  final Map<String, Uri> _resources = <String, Uri>{};
  bool _closed = false;

  /// Control URL of the ContentDirectory service described by [source].
  ///
  /// `rootPath` holds the control path for a UPnP source; a discovered server
  /// keeps its advertised port, so the URL is reproducible after a restart.
  static Uri controlUrlFor(RemoteSource source) => Uri(
        scheme: source.useTls ? 'https' : 'http',
        host: source.host,
        port: source.port,
        path: source.rootPath,
      );

  /// Path of the container with [objectId].
  static String containerPath(String objectId) =>
      '$containerSegment/${_encodeId(objectId)}';

  /// Path of the item with [objectId].
  static String itemPath(String objectId) =>
      '$itemSegment/${_encodeId(objectId)}';

  /// `Range` header value for a byte window.
  static String rangeHeader(int start, int? end) =>
      end == null ? 'bytes=$start-' : 'bytes=$start-$end';

  /// Lists the children of a container.
  @override
  Future<List<RemoteEntry>> list(String path) async {
    final target = _parse(path);
    if (target.isItem) {
      throw const RemoteProtocolError(
        code: 'UPNP_NOT_A_FOLDER',
        userMessage: 'That item is a track, not a folder.',
      );
    }
    try {
      final objects = await _directory.browseAll(
        controlUrl: _controlUrl,
        objectId: target.objectId,
      );
      final entries = <RemoteEntry>[];
      for (final object in objects) {
        if (object.isContainer) {
          entries.add(
            RemoteEntry(
              path: containerPath(object.id),
              name: object.title,
              isDirectory: true,
            ),
          );
        } else if (_isPlayable(object)) {
          entries.add(
            RemoteEntry(
              path: itemPath(object.id),
              name: object.title,
              isDirectory: false,
              sizeBytes: object.sizeBytes,
            ),
          );
        }
      }
      entries.sort(RemoteEntry.compare);
      return entries;
    } on UpnpBrowseError catch (e, st) {
      throw _asRemoteError(e, st);
    }
  }

  /// Reads one object's metadata, or `null` when it no longer exists.
  @override
  Future<RemoteEntry?> stat(String path) async {
    final target = _parse(path);
    if (target.isRoot) {
      return RemoteEntry(
        path: '',
        name: source.displayName,
        isDirectory: true,
      );
    }
    try {
      final object = await _readObject(target.objectId);
      if (object == null) return null;
      if (object.isContainer) {
        return RemoteEntry(
          path: containerPath(object.id),
          name: object.title,
          isDirectory: true,
        );
      }
      if (!_isPlayable(object)) return null;
      return RemoteEntry(
        path: itemPath(object.id),
        name: object.title,
        isDirectory: false,
        sizeBytes: object.sizeBytes,
      );
    } on UpnpBrowseError catch (e, st) {
      final mapped = _asRemoteError(e, st);
      // A vanished object is a plain miss for stat: the stream bridge answers
      // "unknown size" instead of failing the request outright.
      if (mapped is RemoteNotFoundError) return null;
      throw mapped;
    }
  }

  /// Streams one item's resource URI, honouring a byte window.
  ///
  /// A server that ignores the `Range` header (200 instead of 206) is handled
  /// by skipping [start] bytes locally, as the [RemoteFsProvider] contract
  /// requires.
  @override
  Stream<List<int>> openRead(String path, {int start = 0, int? end}) async* {
    if (start < 0) throw ArgumentError.value(start, 'start', 'must be >= 0');
    if (end != null && end < start) {
      throw ArgumentError.value(end, 'end', 'must be >= start');
    }
    final target = _parse(path);
    if (!target.isItem) {
      throw const RemoteProtocolError(
        code: 'UPNP_NOT_A_FILE',
        userMessage: 'That item is not a playable track.',
      );
    }

    final uri = await _resourceUri(target.objectId);
    final fullRead = start == 0 && end == null;
    final request = http.Request('GET', uri);
    if (!fullRead) {
      request.headers[HttpHeaders.rangeHeader] = rangeHeader(start, end);
    }

    final http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(_timeout);
    } on TimeoutException catch (e, st) {
      throw _unreachable('The media server did not answer in time.', e, st);
    } on http.ClientException catch (e, st) {
      throw _unreachable('Could not reach the media server.', e, st);
    } on IOException catch (e, st) {
      throw _unreachable('Could not reach the media server.', e, st);
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
        'The media server stopped sending data. Check the connection.',
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

  /// Browses the root container once; the cheapest proof the server answers.
  @override
  Future<bool> testConnection() async {
    final watch = Stopwatch()..start();
    try {
      await _directory.browse(
        controlUrl: _controlUrl,
        objectId: UpnpContentDirectory.rootObjectId,
        count: 1,
      );
      ErrorLogger.log(
        'UPnP probe succeeded in ${watch.elapsedMilliseconds} ms',
        category: 'RemoteSources',
        meta: {'authority': source.authority},
      );
      return true;
    } on AppError catch (e, st) {
      ErrorLogger.log(
        'UPnP probe failed: ${e.code}',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
        meta: {'authority': source.authority},
      );
      return false;
    } catch (e, st) {
      ErrorLogger.log(
        'UPnP probe failed unexpectedly',
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
    _resources.clear();
    _directory.close();
    if (_ownsClient) _client.close();
  }

  /// One object from `BrowseMetadata`, or `null` when the server has no such
  /// object.
  Future<UpnpObject?> _readObject(String objectId) async {
    final page = await _directory.browse(
      controlUrl: _controlUrl,
      objectId: objectId,
      count: 1,
      browseFlag: UpnpContentDirectory.browseMetadata,
    );
    return page.objects.isEmpty ? null : page.objects.first;
  }

  /// Playable resource URI for [objectId], remembered once resolved.
  Future<Uri> _resourceUri(String objectId) async {
    final cached = _resources[objectId];
    if (cached != null) return cached;
    final UpnpObject? object;
    try {
      object = await _readObject(objectId);
    } on UpnpBrowseError catch (e, st) {
      throw _asRemoteError(e, st);
    }
    if (object == null) {
      throw const RemoteNotFoundError(
        code: 'UPNP_OBJECT_MISSING',
        userMessage: 'This track is no longer on the server.',
      );
    }
    final uri = object.playableHttpUri(allowedHostSuffixes: _allowedHosts);
    if (uri == null) {
      throw const RemoteProtocolError(
        code: 'UPNP_RESOURCE_UNPLAYABLE',
        userMessage: 'This media server cannot stream that track.',
      );
    }
    if (_resources.length >= maxCachedResources) {
      _resources.remove(_resources.keys.first);
    }
    _resources[objectId] = uri;
    return uri;
  }

  /// True for an audio item with an absolute http(s) resource.
  ///
  /// Devices frequently omit `upnp:class`, so a missing class is accepted; a
  /// class that says "video" or "image" is not.
  static bool _isPlayable(UpnpObject object) {
    if (object.isContainer) return false;
    final klass = object.upnpClass;
    if (klass != null && !klass.startsWith('object.item.audioItem')) {
      return false;
    }
    return object.isHttpResource;
  }

  static Uri _validatedControlUrl(Uri controlUrl) {
    final scheme = controlUrl.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      throw const RemoteProtocolError(
        code: 'UPNP_CONTROL_URL_INVALID',
        userMessage: 'This media server address is not usable.',
      );
    }
    if (controlUrl.host.trim().isEmpty) {
      throw const RemoteProtocolError(
        code: 'UPNP_CONTROL_URL_INVALID',
        userMessage: 'This media server address is not usable.',
      );
    }
    return controlUrl;
  }

  /// Parses a provider path into an object id.
  ({String objectId, bool isItem, bool isRoot}) _parse(String path) {
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) {
      return (
        objectId: UpnpContentDirectory.rootObjectId,
        isItem: false,
        isRoot: true
      );
    }
    if (segments.length != 2) throw _badPath();
    final id = _decodeId(segments[1]);
    if (id == null || id.isEmpty) throw _badPath();
    final isContainer = segments.first == containerSegment;
    if (!isContainer && segments.first != itemSegment) throw _badPath();
    return (objectId: id, isItem: !isContainer, isRoot: false);
  }

  static String _encodeId(String id) => Uri.encodeComponent(id);

  static String? _decodeId(String segment) {
    try {
      return Uri.decodeComponent(segment);
    } on ArgumentError {
      return null;
    } on FormatException {
      return null;
    }
  }

  static const RemoteProtocolError _pathError = RemoteProtocolError(
    code: 'UPNP_BAD_PATH',
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
      code: 'UPNP_UNREACHABLE',
      userMessage: message,
      cause: cause,
      stackTrace: stackTrace,
    );
  }

  AppError _statusError(int status) {
    ErrorLogger.log(
      'UPnP resource request failed with HTTP $status',
      category: 'RemoteSources',
      meta: {'authority': source.authority},
    );
    if (status == 401 || status == 403) {
      return const RemoteAuthError(
        code: 'UPNP_AUTH',
        userMessage: 'The media server rejected the request.',
      );
    }
    if (status == 404) {
      return const RemoteNotFoundError(
        code: 'UPNP_NOT_FOUND',
        userMessage: 'This track is no longer on the server.',
      );
    }
    if (status == 416) {
      return const RemoteProtocolError(
        code: 'UPNP_RANGE_UNSATISFIABLE',
        userMessage: 'The requested part of the file is outside its size.',
      );
    }
    if (status >= 500) {
      return RemoteUnavailableError(
        code: 'UPNP_SERVER_ERROR',
        userMessage: 'The media server reported an error ($status). '
            'Try again later.',
      );
    }
    return RemoteProtocolError(
      code: 'UPNP_HTTP_$status',
      userMessage: 'The media server rejected the request ($status).',
    );
  }

  /// Converts a control-point failure into the typed family the stream bridge
  /// understands.
  static AppError _asRemoteError(UpnpBrowseError error, StackTrace stackTrace) {
    if (error.code == 'UPNP_TIMEOUT' || error.code == 'UPNP_NETWORK_ERROR') {
      return RemoteUnavailableError(
        code: 'UPNP_UNREACHABLE',
        userMessage: error.userMessage,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    final upnpCode = error.errorCode;
    if (upnpCode == 701 || upnpCode == 710) {
      return RemoteNotFoundError(
        code: 'UPNP_OBJECT_MISSING',
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
