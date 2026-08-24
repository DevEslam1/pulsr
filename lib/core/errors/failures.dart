// lib/core/errors/failures.dart
import 'package:fpdart/fpdart.dart';

typedef Result<T> = Either<AppFailure, T>;

abstract class AppFailure {
  final String message;
  final dynamic error;

  const AppFailure(this.message, [this.error]);

  @override
  String toString() => '$runtimeType: $message';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppFailure &&
        other.runtimeType == runtimeType &&
        other.message == message &&
        other.error == error;
  }

  @override
  int get hashCode => Object.hash(runtimeType, message, error);
}

class DatabaseFailure extends AppFailure {
  const DatabaseFailure(super.message, [super.error]);
}

class AudioPlaybackFailure extends AppFailure {
  const AudioPlaybackFailure(super.message, [super.error]);
}

class PermissionFailure extends AppFailure {
  const PermissionFailure(super.message, [super.error]);
}

class StorageFailure extends AppFailure {
  const StorageFailure(super.message, [super.error]);
}

class LyricsFailure extends AppFailure {
  const LyricsFailure(super.message, [super.error]);
}

class TagEditFailure extends AppFailure {
  const TagEditFailure(super.message, [super.error]);
}

class PlaylistImportFailure extends AppFailure {
  const PlaylistImportFailure(super.message, [super.error]);
}

class BackupFailure extends AppFailure {
  const BackupFailure(super.message, [super.error]);
}

class DownloadFailure extends AppFailure {
  const DownloadFailure(super.message, [super.error]);
}

