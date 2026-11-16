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
  bool _closed = false;

  /// Reads one complete reply.
  Future<FtpReply> readReply() => FtpReply.readReply(_nextLine);

  /// Sends [command] without waiting for the reply.
  ///
  /// Callers must never pass a password in a log line; this method does not log
  /// commands at all so a `PASS` cannot leak.
  Future<void> send(String command) async {
    if (_closed) throw const FtpClosedError();
    _socket.add(utf8.encode('$command\r\n'));
    await _socket.flush().timeout(_timeout);
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
    final hasNext = await _lines.moveNext().timeout(_timeout);
    return hasNext ? _lines.current : null;
  }
}
