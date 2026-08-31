// lib/domain/models/download_task.dart
// DL-10: Sealed statuses & TransitionGuard matrix to prevent illegal state jumps.

import 'package:fpdart/fpdart.dart';
import '../../core/errors/failures.dart';
import 'retry_policy.dart';

enum DownloadStatus {
  queued,
  downloading,
  embedding,
  paused,
  interrupted,
  failed,
  complete,
  canceled;

  bool get isTerminal =>
      this == DownloadStatus.complete ||
      this == DownloadStatus.failed ||
      this == DownloadStatus.canceled;
  bool get isActive =>
      this == DownloadStatus.queued ||
      this == DownloadStatus.downloading ||
      this == DownloadStatus.embedding;
  bool get canPause =>
      this == DownloadStatus.downloading || this == DownloadStatus.queued;
  bool get canResume =>
      this == DownloadStatus.paused || this == DownloadStatus.interrupted;
  bool get canRetry =>
      this == DownloadStatus.failed ||
      this == DownloadStatus.interrupted ||
      this == DownloadStatus.canceled;
  bool get canPrioritize =>
      this == DownloadStatus.queued ||
      this == DownloadStatus.paused ||
      this == DownloadStatus.interrupted;
  bool get canCancel => !isTerminal;

  static DownloadStatus? fromString(String? raw) {
    if (raw == null) return null;
    for (final s in DownloadStatus.values) {
      if (s.name == raw) return s;
    }
    return null;
  }
}


/// DL-10: State transition matrix guard ensuring only valid lifecycle state jumps are allowed.
class TransitionGuard {
  static const Map<DownloadStatus, Set<DownloadStatus>> _allowedTransitions = {
    DownloadStatus.queued: {
      DownloadStatus.downloading,
      DownloadStatus.paused,
      DownloadStatus.interrupted,
      DownloadStatus.failed,
      DownloadStatus.complete, // direct transition if already cached
      DownloadStatus.canceled,
    },
    DownloadStatus.downloading: {
      DownloadStatus.embedding,
      DownloadStatus.paused,
      DownloadStatus.interrupted,
      DownloadStatus.failed,
      DownloadStatus.complete,
      DownloadStatus.queued, // reorder / prioritize
      DownloadStatus.canceled,
    },
    DownloadStatus.embedding: {
      DownloadStatus.complete,
      DownloadStatus.failed,
      DownloadStatus.interrupted,
      DownloadStatus.canceled,
    },
    DownloadStatus.paused: {
      DownloadStatus.queued,
      DownloadStatus.downloading,
      DownloadStatus.failed,
      DownloadStatus.interrupted,
      DownloadStatus.canceled,
    },
    DownloadStatus.interrupted: {
      DownloadStatus.queued,
      DownloadStatus.downloading,
      DownloadStatus.paused,
      DownloadStatus.failed,
      DownloadStatus.canceled,
    },
    DownloadStatus.failed: {
      DownloadStatus.queued,
      DownloadStatus.downloading, // retry
      DownloadStatus.canceled,
    },
    DownloadStatus.complete: {
      DownloadStatus.queued, // re-download after manual file delete
    },
    DownloadStatus.canceled: {
      DownloadStatus.queued,
      DownloadStatus.downloading,
    },
  };

  static bool canTransition(DownloadStatus from, DownloadStatus to) {
    if (from == to) return true;
    return _allowedTransitions[from]?.contains(to) ?? false;
  }

  static Either<InvalidTransitionFailure, Unit> validate(DownloadStatus from, DownloadStatus to) {
    if (canTransition(from, to)) {
      return const Right(unit);
    }
    return Left(InvalidTransitionFailure(from.name, to.name));
  }
}

typedef DownloadTaskStatus = DownloadStatus;


class DownloadTask {
  final String id;
  final String videoId;
  final String title;
  final String artist;
  final DownloadStatus status;
  final double progress;
  final double? speedKbps;
  final int? etaSeconds;

  /// Total expected size in bytes, when the server reports it. Only
  /// meaningful while [status] is downloading.
  final int? totalBytes;
  final String? filePath;

  /// Positive library id of the reconciled row created when the download
  /// completed. Set by the repository in the same atomic completion commit
  /// so observers (e.g. the player swap after a search-initiated download)
  /// can follow the task into the local library without a second lookup.
  final int? librarySongId;
  final String? tempFilePath;
  final String? expectedChecksum;
  final String? format;
  final int? bitrate;
  final String? error;
  final DateTime createdAt;
  final String? artworkUrl;

  const DownloadTask({
    required this.id,
    required this.videoId,
    required this.title,
    required this.artist,
    this.status = DownloadStatus.queued,
    this.progress = 0.0,
    this.speedKbps,
    this.etaSeconds,
    this.totalBytes,
    this.filePath,
    this.librarySongId,
    this.tempFilePath,
    this.expectedChecksum,
    this.format,
    this.bitrate,
    this.error,
    required this.createdAt,
    this.artworkUrl,
  });

