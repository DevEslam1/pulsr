// lib/core/errors/app_error.dart
// FIX-D1: Strongly-typed error taxonomy for Pulsr.
//
// `AppError` itself is defined in `app_error_base.dart` (platform-free) so the
// legacy `AppFailure` hierarchy in `failures.dart` can extend it and the whole
// app shares one error type. This library adds the six canonical subtypes and
// the [resolveAppError] classifier, and re-exports the base.
import 'dart:async';
import 'dart:io';
import 'package:drift/drift.dart'
    show DriftWrappedException, InvalidDataException, CouldNotRollBackException;
import 'package:flutter/services.dart';

import 'app_error_base.dart';
// Imported for [classifyFailure]; does not create a cycle because `failures.dart`
// only depends on the platform-free base.
import 'failures.dart';

export 'app_error_base.dart';

/// Network connectivity, DNS, HTTP, or timeout errors.
class NetworkError extends AppError {
  final int? statusCode;
  final bool isTimeout;

  const NetworkError({
    required super.code,
    required super.userMessage,
    this.statusCode,
    this.isTimeout = false,
    super.cause,
    super.stackTrace,
  });
}

/// Disk IO, database SQLite/Drift, file permissions, or storage space errors.
class StorageError extends AppError {
  final String? path;

  const StorageError({
    required super.code,
    required super.userMessage,
    this.path,
    super.cause,
    super.stackTrace,
  });
}

/// Audio pipeline, codec decode, ExoPlayer/AudioService native playback errors.
class AudioError extends AppError {
  final int? trackId;

  const AudioError({
    required super.code,
    required super.userMessage,
    this.trackId,
    super.cause,
    super.stackTrace,
  });
}

/// YouTube Music API, scraping, bot blocking, or streaming token failures.
class YtmError extends AppError {
  final String? videoId;
  final bool isBotBlock;

  const YtmError({
    required super.code,
    required super.userMessage,
    this.videoId,
    this.isBotBlock = false,
    super.cause,
    super.stackTrace,
  });
}

/// OS permissions: storage, notifications, microphone, or background audio.
class PermissionError extends AppError {
  final String permissionName;

  const PermissionError({
    required super.code,
    required super.userMessage,
    required this.permissionName,
    super.cause,
    super.stackTrace,
  });
}

/// Generic unexpected domain failure.
class GenericAppError extends AppError {
  const GenericAppError({
    required super.code,
    required super.userMessage,
    super.cause,
    super.stackTrace,
  });
}

/// Classifies any arbitrary exception/error into a strongly-typed [AppError].
AppError resolveAppError(Object error, [StackTrace? stackTrace]) {
  if (error is AppError) return error;

  if (error is TimeoutException) {
    return NetworkError(
      code: 'NET_TIMEOUT',
      userMessage: 'The request timed out. Please try again.',
      isTimeout: true,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  // TLS handshake failures are an [IOException], not a [SocketException], so
  // they must be matched before the generic socket case or a bad cert / MITM
  // proxy reads as a plain connectivity blip.
  if (error is HandshakeException) {
    return NetworkError(
      code: 'NET_TLS_ERROR',
      userMessage:
          'Secure connection failed. Check your network or proxy settings.',
      cause: error,
      stackTrace: stackTrace,
    );
  }

  if (error is SocketException || error is HttpException) {
    return NetworkError(
      code: 'NET_SOCKET_ERROR',
      userMessage: 'Network connection failed. Please check your connection.',
      cause: error,
      stackTrace: stackTrace,
    );
  }

  // Drift wraps database/SQLite failures in its own exception types. They are
  // storage failures, not generic ones, so the UI can offer a storage-specific
  // remedy (free space, retry, reset cache) instead of "unexpected error".
  if (error is DriftWrappedException ||
      error is InvalidDataException ||
      error is CouldNotRollBackException) {
    return StorageError(
      code: 'DB_ERROR',
      userMessage: 'A database error occurred. Please try again.',
      cause: error,
      stackTrace: stackTrace,
    );
  }

  if (error is PlatformException) {
    if (error.code.contains('permission') || error.code.contains('DENIED')) {
      return PermissionError(
        code: 'PERM_DENIED',
        userMessage: error.message ?? 'Permission denied.',
        permissionName: error.code,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    if (error.code.contains('audio') || error.code.contains('playback')) {
      return AudioError(
        code: 'AUDIO_PLATFORM_ERR',
        userMessage: error.message ?? 'Audio playback device error.',
        cause: error,
        stackTrace: stackTrace,
      );
    }
    return GenericAppError(
      code: error.code,
      userMessage: error.message ?? 'Platform operation failed.',
      cause: error,
      stackTrace: stackTrace,
    );
  }

  if (error is FileSystemException) {
    return StorageError(
      code: 'FS_IO_ERROR',
      userMessage: 'File access failed on disk.',
      path: error.path,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  if (error is FormatException) {
    return GenericAppError(
      code: 'FORMAT_ERROR',
      userMessage: 'The data could not be read because it is malformed.',
      cause: error,
      stackTrace: stackTrace,
    );
  }

  final msg = error.toString();
  final lower = msg.toLowerCase();
  // Word-boundary match so unrelated words containing "bot" (robot, bottle,
  // both, sabotage) are not misreported as a YouTube bot challenge.
  if (RegExp(r'\bbots?\b').hasMatch(lower) ||
      lower.contains('sign in to confirm you’re not a bot')) {
    return YtmError(
      code: 'YTM_BOT_BLOCK',
      userMessage: 'YouTube Music bot check triggered. Please wait a moment.',
      isBotBlock: true,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  // SQLite can also surface raw engine errors (e.g. from a plugin or an
  // unwrapped platform channel) whose type we cannot import here without
  // pulling dart:ffi into every consumer. Match the engine's stable
  // `SqliteException(<code>)` prefix instead.
  if (lower.contains('sqliteexception')) {
    return StorageError(
      code: 'DB_ERROR',
      userMessage: 'A database error occurred. Please try again.',
      cause: error,
      stackTrace: stackTrace,
    );
  }

  if (lower.contains('timeout') || lower.contains('connection closed')) {
    return NetworkError(
      code: 'NET_TIMEOUT',
      userMessage: 'The request timed out. Please try again.',
      isTimeout: true,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  return GenericAppError(
    code: 'GENERIC_ERROR',
    userMessage: msg.isNotEmpty ? msg : 'An unexpected error occurred.',
    cause: error,
    stackTrace: stackTrace,
  );
}

/// Classifies an arbitrary thrown object into a canonical [AppError], then
/// narrows it to an [AppFailure] suitable for `Result`. A supplied domain
/// failure is returned unchanged so typed failures are never downgraded.
AppFailure classifyFailure(Object error, [StackTrace? stackTrace]) {
  final resolved = resolveAppError(error, stackTrace);
  if (resolved is AppFailure) return resolved;
  return GenericFailure(resolved.userMessage, resolved);
}
