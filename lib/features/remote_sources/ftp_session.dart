// lib/features/remote_sources/ftp_session.dart
//
// P0-1 "remote sources": one FTP control session.
//
// Owns the control socket, the login handshake, passive data connections and
// the reply bookkeeping that keeps a transfer in step with the server. The
// provider above it decides what to do with the bytes; this layer only speaks
// the protocol.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mutex/mutex.dart';

import '../../core/errors/app_error_base.dart';
import '../../core/network/remote_target_policy.dart';
import '../../core/utils/error_logger.dart';
import '../../domain/interfaces/remote_fs_provider.dart';
import '../../domain/models/remote_source.dart';
import 'ftp_control_connection.dart';
import 'ftp_error_mapper.dart';
import 'ftp_protocol.dart';

/// A logged-in FTP session with one reusable control connection.
class FtpSession {
  /// Creates a session for [source].
  ///
  /// [username] defaults to the source's username, then to `anonymous`;
  /// [password] is never logged.
  FtpSession({
    required this.source,
    required this.errors,
    String? username,
    String? password,
    Duration timeout = const Duration(seconds: 30),
  })  : _username = username,
        _password = password,
        _timeout = timeout;

  /// Largest LIST/NLST payload accepted before the listing is refused.
  static const int maxListingBytes = 4 * 1024 * 1024;

  /// Source this session talks to.
  final RemoteSource source;

  /// Reply/transport mapper shared with the provider.
  final FtpErrorMapper errors;

  final String? _username;
  final String? _password;
  final Duration _timeout;
  final Mutex _sessionLock = Mutex();

  FtpControlConnection? _control;
  String _homeDir = '/';
  bool _closed = false;

  /// Whether a *usable* control connection is open.
  ///
  /// A socket that failed and was marked unhealthy reports `false`, so callers
  /// can tell "reconnect will work" apart from "the same dead socket".
  bool get isConnected => _control?.isHealthy ?? false;

  /// Working directory reported by `PWD` after login (`/` before that).
  String get homeDir => _homeDir;

  /// Connects and logs in when needed; safe to call before every command.
  ///
  /// A cached control connection that failed (closed socket, malformed reply,
  /// timeout) is discarded instead of reused, and a connect/login attempt that
  /// dies with [FtpClosedError] or [SocketException] is retried exactly once
  /// on a fresh connection. Two failures in a row are reported, so a dead host
  /// still fails fast instead of looping.
  Future<void> ensureConnected() async {
    if (_closed) {
      throw StateError('This FTP session has been closed.');
    }
    final current = _control;
    if (current != null) {
      if (current.isHealthy) return;
      _control = null;
      await current.destroy();
    }
    await _sessionLock.protect(() async {
      if (_control != null) return;
      var attempts = 0;
      while (true) {
        try {
          await _connectAndLogin();
          return;
        } on FtpClosedError catch (e, st) {
          attempts++;
          if (attempts > 1) {
            ErrorLogger.log(
              'FTP reconnect failed: the server closed the connection again',
              error: e,
              stackTrace: st,
              category: 'RemoteSources',
              meta: {'authority': source.authority},
            );
            throw RemoteUnavailableError(
              code: 'FTP_CLOSED',
              userMessage: 'The server closed the connection during login.',
              cause: e,
              stackTrace: st,
            );
          }
          ErrorLogger.log(
            'FTP control connection closed; reconnecting once',
            error: e,
            stackTrace: st,
            category: 'RemoteSources',
            meta: {'authority': source.authority},
          );
        } on SocketException catch (e, st) {
          attempts++;
          if (attempts > 1) {
            ErrorLogger.log(
              'FTP reconnect failed on the socket',
              error: e,
              stackTrace: st,
              category: 'RemoteSources',
              meta: {'authority': source.authority},
            );
            throw RemoteUnavailableError(
              code: 'FTP_CONNECT',
              userMessage: 'Could not connect to ${source.authority}.',
              cause: e,
              stackTrace: st,
            );
          }
          ErrorLogger.log(
            'FTP control socket failed; reconnecting once',
            error: e,
            stackTrace: st,
            category: 'RemoteSources',
            meta: {'authority': source.authority},
          );
        }
      }
    });
  }

  /// Returns the control connection, throwing when the session is not open.
  FtpControlConnection requireControl() {
    final control = _control;
    if (control == null) {
      throw const RemoteUnavailableError(
        code: 'FTP_NOT_CONNECTED',
        userMessage: 'Not connected to the FTP server.',
      );
    }
    return control;
  }

