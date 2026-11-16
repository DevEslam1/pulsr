// lib/domain/interfaces/remote_fs_provider.dart
//
// P0-1 "remote sources": the single contract every network filesystem
// (WebDAV, FTP, SMB) implements, plus the typed failures they may raise.
//
// The provider layer never invents success: a transport that is missing, not
// configured or rejected by the server throws one of the [AppError] subtypes
// below, and the UI renders its [AppError.userMessage] verbatim.
import '../../core/errors/app_error_base.dart';
import '../models/remote_source.dart';

/// Credentials were missing, rejected or expired (HTTP 401/403, FTP 530,
/// SMB logon failure).
class RemoteAuthError extends AppError {
  /// Creates an authentication failure.
  const RemoteAuthError({
    required super.code,
    required super.userMessage,
    super.cause,
    super.stackTrace,
  });
}

/// The requested path does not exist on the server (HTTP 404, FTP 550).
class RemoteNotFoundError extends AppError {
  /// Creates a not-found failure.
  const RemoteNotFoundError({
    required super.code,
    required super.userMessage,
    super.cause,
    super.stackTrace,
  });
}

/// The endpoint could not be reached, the transfer timed out, or the platform
/// support needed for this transport is absent from the current build.
class RemoteUnavailableError extends AppError {
  /// Creates an unreachable/unavailable failure.
  const RemoteUnavailableError({
    required super.code,
    required super.userMessage,
    super.cause,
    super.stackTrace,
  });
}

/// The server answered, but not in a way this provider can interpret
/// (unexpected status code, malformed XML/listing/reply, disabled method).
class RemoteProtocolError extends AppError {
  /// Creates a protocol-level failure.
  const RemoteProtocolError({
    required super.code,
    required super.userMessage,
    super.cause,
    super.stackTrace,
  });
}

/// Read access to one remote library.
///
/// Implementations are cheap wrappers around a connection: construct one per
/// source, call [testConnection] before showing a browser, and call [close]
/// when the screen or stream is done with it.
///
/// Paths are relative to `source.rootPath` and use `/`; `''` is the root
/// directory. Implementations never throw for a plain "no such file" without
/// using [RemoteNotFoundError].
abstract class RemoteFsProvider {
  /// The source this provider is bound to.
  RemoteSource get source;

  /// Lists the direct children of [path], folders first then files.
  ///
  /// Throws [RemoteNotFoundError] when [path] does not exist,
  /// [RemoteAuthError] when credentials are rejected and
  /// [RemoteUnavailableError] when the host cannot be reached.
  Future<List<RemoteEntry>> list(String path);

  /// Returns metadata for [path], or `null` when it does not exist.
  Future<RemoteEntry?> stat(String path);

  /// Streams the bytes of [path], from [start] to [end] inclusive.
  ///
  /// [end] is inclusive and `null` means "until the end of the file". The
  /// stream is cancelled by the consumer (seek/skip); implementations must
  /// release their connection when that happens. Servers that ignore the range
  /// request are handled by skipping [start] bytes locally.
  Stream<List<int>> openRead(String path, {int start = 0, int? end});

  /// Performs the cheapest round-trip that proves the source is usable.
  ///
  /// Returns `false` (and logs) instead of throwing, so a settings screen can
  /// show a red dot without try/catch noise.
  Future<bool> testConnection();

  /// Releases sockets, sessions and any native handle held by the provider.
  Future<void> close();
}
