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
  const AppFailure(String message, [String code = 'APP_FAILURE', Object? cause])
      : super(code: code, userMessage: message, cause: cause);

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
  const DatabaseFailure(String message, [Object? error])
      : super(message, 'DB_FAILURE', error);
}

class AudioPlaybackFailure extends AppFailure {
  const AudioPlaybackFailure(String message, [Object? error])
      : super(message, 'AUDIO_PLAYBACK_FAILURE', error);
}

class PermissionFailure extends AppFailure {
  const PermissionFailure(String message, [Object? error])
      : super(message, 'PERMISSION_FAILURE', error);
}

class StorageFailure extends AppFailure {
  const StorageFailure(String message, [Object? error])
      : super(message, 'STORAGE_FAILURE', error);
}

class LyricsFailure extends AppFailure {
  const LyricsFailure(String message, [Object? error])
      : super(message, 'LYRICS_FAILURE', error);
}

class TagEditFailure extends AppFailure {
  const TagEditFailure(String message, [Object? error])
      : super(message, 'TAG_EDIT_FAILURE', error);
}

class PlaylistImportFailure extends AppFailure {
  const PlaylistImportFailure(String message, [Object? error])
      : super(message, 'PLAYLIST_IMPORT_FAILURE', error);
}

class BackupFailure extends AppFailure {
  const BackupFailure(String message, [Object? error])
      : super(message, 'BACKUP_FAILURE', error);
}

class DownloadFailure extends AppFailure {
  const DownloadFailure(String message, [Object? error])
      : super(message, 'DOWNLOAD_FAILURE', error);
}

/// Catch-all failure used when an [AppError] cannot be mapped to a more
/// specific domain failure.
class GenericFailure extends AppFailure {
  const GenericFailure(String message, [Object? error])
      : super(message, 'GENERIC_FAILURE', error);
}
