// lib/features/remote_sources/ftp_control_connection.dart
//
// P0-1 "remote sources": the FTP control channel.
//
// One socket, UTF-8 decoded line by line, replying through
// [FtpReply.readReply] so RFC 959 multiline answers (`220-...` ... `220 ok`)
// are read as one reply. Transport failures surface as [SocketException] /
// [TimeoutException] and are mapped to typed errors by the provider.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/utils/error_logger.dart';
import 'ftp_protocol.dart';

/// A connected FTP control channel.
class FtpControlConnection {
  FtpControlConnection._(this._socket, this._timeout)
      : _lines = StreamIterator<String>(
          _socket.cast<List<int>>().transform(utf8.decoder).transform(
                const LineSplitter(),
              ),
        );

  /// Opens a TCP connection to [host]:[port] and returns the control channel.
  ///
  /// The caller is responsible for reading the greeting and logging in.
  static Future<FtpControlConnection> connect({
    required String host,
    required int port,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final socket = await Socket.connect(host, port, timeout: timeout);
    socket.setOption(SocketOption.tcpNoDelay, true);
    return FtpControlConnection._(socket, timeout);
  }

  final Socket _socket;
  final Duration _timeout;
  final StreamIterator<String> _lines;

  /// Address of the server, used as the data-connection host when PASV
  /// advertises a private address (typical NAT misconfiguration).
  String get peerAddress => _socket.remoteAddress.address;

  /// Whether the socket is still writable.
  bool get isOpen => !_closed;

  /// Whether the channel can still be trusted for the next command.
  ///
  /// Set to `false` on *any* transport or decoding failure: once a reply line
  /// was lost or could not be decoded, the reply stream is out of step with
  /// the server and the only safe recovery is a fresh connection.
  bool get isHealthy => !_closed && !_broken;
  bool _closed = false;
  bool _broken = false;

  /// Marks the channel unusable and drops the socket.
  void invalidate() {
    if (_broken && _closed) return;
    _broken = true;
    try {
      _socket.destroy();
    } catch (e, st) {
      ErrorLogger.log(
        'FTP control socket did not close after an error',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
      );
    }
  }

  /// Reads one complete reply.
  Future<FtpReply> readReply() async {
    try {
      return await FtpReply.readReply(_nextLine);
    } on FtpClosedError {
      invalidate();
      rethrow;
    } on FtpFormatError {
      invalidate();
      rethrow;
    } on SocketException {
      invalidate();
      rethrow;
    } on TimeoutException {
      invalidate();
      rethrow;
    }
  }

  /// Sends [command] without waiting for the reply.
  ///
  /// Callers must never pass a password in a log line; this method does not log
  /// commands at all so a `PASS` cannot leak.
  Future<void> send(String command) async {
    if (!isHealthy) throw const FtpClosedError();
    try {
      _socket.add(utf8.encode('$command\r\n'));
      await _socket.flush().timeout(_timeout);
    } on SocketException {
      invalidate();
      rethrow;
    } on TimeoutException {
      invalidate();
      rethrow;
    }
  }

  /// Sends [command] and reads exactly one reply.
  Future<FtpReply> command(String command) async {
    await send(command);
    return readReply();
  }

  /// Closes the socket and stops the line iterator.
  Future<void> destroy() async {
    if (_closed) return;
    _closed = true;
    _broken = true;
    try {
      await _lines.cancel();
    } catch (e, st) {
      ErrorLogger.log(
        'FTP control line iterator did not cancel cleanly',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
      );
    }
    try {
      _socket.destroy();
    } catch (e, st) {
      ErrorLogger.log(
        'FTP control socket did not close cleanly',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
      );
    }
  }

  Future<String?> _nextLine() async {
    if (!isHealthy) throw const FtpClosedError();
    try {
      final hasNext = await _lines.moveNext().timeout(_timeout);
      return hasNext ? _lines.current : null;
    } on FormatException catch (e, st) {
      // A malformed UTF-8 byte sequence means the line framing was lost; keep
      // going would read half a reply and desynchronise every later command.
      ErrorLogger.log(
        'FTP control reply was not valid UTF-8; dropping the session',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
      );
      invalidate();
      throw const FtpFormatError('FTP reply is not valid UTF-8');
    }
  }
}