  /// Transient (retryable) failure classification for [status] == failed.
  /// Storage/permission/feature-disabled errors are permanent; network,
  /// timeout and interrupted errors are transient and may be auto-retried.
  bool get isTransientFailure {
    if (status != DownloadStatus.failed && status != DownloadStatus.interrupted) {
      return false;
    }
    final message = error ?? '';
    final permanent = message.toLowerCase().contains('insufficient storage') ||
        message.toLowerCase().contains('storage full') ||
        message.toLowerCase().contains('unavailable in this build') ||
        message.toLowerCase().contains('bot blocked') ||
        message.toLowerCase().contains('offline only');
    if (permanent) return false;
    return RetryPolicy.isRetryableError(message);
  }

  /// Complement of [isTransientFailure] for terminal failed states.
  bool get isPermanentFailure =>
      status == DownloadStatus.failed && !isTransientFailure;

  DownloadTask copyWith({
    String? id,
    String? videoId,
    String? title,
    String? artist,
    DownloadStatus? status,
    double? progress,
    double? speedKbps,
    bool clearSpeedKbps = false,
    int? etaSeconds,
    bool clearEtaSeconds = false,
    int? totalBytes,
    bool clearTotalBytes = false,
    String? filePath,
    int? librarySongId,
    String? tempFilePath,
    String? expectedChecksum,
    String? format,
    int? bitrate,
    String? error,
    bool clearError = false,
    DateTime? createdAt,
    String? artworkUrl,
  }) {
    return DownloadTask(
      id: id ?? this.id,
      videoId: videoId ?? this.videoId,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      speedKbps: clearSpeedKbps ? null : (speedKbps ?? this.speedKbps),
      etaSeconds: clearEtaSeconds ? null : (etaSeconds ?? this.etaSeconds),
      totalBytes: clearTotalBytes ? null : (totalBytes ?? this.totalBytes),
      filePath: filePath ?? this.filePath,
      librarySongId: librarySongId ?? this.librarySongId,
      tempFilePath: tempFilePath ?? this.tempFilePath,
      expectedChecksum: expectedChecksum ?? this.expectedChecksum,
      format: format ?? this.format,
      bitrate: bitrate ?? this.bitrate,
      error: clearError ? null : (error ?? this.error),
      createdAt: createdAt ?? this.createdAt,
      artworkUrl: artworkUrl ?? this.artworkUrl,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'videoId': videoId,
      'title': title,
      'artist': artist,
      'status': status.name,
      'progress': progress,
      'speedKbps': speedKbps,
      'etaSeconds': etaSeconds,
      'totalBytes': totalBytes,
      'filePath': filePath,
      'librarySongId': librarySongId,
      'tempFilePath': tempFilePath,
      'expectedChecksum': expectedChecksum,
      'format': format,
      'bitrate': bitrate,
      'error': error,
      'createdAt': createdAt.toIso8601String(),
      'artworkUrl': artworkUrl,
    };
  }

  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    final statusStr = json['status'] as String?;
    final parsedStatus = DownloadStatus.fromString(statusStr);
    if (parsedStatus == null) {
      throw FormatException('Invalid or missing DownloadStatus: $statusStr');
    }

    return DownloadTask(
      id: json['id'] as String? ?? json['videoId'] as String? ?? '',
      videoId: json['videoId'] as String? ?? '',
      title: json['title'] as String? ?? 'Unknown Title',
      artist: json['artist'] as String? ?? 'Unknown Artist',
      status: parsedStatus,
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      speedKbps: (json['speedKbps'] as num?)?.toDouble(),
      etaSeconds: json['etaSeconds'] as int?,
      totalBytes: json['totalBytes'] as int?,
      filePath: json['filePath'] as String?,
      librarySongId: json['librarySongId'] as int?,
      tempFilePath: json['tempFilePath'] as String?,
      expectedChecksum: json['expectedChecksum'] as String?,
      format: json['format'] as String?,
      bitrate: json['bitrate'] as int?,
      error: json['error'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      artworkUrl: json['artworkUrl'] as String?,
    );
  }


  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DownloadTask &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          videoId == other.videoId &&
          status == other.status &&
          progress == other.progress &&
          filePath == other.filePath &&
          error == other.error;

  @override
  int get hashCode => Object.hash(id, videoId, status, progress, filePath, error);
}

class StorageStats {
  final int usedBytes;
  final int freeBytes;
  final int totalBytes;
  final int downloadedSongsCount;

  const StorageStats({
    this.usedBytes = 0,
    this.freeBytes = 0,
    this.totalBytes = 0,
    this.downloadedSongsCount = 0,
  });

  double get usedPercentage {
    if (totalBytes <= 0) return 0.0;
    return (usedBytes / totalBytes).clamp(0.0, 1.0);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StorageStats &&
          runtimeType == other.runtimeType &&
          usedBytes == other.usedBytes &&
          freeBytes == other.freeBytes &&
          totalBytes == other.totalBytes &&
          downloadedSongsCount == other.downloadedSongsCount;

  @override
  int get hashCode => Object.hash(usedBytes, freeBytes, totalBytes, downloadedSongsCount);
}
