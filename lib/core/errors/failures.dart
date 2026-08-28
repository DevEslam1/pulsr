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

enum DownloadFailureAction { retry, openSettings, freeSpace, resume, none }

class DownloadFailure extends AppFailure {
  final String l10nKey;
  final DownloadFailureAction action;

  const DownloadFailure(
    super.message, [
    super.error,
    this.l10nKey = 'downloadErrorGeneric',
    this.action = DownloadFailureAction.retry,
  ]);
}

class GenericDownloadFailure extends DownloadFailure {
  const GenericDownloadFailure(
    super.message, [
    super.error,
    super.l10nKey = 'downloadErrorGeneric',
    super.action = DownloadFailureAction.retry,
  ]);
}

class AlreadyQueuedFailure extends DownloadFailure {
  const AlreadyQueuedFailure(
    String message, [
    dynamic error,
  ]) : super(
          message,
          error,
          'downloadErrorAlreadyQueued',
          DownloadFailureAction.none,
        );
}

class InsufficientStorageFailure extends DownloadFailure {
  final int? neededBytes;
  final int? availableBytes;

  const InsufficientStorageFailure(
    String message, {
    this.neededBytes,
    this.availableBytes,
    dynamic error,
  }) : super(
          message,
          error,
          'downloadErrorStorage',
          DownloadFailureAction.freeSpace,
        );
}

class PermissionDeniedFailure extends DownloadFailure {
  const PermissionDeniedFailure(
    String message, [
    dynamic error,
  ]) : super(
          message,
          error,
          'downloadErrorPermission',
          DownloadFailureAction.openSettings,
        );
}

class InterruptedFailure extends DownloadFailure {
  const InterruptedFailure(
    String message, [
    dynamic error,
  ]) : super(
          message,
          error,
          'downloadErrorInterrupted',
          DownloadFailureAction.resume,
        );
}

class NetworkFailure extends DownloadFailure {
  const NetworkFailure(
    String message, [
    dynamic error,
  ]) : super(
          message,
          error,
          'downloadErrorNetwork',
          DownloadFailureAction.retry,
        );
}

class CorruptDownloadFailure extends DownloadFailure {
  const CorruptDownloadFailure(
    String message, [
    dynamic error,
  ]) : super(
          message,
          error,
          'downloadErrorCorrupt',
          DownloadFailureAction.retry,
        );
}

class FeatureDisabledFailure extends DownloadFailure {
  const FeatureDisabledFailure(
    [String message = 'Unavailable in this build', dynamic error]
  ) : super(
          message,
          error,
          'downloadErrorDisabled',
          DownloadFailureAction.none,
        );
}

class InvalidTransitionFailure extends DownloadFailure {
  final String from;
  final String to;

  const InvalidTransitionFailure(this.from, this.to, [dynamic error])
      : super(
          'Invalid download status transition: $from -> $to',
          error,
          'downloadErrorTransition',
          DownloadFailureAction.none,
        );
}

class ValidationFailure extends AppFailure {
  const ValidationFailure(super.message, [super.error]);
}

class FgsTimeoutFailure extends DownloadFailure {
  const FgsTimeoutFailure(
    String message, [
    dynamic error,
  ]) : super(
          message,
          error,
          'downloadErrorTimeout',
          DownloadFailureAction.retry,
        );
}

class YtmFailure extends AppFailure {
  final String? code;
  const YtmFailure(super.message, [this.code, super.error]);
}
