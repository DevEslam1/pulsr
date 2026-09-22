// lib/core/errors/app_error.dart
// FIX-D1: Strongly-typed sealed error taxonomy for Pulsr
import 'dart:io';
import 'package:flutter/services.dart';

/// Sealed hierarchy of domain and system errors across Pulsr.
sealed class AppError implements Exception {
  final String code;
  final String userMessage;
  final Object? cause;
  final StackTrace? stackTrace;

  const AppError({
    required this.code,
    required this.userMessage,
    this.cause,
    this.stackTrace,
  });

  @override
  String toString() => '$runtimeType($code): $userMessage';
}

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

  if (error is SocketException || error is HttpException) {
    return NetworkError(
      code: 'NET_SOCKET_ERROR',
      userMessage: 'Network connection failed. Please check your connection.',
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
