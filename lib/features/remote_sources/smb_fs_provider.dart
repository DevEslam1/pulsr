// lib/features/remote_sources/smb_fs_provider.dart
//
// P0-1 "remote sources": SMB2/3 through the Android plugin (SmbPlugin.kt).
//
// Dart owns no SMB stack: every call crosses `com.pulsr.music/smb`. When that
// channel is absent (desktop, iOS, an older build, or a build without the
// `com.hierynomus:smbj` dependency) the provider raises an actionable
// [RemoteUnavailableError]. It never reports a successful listing or an empty
// file for a channel that is not there.
//
// Path contract (do not "helpfully" change one side only):
//   * `basePath` is the share-relative root of the source (`''` or `Music`).
//   * `path` is always share-relative as well (`''` or `Albums/a.mp3`), never
//     prefixed with `basePath`.
//   * SmbPlugin.kt owns the single `basePath + path` join and answers with
//     native paths that include `basePath`; this provider strips it back off.
// Sending `basePath` inside `path` makes the native side join twice, which
// resolves to `Music/Music/...` on every request.
import 'dart:async';

import 'package:flutter/services.dart';

import '../../core/errors/app_error_base.dart';
import '../../core/utils/error_logger.dart';
import '../../domain/interfaces/remote_fs_provider.dart';
import '../../domain/models/remote_source.dart';

/// SMB implementation of [RemoteFsProvider], backed by the native plugin.
class SmbFsProvider implements RemoteFsProvider {
  /// Creates a provider for [source].
  ///
  /// [username] accepts `user`, `DOMAIN\user` or `user@domain`; [password]
  /// comes from the credential store and is never logged.
  SmbFsProvider(
    this.source, {
    String? username,
    String? password,
    MethodChannel? channel,
    Duration timeout = const Duration(seconds: 30),
    int chunkSize = defaultChunkSize,
  })  : _username = username ?? source.username,
        _password = password,
        _channel = channel ?? const MethodChannel(channelName),
        _timeout = timeout,
        _chunkSize = chunkSize;

  /// MethodChannel served by `SmbPlugin.kt`.
  static const String channelName = 'com.pulsr.music/smb';

  /// Bytes requested per `openReadChunk` call.
  static const int defaultChunkSize = 256 * 1024;

  @override
  final RemoteSource source;

  final MethodChannel _channel;
  final String? _username;
  final String? _password;
  final Duration _timeout;
  final int _chunkSize;

  /// Lists [path] through the native plugin.
  @override
  Future<List<RemoteEntry>> list(String path) async {
    final payload = await _invoke<List<dynamic>>(
      'list',
      <String, dynamic>{
        ..._baseArguments(),
        'path': _shareRelativePath(path),
      },
    );
    final entries = <RemoteEntry>[];
    for (final item in payload ?? const <dynamic>[]) {
      if (item is! Map) continue;
      final map = item.cast<dynamic, dynamic>();
      final entryPath = _relativeFromNative(map['path'] as String? ?? '');
      if (entryPath.isEmpty) continue;
      entries.add(
        RemoteEntry(
          path: entryPath,
          name: map['name'] as String? ?? entryPath.split('/').last,
          isDirectory: map['isDirectory'] as bool? ?? false,
          sizeBytes: (map['sizeBytes'] as num?)?.toInt(),
          modifiedAt: _dateFromNative(map['modifiedAt']),
          etag: map['etag'] as String?,
        ),
      );
    }
    entries.sort(RemoteEntry.compare);
    return entries;
  }

  /// Returns metadata for [path] through the native plugin.
  @override
  Future<RemoteEntry?> stat(String path) async {
    final payload = await _invoke<Map<dynamic, dynamic>>(
      'stat',
      <String, dynamic>{
        ..._baseArguments(),
        'path': _shareRelativePath(path),
      },
    );
    if (payload == null) return null;
    final entryPath = _relativeFromNative(payload['path'] as String? ?? '');
    final name = entryPath.isEmpty
        ? (payload['name'] as String? ?? '')
        : entryPath.split('/').last;
    if (name.isEmpty) return null;
    return RemoteEntry(
      path: entryPath,
      name: name,
      isDirectory: payload['isDirectory'] as bool? ?? false,
      sizeBytes: (payload['sizeBytes'] as num?)?.toInt(),
      modifiedAt: _dateFromNative(payload['modifiedAt']),
      etag: payload['etag'] as String?,
    );
  }

