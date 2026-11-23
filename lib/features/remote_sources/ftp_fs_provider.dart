// lib/features/remote_sources/ftp_fs_provider.dart
//
// P0-1 "remote sources": plain FTP (RFC 959) with passive data connections.
//
// This class is the provider half: it resolves provider-relative paths, turns
// listings into entries and enforces "one transfer at a time". The protocol
// half lives in ftp_session.dart / ftp_protocol.dart, and error mapping in
// ftp_error_mapper.dart.
import 'dart:async';
import 'dart:io';

import 'package:mutex/mutex.dart';

import '../../core/errors/app_error_base.dart';
import '../../core/utils/error_logger.dart';
import '../../domain/interfaces/remote_fs_provider.dart';
import '../../domain/models/remote_source.dart';
import 'ftp_error_mapper.dart';
import 'ftp_protocol.dart';
import 'ftp_session.dart';

/// FTP implementation of [RemoteFsProvider].
///
/// One control connection is kept per provider and every command is serialized
/// by the session, because an FTP session allows a single command at a time.
/// Transfers are serialized too: a second [openRead] waits for the first to
/// finish rather than interleaving two RETR commands on one session.
class FtpFsProvider implements RemoteFsProvider {
  /// Creates a provider for [source].
  ///
  /// [username] defaults to the source's username, then to `anonymous`.
  /// [password] comes from the credential store and is never logged.
  FtpFsProvider(
    this.source, {
    String? username,
    String? password,
    Duration timeout = const Duration(seconds: 30),
  })  : _username = username ?? source.username,
        _password = password,
        _timeout = timeout,
        _errors = FtpErrorMapper(source: source);

  /// Largest listing payload accepted (see [FtpSession.maxListingBytes]).
  static const int maxListingBytes = FtpSession.maxListingBytes;

  /// Cap on per-entry `stat` calls when a server only supports NLST.
  static const int maxNlstStatEntries = 64;

  @override
  final RemoteSource source;

  final String? _username;
  final String? _password;
  final Duration _timeout;
  final FtpErrorMapper _errors;
  final Mutex _transferLock = Mutex();
  late final FtpSession _session = FtpSession(
    source: source,
    errors: _errors,
    username: _username,
    password: _password,
    timeout: _timeout,
  );
  bool _closed = false;

  /// Lists [path] (`LIST`, falling back to `NLST` plus type probing).
  @override
  Future<List<RemoteEntry>> list(String path) =>
      _transferLock.protect(() => _errors.guard('list', () async {
        await _session.ensureConnected();
        final absolute = _resolve(path);
        List<RemoteEntry> entries = const [];
        var listSucceeded = false;
        var listing = '';
        try {
          listing = await _session.readListing('LIST $absolute');
          listSucceeded = true;
          entries = FtpListingParser.parseListing(
            listing,
            parentPath: path,
          );
        } on RemoteProtocolError catch (e, st) {
          if (!_session.isConnected) rethrow;
          // Plenty of embedded servers reject `LIST <path>` but answer NLST.
          ErrorLogger.log(
            'FTP LIST with a path was rejected; retrying with NLST',
            error: e,
            stackTrace: st,
            category: 'RemoteSources',
            meta: {'authority': source.authority},
          );
          entries = const [];
        }
        if (entries.isNotEmpty) return entries;
        // A clean empty LIST response already proves the folder has no entries;
        // calling NLST next turns valid empty folders into 550 errors on many
        // FTP daemons.
        if (listSucceeded && listing.trim().isEmpty) return const [];
        final names = await _session.readListing('NLST $absolute');
        return _enrichTypes(
          FtpListingParser.parseNameList(names, parentPath: path),
        );
      }));

  /// Returns metadata for [path] using `SIZE` / `MDTM`, falling back to `CWD`.
  @override
  Future<RemoteEntry?> stat(String path) =>
      _transferLock.protect(() => _statUnlocked(path));

