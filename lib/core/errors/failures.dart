// lib/core/errors/failures.dart
//
// Legacy failure taxonomy, retained by name for existing call sites but now a
// thin layer over the canonical error base in `app_error_base.dart`. Because
// `AppFailure is AppError`, a single error type flows through `Result<T>` and
// through `resolveAppError()`; there is no longer a second, unrelated error
// hierarchy.
import 'package:fpdart/fpdart.dart';

import 'app_error_base.dart';

/// The single canonical result type: either an [AppFailure] (an [AppError]) or
/// a value of type [T].
typedef Result<T> = Either<AppFailure, T>;

/// Base class for domain failures. Extends [AppError] so every failure carries
/// the standard [code]/[userMessage]/[cause]/[stackTrace] metadata and can be
/// handled by the same exhaustive-matching and reporting code as the canonical
/// subtypes.
abstract class AppFailure extends AppError {
  const AppFailure(String message,
      [String code = 'APP_FAILURE', Object? cause, StackTrace? stackTrace])
      : super(
          code: code,
          userMessage: message,
          cause: cause,
          stackTrace: stackTrace,
        );

  @override
  String toString() => '$runtimeType: $message';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppFailure &&
        other.runtimeType == runtimeType &&
        other.message == message &&
        other.cause == cause;
  }

  @override
  int get hashCode => Object.hash(runtimeType, message, cause);
}

class DatabaseFailure extends AppFailure {
  const DatabaseFailure(String message, [Object? error, StackTrace? stackTrace])
      : super(message, 'DB_FAILURE', error, stackTrace);
}

class AudioPlaybackFailure extends AppFailure {
  const AudioPlaybackFailure(String message,
      [Object? error, StackTrace? stackTrace])
      : super(message, 'AUDIO_PLAYBACK_FAILURE', error, stackTrace);
}

class PermissionFailure extends AppFailure {
  const PermissionFailure(String message,
      [Object? error, StackTrace? stackTrace])
      : super(message, 'PERMISSION_FAILURE', error, stackTrace);
}

class StorageFailure extends AppFailure {
  const StorageFailure(String message, [Object? error, StackTrace? stackTrace])
      : super(message, 'STORAGE_FAILURE', error, stackTrace);
}

class LyricsFailure extends AppFailure {
  const LyricsFailure(String message, [Object? error, StackTrace? stackTrace])
      : super(message, 'LYRICS_FAILURE', error, stackTrace);
}

class TagEditFailure extends AppFailure {
  const TagEditFailure(String message, [Object? error, StackTrace? stackTrace])
      : super(message, 'TAG_EDIT_FAILURE', error, stackTrace);
}

class PlaylistImportFailure extends AppFailure {
  const PlaylistImportFailure(String message,
      [Object? error, StackTrace? stackTrace])
      : super(message, 'PLAYLIST_IMPORT_FAILURE', error, stackTrace);
}

class BackupFailure extends AppFailure {
  const BackupFailure(String message, [Object? error, StackTrace? stackTrace])
      : super(message, 'BACKUP_FAILURE', error, stackTrace);
}

class DownloadFailure extends AppFailure {
  const DownloadFailure(String message, [Object? error, StackTrace? stackTrace])
      : super(message, 'DOWNLOAD_FAILURE', error, stackTrace);
}

class NetworkFailure extends AppFailure {
  const NetworkFailure(String message, [Object? error, StackTrace? stackTrace])
      : super(message, 'NETWORK_FAILURE', error, stackTrace);
}

class YtmFailure extends AppFailure {
  const YtmFailure(String message, [Object? error, StackTrace? stackTrace])
      : super(message, 'YTM_FAILURE', error, stackTrace);
}

/// Catch-all failure used when an [AppError] cannot be mapped to a more
/// specific domain failure.
class GenericFailure extends AppFailure {
  const GenericFailure(String message, [Object? error, StackTrace? stackTrace])
      : super(message, 'GENERIC_FAILURE', error, stackTrace);
}