  /// Streams [path] in [chunkSize] windows fetched from the native plugin.
  @override
  Stream<List<int>> openRead(String path, {int start = 0, int? end}) async* {
    if (start < 0) throw ArgumentError.value(start, 'start', 'must be >= 0');
    if (end != null && end < start) {
      throw ArgumentError.value(end, 'end', 'must be >= start');
    }
    final sharePath = _shareRelativePath(path);
    var offset = start;
    var remaining = end == null ? -1 : end - start + 1;
    while (true) {
      if (remaining == 0) return;
      final want = remaining < 0
          ? _chunkSize
          : (remaining < _chunkSize ? remaining : _chunkSize);
      final chunk = await _readChunk(sharePath, offset, want);
      if (chunk.isEmpty) return;
      yield chunk;
      offset += chunk.length;
      if (remaining > 0) remaining -= chunk.length;
      if (chunk.length < want) return;
    }
  }

  /// Runs the native `probe` (connect, logon and root check).
  @override
  Future<bool> testConnection() async {
    final watch = Stopwatch()..start();
    try {
      final result = await _invoke<dynamic>('probe', _baseArguments());
      final ok = result is bool ? result : true;
      ErrorLogger.log(
        'SMB probe ${ok ? 'succeeded' : 'failed'} in '
        '${watch.elapsedMilliseconds} ms',
        category: 'RemoteSources',
        meta: {'authority': source.authority},
      );
      return ok;
    } on AppError catch (e, st) {
      ErrorLogger.log(
        'SMB probe failed: ${e.code}',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
        meta: {'authority': source.authority},
      );
      return false;
    }
  }

  /// Asks the native side to drop its cached session for this source.
  @override
  Future<void> close() async {
    try {
      await _channel
          .invokeMethod<void>('close', _baseArguments())
          .timeout(const Duration(seconds: 5));
    } on MissingPluginException catch (e, st) {
      // Nothing to release: the plugin was never there.
      ErrorLogger.log(
        'SMB plugin is unavailable while closing; nothing to release',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
      );
    } on PlatformException catch (e, st) {
      ErrorLogger.log(
        'SMB session close failed',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
        meta: {'authority': source.authority},
      );
    } on AppError catch (e, st) {
      ErrorLogger.log(
        'SMB close was called without a usable share',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
      );
    } on TimeoutException catch (e, st) {
      ErrorLogger.log(
        'SMB session close timed out',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
        meta: {'authority': source.authority},
      );
    }
  }

  Future<Uint8List> _readChunk(String sharePath, int offset, int length) async {
    final payload = await _invoke<dynamic>(
      'openReadChunk',
      <String, dynamic>{
        ..._baseArguments(),
        'path': sharePath,
        'offset': offset,
        'length': length,
      },
    );
    if (payload is Uint8List) return payload;
    if (payload is List<int>) return Uint8List.fromList(payload);
    if (payload is List) {
      return Uint8List.fromList(payload.whereType<int>().toList());
    }
    if (payload == null) {
      throw const RemoteProtocolError(
        code: 'SMB_CHUNK_MISSING',
        userMessage: 'The SMB plugin returned no data for this file.',
      );
    }
    throw RemoteProtocolError(
      code: 'SMB_CHUNK_TYPE',
      userMessage: 'The SMB plugin returned an unexpected payload '
          '(${payload.runtimeType}).',
    );
  }

  Future<T?> _invoke<T>(String method, Map<String, dynamic> args) async {
    try {
      return await _channel.invokeMethod<T>(method, args).timeout(_timeout);
    } on MissingPluginException catch (e, st) {
      ErrorLogger.log(
        'SMB plugin channel is not registered',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
        meta: {'method': method},
      );
      throw _unavailable();
    } on PlatformException catch (e, st) {
      ErrorLogger.log(
        'SMB call "$method" failed with ${e.code}',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
        meta: {'authority': source.authority, 'method': method},
      );
      throw _mapPlatformError(e);
    } on TimeoutException catch (e, st) {
      ErrorLogger.log(
        'SMB call "$method" timed out',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
        meta: {'authority': source.authority, 'method': method},
      );
      throw RemoteUnavailableError(
        code: 'SMB_TIMEOUT',
        userMessage: 'The file server did not answer in time.',
        cause: e,
        stackTrace: st,
      );
    }
  }