  Future<RemoteEntry?> _statUnlocked(String path) =>
      _errors.guard('stat', () async {
        await _session.ensureConnected();
        final control = _session.requireControl();
        final absolute = _resolve(path);
        final relative = _relative(path);
        final name = _entryName(relative, absolute);
        int? size;
        DateTime? modified;
        final sizeReply = await control.command('SIZE $absolute');
        if (sizeReply.code == 213) {
          size = int.tryParse(sizeReply.message.trim());
        }
        final timeReply = await control.command('MDTM $absolute');
        if (timeReply.code == 213) {
          modified = FtpListingParser.parseModifiedTime(timeReply.message);
        }
        if (size != null) {
          return RemoteEntry(
            path: relative,
            name: name,
            isDirectory: false,
            sizeBytes: size,
            modifiedAt: modified,
          );
        }
        final cwdReply = await control.command('CWD $absolute');
        if (cwdReply.code == 250) {
          final restore = await control.command('CWD ${_session.homeDir}');
          if (!restore.isSuccess) {
            ErrorLogger.log(
              'FTP could not restore the working directory after a CWD probe',
              category: 'RemoteSources',
              meta: {'code': restore.code},
            );
          }
          return RemoteEntry(
            path: relative,
            name: name,
            isDirectory: true,
            modifiedAt: modified,
          );
        }
        if (cwdReply.code == 550 || cwdReply.code == 450) return null;
        return null;
      });

  /// Streams [path] with `REST <start>` + `RETR`, honouring [end] locally.
  @override
  Stream<List<int>> openRead(String path, {int start = 0, int? end}) async* {
    if (start < 0) throw ArgumentError.value(start, 'start', 'must be >= 0');
    if (end != null && end < start) {
      throw ArgumentError.value(end, 'end', 'must be >= start');
    }
    await _transferLock.acquire();
    Socket? data;
    var completed = false;
    try {
      await _session.ensureConnected();
      final control = _session.requireControl();
      final absolute = _resolve(path);
      data = await _session.openDataSocket();
      var skip = 0;
      if (start > 0) {
        final rest = await control.command('REST $start');
        if (rest.code != 350) {
          // The server cannot resume: read from the beginning and drop bytes.
          skip = start;
          ErrorLogger.log(
            'FTP server rejected REST; skipping $start bytes locally',
            category: 'RemoteSources',
            meta: {'authority': source.authority, 'code': rest.code},
          );
        }
      }
      final reply = await control.command('RETR $absolute');
      if (!reply.isIntermediate && !reply.isSuccess) {
        throw _errors.mapReply(reply, 'RETR');
      }
      var remaining = end == null ? -1 : end - start + 1;
      var stoppedEarly = false;
      await for (final chunk in data.timeout(_timeout)) {
        var bytes = chunk;
        if (skip > 0) {
          if (bytes.length <= skip) {
            skip -= bytes.length;
            continue;
          }
          bytes = bytes.sublist(skip);
          skip = 0;
        }
        if (remaining >= 0 && bytes.length > remaining) {
          bytes = bytes.sublist(0, remaining);
        }
        if (remaining >= 0) remaining -= bytes.length;
        if (bytes.isNotEmpty) yield bytes;
        if (remaining == 0) {
          stoppedEarly = true;
          break;
        }
      }
      // Close the data socket before awaiting the completion reply: a server
      // that writes `226` only after the data connection disappears would
      // otherwise deadlock against us. `completeTransfer` accepts 426 (the
      // normal answer to an early close) as a healthy completion. Destroy
      // immediately on ranged early-stop so unread tail bytes never stall close.
      try {
        if (stoppedEarly) {
          data.destroy();
        } else {
          await data.close();
        }
      } on IOException catch (e, st) {
        ErrorLogger.log(
          'FTP data socket did not close cleanly at the end of a read',
          error: e,
          stackTrace: st,
          category: 'RemoteSources',
        );
      }
      data = null;
      completed = await _session.completeTransfer();
    } on AppError {
      rethrow;
    } on TimeoutException catch (e, st) {
      ErrorLogger.log(
        'FTP transfer timed out',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
        meta: {'authority': source.authority},
      );
      throw RemoteUnavailableError(
        code: 'FTP_TIMEOUT',
        userMessage: 'The server stopped sending data. Check the connection.',
        cause: e,
        stackTrace: st,
      );
    } on SocketException catch (e, st) {
      ErrorLogger.log(
        'FTP transfer socket failed',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
        meta: {'authority': source.authority},
      );
      throw RemoteUnavailableError(
        code: 'FTP_SOCKET',
        userMessage: 'The download was interrupted. Please try again.',
        cause: e,
        stackTrace: st,
      );
    } on FtpClosedError catch (e, st) {
      ErrorLogger.log(
        'FTP server closed the control connection mid-transfer',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
        meta: {'authority': source.authority},
      );
      throw RemoteUnavailableError(
        code: 'FTP_CLOSED',
        userMessage: 'The server closed the connection.',
        cause: e,
        stackTrace: st,
      );
    } finally {
      try {
        // Destroy on abnormal/canceled teardown so lingering server buffers or
        // FIN handshakes never stall subsequent transfers.
        data?.destroy();
      } catch (e, st) {
        ErrorLogger.log(
          'FTP data socket did not close cleanly',
          error: e,
          stackTrace: st,
          category: 'RemoteSources',
        );
      }
      if (!completed) {
        // An abandoned transfer (seek, cancel or error) leaves a reply pending
        // on the control channel; reconnecting is the only clean recovery.
        await _session.abort();
      }
      _transferLock.release();
    }
  }