  /// Opens a passive data connection (`EPSV` first, then `PASV`).
  ///
  /// The data connection always goes to the address the control connection is
  /// already talking to. A `PASV` reply carries an advisory IP that a hostile
  /// or NAT-ed server can set to anything; connecting to it is the classic FTP
  /// bounce primitive. The advertised host is still checked against
  /// [RemoteTargetPolicy] so a private/loopback spoof is visible in the log.
  Future<Socket> openDataSocket() async {
    final control = requireControl();
    final peerAddress = control.peerAddress;
    final epsv = await control.command('EPSV');
    if (epsv.code == 229) {
      final port = FtpListingParser.parseExtendedPassiveReply(epsv.message);
      if (port != null) {
        try {
          return await Socket.connect(
            peerAddress,
            port,
            timeout: _timeout,
          );
        } on SocketException catch (e, st) {
          ErrorLogger.log(
            'FTP EPSV data connection failed; retrying with PASV',
            error: e,
            stackTrace: st,
            category: 'RemoteSources',
            meta: {'port': port},
          );
        }
      }
    }
    final pasv = await control.command('PASV');
    if (pasv.code != 227) throw errors.mapReply(pasv, 'PASV');
    final parsed = FtpListingParser.parsePassiveReply(pasv.message);
    if (parsed == null) {
      throw const RemoteProtocolError(
        code: 'FTP_PASV_UNPARSABLE',
        userMessage: 'The server sent an unreadable passive-mode address.',
      );
    }
    final advertised = parsed.host;
    if (advertised != peerAddress) {
      final unsafe = RemoteTargetPolicy.isUnsafeHost(advertised);
      ErrorLogger.log(
        unsafe
            ? 'FTP PASV advertised a private/non-routable address; using the '
                'control peer instead'
            : 'FTP PASV advertised an address that differs from the control '
                'peer; using the control peer instead',
        category: 'RemoteSources',
        meta: {'authority': source.authority},
      );
    }
    return Socket.connect(peerAddress, parsed.port, timeout: _timeout);
  }

  /// Runs a listing command (`LIST`/`NLST`) and returns its text payload.
  ///
  /// The listing is decoded with `allowMalformed` on purpose: servers commonly
  /// send Latin-1 filenames, and one bad byte must not throw away a whole
  /// folder. A decode failure on the *control* channel is different — that one
  /// throws [FtpFormatError] and invalidates the session (see
  /// [FtpControlConnection]).
  Future<String> readListing(String command) async {
    final control = requireControl();
    final data = await openDataSocket();
    final buffer = StringBuffer();
    try {
      final ack = await control.command(command);
      if (!ack.isIntermediate && !ack.isSuccess) {
        throw errors.mapReply(ack, command.split(' ').first);
      }
      await for (final chunk in data.cast<List<int>>().transform(
        const Utf8Decoder(allowMalformed: true),
      ).timeout(_timeout)) {
        buffer.write(chunk);
        if (buffer.length > maxListingBytes) {
          throw const RemoteProtocolError(
            code: 'FTP_LISTING_OVERSIZED',
            userMessage: 'This folder contains too many entries to list.',
          );
        }
      }
    } on FormatException catch (e, st) {
      // The control reply could not be decoded: the session is out of step and
      // cannot be reused for the next command.
      ErrorLogger.log(
        'FTP listing reply could not be decoded; dropping the session',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
        meta: {'authority': source.authority},
      );
      await abort();
      throw RemoteProtocolError(
        code: 'FTP_DECODE',
        userMessage: 'The server sent text this client cannot decode.',
        cause: e,
        stackTrace: st,
      );
    } finally {
      try {
        await data.close();
      } on IOException catch (e, st) {
        ErrorLogger.log(
          'FTP data socket did not close cleanly after a listing',
          error: e,
          stackTrace: st,
          category: 'RemoteSources',
        );
      }
    }
    final done = await control.readReply();
    if (done.code != 226 && done.code != 250) {
      ErrorLogger.log(
        'FTP listing finished with an unexpected completion code',
        category: 'RemoteSources',
        meta: {'code': done.code, 'authority': source.authority},
      );
    }
    return buffer.toString();
  }

  /// Reads the transfer completion reply; returns whether the session is sane.
  ///
  /// The caller must close (or drain) the data socket *before* awaiting this:
  /// plenty of servers only emit `226` once the data connection is gone, and
  /// reading the reply first deadlocks them against a client that still holds
  /// the socket open. `426` is accepted as well — it is the expected answer
  /// when the client closed the data connection after a ranged read, and the
  /// control channel itself is still in step.
  Future<bool> completeTransfer() async {
    final control = requireControl();
    try {
      final done =
          await control.readReply().timeout(const Duration(seconds: 10));
      if (done.code == 226 || done.code == 250) return true;
      if (done.code == 426) {
        ErrorLogger.log(
          'FTP transfer was closed early (426); the control channel is intact',
          category: 'RemoteSources',
          meta: {'authority': source.authority},
        );
        return true;
      }
      ErrorLogger.log(
        'FTP transfer completed with code ${done.code}',
        category: 'RemoteSources',
        meta: {'authority': source.authority},
      );
      return false;
    } on TimeoutException catch (e, st) {
      ErrorLogger.log(
        'FTP transfer completion reply did not arrive',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
      );
      return false;
    } on SocketException catch (e, st) {
      ErrorLogger.log(
        'FTP control socket failed while awaiting the completion reply',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
      );
      return false;
    } on FtpClosedError catch (e, st) {
      ErrorLogger.log(
        'FTP control connection closed while awaiting the completion reply',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
      );
      return false;
    } on FtpFormatError catch (e, st) {
      ErrorLogger.log(
        'FTP completion reply was malformed',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
      );
      return false;
    }
  }

