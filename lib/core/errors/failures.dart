// lib/core/errors/failures.dart

abstract class AppFailure {
  final String message;
  final dynamic error;

  const AppFailure(this.message, [this.error]);

  @override
  String toString() => '$runtimeType: $message';
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