  /// Logs in and runs `NOOP` to prove the session works.
  @override
  Future<bool> testConnection() => _transferLock.protect(() async {
        final watch = Stopwatch()..start();
        try {
          await _session.ensureConnected();
          final reply = await _session.requireControl().command('NOOP');
          final ok = reply.isSuccess;
          ErrorLogger.log(
            'FTP probe ${ok ? 'succeeded' : 'failed'} in '
            '${watch.elapsedMilliseconds} ms (code ${reply.code})',
            category: 'RemoteSources',
            meta: {'authority': source.authority},
          );
          return ok;
        } on AppError catch (e, st) {
          ErrorLogger.log(
            'FTP probe failed: ${e.code}',
            error: e,
            stackTrace: st,
            category: 'RemoteSources',
            meta: {'authority': source.authority},
          );
          return false;
        } catch (e, st) {
          ErrorLogger.log(
            'FTP probe failed unexpectedly',
            error: e,
            stackTrace: st,
            category: 'RemoteSources',
            meta: {'authority': source.authority},
          );
          return false;
        }
      });

  /// Sends `QUIT` and closes the session.
  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _session.quit();
  }

  Future<List<RemoteEntry>> _enrichTypes(List<RemoteEntry> entries) async {
    if (entries.isEmpty) return entries;
    final enriched = <RemoteEntry>[];
    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      if (index >= maxNlstStatEntries) {
        enriched.add(entry);
        continue;
      }
      final metadata = await _statUnlocked(entry.path);
      enriched.add(metadata ?? entry);
    }
    enriched.sort(RemoteEntry.compare);
    return enriched;
  }

  String _resolve(String path) {
    final root = RemoteSource.normalizeRootPath(source.rootPath);
    final value = _relative(path);
    if (value.isEmpty) return root;
    return root == '/' ? '/$value' : '$root/$value';
  }

  String _relative(String path) {
    if (_containsControlChars(path)) {
      throw const RemoteProtocolError(
        code: 'FTP_PATH_TRAVERSAL',
        userMessage: 'That path is not allowed.',
      );
    }
    var value = path.trim().replaceAll('\\', '/');
    while (value.startsWith('/')) {
      value = value.substring(1);
    }
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    for (final segment in value.split('/')) {
      if (_isTraversalSegment(segment)) {
        throw const RemoteProtocolError(
          code: 'FTP_PATH_TRAVERSAL',
          userMessage: 'That path is not allowed.',
        );
      }
    }
    return value;
  }

  /// Display name for a `stat` call; `''` is the configured root itself.
  String _entryName(String relative, String absolute) {
    if (relative.isNotEmpty) return relative.split('/').last;
    final segments =
        absolute.split('/').where((segment) => segment.isNotEmpty).toList();
    return segments.isEmpty ? '/' : segments.last;
  }

  static bool _containsControlChars(String value) =>
      value.contains('\r') || value.contains('\n') || value.contains('\u0000');

  static bool _isTraversalSegment(String segment) {
    if (segment.isEmpty) return false;
    if (_containsControlChars(segment)) return true;
    if (segment == '..') return true;
    try {
      final decoded = Uri.decodeComponent(segment);
      return decoded == '..' || _containsControlChars(decoded);
    } on ArgumentError {
      return true;
    } on FormatException {
      return true;
    }
  }
}
