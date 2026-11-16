// lib/features/remote_sources/webdav_errors.dart
//
// P0-1 "remote sources": HTTP status -> typed error for WebDAV.
//
// Kept apart from the provider so the mapping table is testable on its own and
// the provider file only carries transport code.
import '../../core/errors/app_error_base.dart';
import '../../domain/interfaces/remote_fs_provider.dart';

/// Maps a non-2xx WebDAV status to the [AppError] the UI understands.
///
/// [path] is provider-relative and only used to make messages specific; the
/// returned messages never contain credentials.
AppError webDavStatusError(int status, {required String path}) {
  if (status == 401 || status == 403) {
    return RemoteAuthError(
      code: 'WEBDAV_AUTH',
      userMessage: 'The server rejected these credentials ($status).',
    );
  }
  if (status == 404) {
    return RemoteNotFoundError(
      code: 'WEBDAV_NOT_FOUND',
      userMessage: 'This folder no longer exists on the server.',
    );
  }
  if (status == 405) {
    return RemoteProtocolError(
      code: 'WEBDAV_METHOD_DISABLED',
      userMessage: 'The server does not allow WebDAV browsing (405).',
    );
  }
  if (status == 416) {
    return RemoteProtocolError(
      code: 'WEBDAV_RANGE_UNSATISFIABLE',
      userMessage: 'The requested part of the file is outside its size.',
    );
  }
  if (status == 423) {
    return RemoteUnavailableError(
      code: 'WEBDAV_LOCKED',
      userMessage: 'The server has locked this file (423).',
    );
  }
  if (status >= 500) {
    return RemoteUnavailableError(
      code: 'WEBDAV_SERVER_ERROR',
      userMessage: 'The server reported an error ($status). Try again later.',
    );
  }
  return RemoteProtocolError(
    code: 'WEBDAV_HTTP_$status',
    userMessage: 'Unexpected server answer ($status) for "$path".',
  );
}
