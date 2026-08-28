// lib/core/errors/failures.dart
import 'package:fpdart/fpdart.dart';

typedef Result<T> = Either<AppFailure, T>;
typedef Failure = AppFailure;

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

class AlreadyQueuedFailure extends DownloadFailure {
  const AlreadyQueuedFailure(super.message, [super.error]);
}

class InsufficientStorageFailure extends StorageFailure {
  final int? neededBytes;
  final int? availableBytes;

  const InsufficientStorageFailure(
    String message, {
    this.neededBytes,
    this.availableBytes,
    dynamic error,
  }) : super(message, error);
}

class CorruptDownloadFailure extends DownloadFailure {
  const CorruptDownloadFailure(super.message, [super.error]);
}

class FeatureDisabledFailure extends DownloadFailure {
  const FeatureDisabledFailure(
      [super.message = 'Unavailable in this build', super.error]);
}

class InvalidTransitionFailure extends DownloadFailure {
  final String from;
  final String to;

  const InvalidTransitionFailure(this.from, this.to, [dynamic error])
      : super('Invalid download status transition: $from -> $to', error);
}

class ValidationFailure extends AppFailure {
  const ValidationFailure(super.message, [super.error]);
}

class FgsTimeoutFailure extends DownloadFailure {
  const FgsTimeoutFailure(super.message, [super.error]);
}

class YtmFailure extends AppFailure {
  final String? code;
  const YtmFailure(super.message, [this.code, super.error]);
}