  AppError _mapPlatformError(PlatformException exception) {
    final code = exception.code.toUpperCase();
    final detail = exception.message;
    if (code.contains('AUTH') || code.contains('LOGON')) {
      return RemoteAuthError(
        code: 'SMB_AUTH',
        userMessage: detail?.isNotEmpty == true
            ? detail!
            : 'The file server rejected the username or password.',
        cause: exception,
      );
    }
    if (code.contains('NOT_FOUND') || code.contains('OBJECT_NAME')) {
      return RemoteNotFoundError(
        code: 'SMB_NOT_FOUND',
        userMessage: 'That folder no longer exists on the server.',
        cause: exception,
      );
    }
    if (code.contains('UNSUPPORTED') || code.contains('NO_PLUGIN')) {
      return _unavailable(cause: exception);
    }
    if (code.contains('TIMEOUT') ||
        code.contains('NETWORK') ||
        code.contains('UNAVAILABLE')) {
      return RemoteUnavailableError(
        code: 'SMB_UNAVAILABLE',
        userMessage: detail?.isNotEmpty == true
            ? detail!
            : 'The file server is unreachable.',
        cause: exception,
      );
    }
    return RemoteProtocolError(
      code: 'SMB_${exception.code}',
      userMessage: detail?.isNotEmpty == true
          ? detail!
          : 'The file server reported an error (${exception.code}).',
      cause: exception,
    );
  }

  RemoteUnavailableError _unavailable({Object? cause}) {
    return RemoteUnavailableError(
      code: 'SMB_PLUGIN_MISSING',
      userMessage: 'SMB browsing needs the Android build of Pulsr with its SMB '
          'plugin. Use WebDAV or FTP on this platform.',
      cause: cause,
    );
  }

  Map<String, dynamic> _baseArguments() {
    final share = _shareName();
    return <String, dynamic>{
      'host': source.host,
      'port': source.port,
      'share': share,
      'basePath': _shareRelativeRoot(),
      'username': _username ?? '',
      'password': _password ?? '',
      'domain': _domainName(),
    };
  }

  /// Normalizes a provider-relative [path] for the native side.
  ///
  /// The result is *share-relative*: `basePath` is sent separately and the
  /// native `joinPath` prepends it exactly once. Never prepend base here.
  String _shareRelativePath(String path) {
    var value = path.trim().replaceAll('\\', '/');
    while (value.startsWith('/')) {
      value = value.substring(1);
    }
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  String _relativeFromNative(String nativePath) {
    var value = nativePath.trim().replaceAll('\\', '/');
    while (value.startsWith('/')) {
      value = value.substring(1);
    }
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    final base = _shareRelativeRoot();
    if (base.isEmpty) return value;
    if (value.toLowerCase() == base.toLowerCase()) return '';
    if (value.toLowerCase().startsWith('${base.toLowerCase()}/')) {
      return value.substring(base.length + 1);
    }
    return value;
  }

  /// First segment of `rootPath`, i.e. the SMB share name.
  String _shareName() {
    final segments = _rootSegments();
    if (segments.isEmpty) {
      throw const RemoteProtocolError(
        code: 'SMB_NO_SHARE',
        userMessage: 'Set the root to /<share> (for example /Music) to browse '
            'an SMB server.',
      );
    }
    return segments.first;
  }

  String _shareRelativeRoot() {
    final segments = _rootSegments();
    if (segments.length <= 1) return '';
    return segments.skip(1).join('/');
  }

  List<String> _rootSegments() {
    return RemoteSource.normalizeRootPath(source.rootPath)
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
  }

  /// Splits `DOMAIN\user` / `user@domain` into a logon domain.
  String _domainName() {
    final user = _username ?? '';
    final backslash = user.indexOf('\\');
    if (backslash > 0) return user.substring(0, backslash);
    final at = user.indexOf('@');
    if (at > 0) return user.substring(at + 1);
    return '';
  }

  static DateTime? _dateFromNative(Object? raw) {
    if (raw is num) return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }
}
