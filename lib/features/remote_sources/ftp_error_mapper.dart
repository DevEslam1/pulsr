// lib/features/remote_sources/ftp_error_mapper.dart
//
// P0-1 "remote sources": FTP reply -> typed error, plus the transport guard
// that turns socket/timeout/format failures into the same taxonomy.
//
// Extracted from the provider so the mapping table is a single, testable unit
// and every provider method shares one logging policy.
import 'dart:async';
import 'dart:io';

import '../../core/errors/app_error_base.dart';
import '../../core/utils/error_logger.dart';
import '../../domain/interfaces/remote_fs_provider.dart';
import '../../domain/models/remote_source.dart';
import 'ftp_protocol.dart';

/// Maps FTP transport failures and server replies to [AppError] instances.
class FtpErrorMapper {
  /// Creates a mapper that logs against [source].
  const FtpErrorMapper({required this.source});

  /// Source whose authority appears in logs (never credentials).
  final RemoteSource source;

  /// Runs [run], translating transport failures into typed errors.
  ///
  /// Typed errors pass through unchanged so a `530` mapped by [mapReply] is not
  /// re-wrapped as a timeout.
  Future<T> guard<T>(String action, Future<T> Function() run) async {
    try {
      return await run();
    } on AppError {
      rethrow;
    } on TimeoutException catch (e, st) {
      ErrorLogger.log(
        'FTP $action timed out',
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
      ErrorLogger.log(
        'FTP $action failed on the socket',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
        meta: {'authority': source.authority},
      );
      throw RemoteUnavailableError(
        code: 'FTP_SOCKET',
        userMessage: 'The connection to ${source.authority} failed.',
        cause: e,
        stackTrace: st,
      );
    } on FtpClosedError catch (e, st) {
      ErrorLogger.log(
        'FTP $action lost the control connection',
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
    } on FtpFormatError catch (e, st) {
      ErrorLogger.log(
        'FTP $action got a malformed reply',
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
    } on FormatException catch (e, st) {
      ErrorLogger.log(
        'FTP $action could not decode the server output',
        error: e,
        stackTrace: st,
        category: 'RemoteSources',
        meta: {'authority': source.authority},
      );
      throw RemoteProtocolError(
        code: 'FTP_DECODE',
        userMessage: 'The server sent text this client cannot decode.',
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Maps a failed reply to the error the UI should show.
  AppError mapReply(FtpReply reply, String action) {
    final code = reply.code;
    ErrorLogger.log(
      'FTP $action failed with code $code',
      category: 'RemoteSources',
      meta: {'authority': source.authority},
    );
    if (code == 421 || code == 425 || code == 426 || code == 450) {
      return RemoteUnavailableError(
        code: 'FTP_UNAVAILABLE_$code',
        userMessage: 'The server is temporarily unavailable ($code).',
      );
    }
    if (code == 530 || code == 532 || code == 430) {
      return RemoteAuthError(
        code: 'FTP_AUTH_$code',
        userMessage: 'The server rejected the login ($code).',
      );
    }
    if (code == 550 || code == 553) {
      return RemoteNotFoundError(
        code: 'FTP_NOT_FOUND_$code',
        userMessage: 'The server cannot open that file or folder ($code).',
      );
    }
    if (code >= 500) {
      return RemoteProtocolError(
        code: 'FTP_REFUSED_$code',
        userMessage: 'The server refused the command ($code).',
      );
    }
    return RemoteProtocolError(
      code: 'FTP_UNEXPECTED_$code',
      userMessage: 'Unexpected server answer ($code).',
    );
  }
}