  /// Drops the control connection so the next command starts from a clean state.
  Future<void> abort() async {
    final control = _control;
    _control = null;
    await control?.destroy();
  }

  /// Sends `QUIT`, waits briefly for the acknowledgement and closes the socket.
  Future<void> quit() async {
    if (_closed) return;
    _closed = true;
    final control = _control;
    _control = null;
    if (control == null) return;
    if (!control.isHealthy) {
      // A reply is already pending (or the socket is dead): sending QUIT would
      // race the outstanding read, so just drop the socket.
      await control.destroy();
      return;
    }
    try {
      await control.send('QUIT');
      // Waiting for 221 lets the server finish before the socket disappears;
      // the bound keeps a stuck peer from blocking the screen's dispose.
      await control.readReply().timeout(const Duration(seconds: 2));
    } on SocketException catch (e, st) {
      ErrorLogger.log(
        'FTP QUIT could not be sent',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
      );
    } on FtpClosedError catch (e, st) {
      ErrorLogger.log(
        'FTP control connection was already closed',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
      );
    } on TimeoutException catch (e, st) {
      ErrorLogger.log(
        'FTP did not acknowledge QUIT',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
      );
    } on FtpFormatError catch (e, st) {
      ErrorLogger.log(
        'FTP sent an unreadable answer to QUIT',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
      );
    } finally {
      await control.destroy();
    }
  }

  Future<void> _connectAndLogin() async {
    FtpControlConnection? control;
    try {
      control = await FtpControlConnection.connect(
        host: source.host,
        port: source.port,
        timeout: _timeout,
      );
      final greeting = await control.readReply();
      if (greeting.code != 220 && greeting.code != 120) {
        throw errors.mapReply(greeting, 'greeting');
      }
      final configuredUser = _username;
      final user = (configuredUser == null || configuredUser.isEmpty)
          ? 'anonymous'
          : configuredUser;
      var reply = await control.command('USER $user');
      if (reply.code == 331 || reply.code == 332) {
        // The password goes out exactly here and is never logged.
        reply = await control.command('PASS ${_password ?? ''}');
        if (reply.code != 230 && reply.code != 202) {
          throw RemoteAuthError(
            code: 'FTP_AUTH_FAILED',
            userMessage: 'The server rejected the username or password '
                '(${reply.code}).',
          );
        }
      } else if (reply.code != 230) {
        throw errors.mapReply(reply, 'login');
      }
      reply = await control.command('TYPE I');
      if (!reply.isSuccess) throw errors.mapReply(reply, 'TYPE I');
      final pwd = await control.command('PWD');
      if (pwd.isSuccess) {
        _homeDir = _parseWorkingDirectory(pwd.message) ?? '/';
      }
      _control = control;
    } on AppError {
      await control?.destroy();
      rethrow;
    } on TimeoutException catch (e, st) {
      await control?.destroy();
      ErrorLogger.log(
        'FTP login timed out',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
        meta: {'authority': source.authority},
      );
      throw RemoteUnavailableError(
        code: 'FTP_TIMEOUT',
        userMessage: '${source.authority} did not answer in time.',
        cause: e,
        stackTrace: st,
      );
    } on SocketException catch (e, st) {
      await control?.destroy();
      ErrorLogger.log(
        'FTP connection failed',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
        meta: {'authority': source.authority},
      );
      // Rethrown raw: [ensureConnected] retries once on a fresh connection
      // before mapping the final failure for the UI.
      rethrow;
    } on FtpClosedError catch (e, st) {
      await control?.destroy();
      ErrorLogger.log(
        'FTP server closed the connection during login',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
        meta: {'authority': source.authority},
      );
      rethrow;
    } on FtpFormatError catch (e, st) {
      await control?.destroy();
      ErrorLogger.log(
        'FTP server sent a malformed reply',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
        meta: {'authority': source.authority},
      );
      throw RemoteProtocolError(
        code: 'FTP_FORMAT',
        userMessage: 'The server answered in a way this client cannot read.',
        cause: e,
        stackTrace: st,
      );
    }
  }

  static String? _parseWorkingDirectory(String message) {
    final start = message.indexOf('"');
    if (start == -1) return null;
    final end = message.indexOf('"', start + 1);
    if (end == -1) return null;
    final value = message.substring(start + 1, end);
    return value.isEmpty ? null : value;
  }
}
