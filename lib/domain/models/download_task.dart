// lib/domain/models/download_task.dart

import 'ytm_audio_quality.dart';

enum DownloadStatus {
  queued,
  downloading,

  /// The bytes are on disk and the service is embedding artwork/tags, saving to
  /// MediaStore, and indexing the row. Distinct from [downloading] so the UI can
  /// say "Embedding tags" instead of showing a finished-looking 100% bar.
  tagging,
  paused,
  failed,
  complete;

  bool get isTerminal =>
      this == DownloadStatus.complete || this == DownloadStatus.failed;
  bool get isActive =>
      this == DownloadStatus.queued ||
      this == DownloadStatus.downloading ||
      this == DownloadStatus.tagging;
  bool get canPause =>
      this == DownloadStatus.downloading ||
      this == DownloadStatus.queued ||
      this == DownloadStatus.tagging;
  bool get canResume => this == DownloadStatus.paused;
  bool get canRetry => this == DownloadStatus.failed;
}

/// How a [DownloadTask] was handled by the repository's admission path.
///
/// `Right(...)` alone cannot distinguish "new download admitted" from "this
/// track was already queued/downloading" or "it is already complete on disk",
/// so batch reporting used to count those as newly queued.
enum DownloadAdmission { queued, alreadyActive, alreadyComplete }

class QueueDownloadResult {
  const QueueDownloadResult({
    required this.taskId,
    required this.admission,
  });

  final String taskId;
  final DownloadAdmission admission;

  bool get wasQueued => admission == DownloadAdmission.queued;
}

class DownloadTask {
  final String id;
  final String videoId;
  final String title;
  final String artist;
  final DownloadStatus status;
  final double progress;
  final double? speedKbps;
  final int? etaSeconds;
  final String? filePath;
  final String? format;
  final int? bitrate;
  final String? error;
  final DateTime createdAt;
  final String? artworkUrl;

  /// Library row id of the remote (`youtube`-sourced) track this download was
  /// launched for. Carried so the reconcile on completion can swap the stale
  /// negative-id queue entry for the positive local row.
  final int? sourceSongId;

  /// Positive library row id once the download has been reconciled into a local
  /// track. Null until [status] reaches [DownloadStatus.complete].
  final int? localSongId;

  /// Byte size of the downloaded audio file once complete.
  final int? fileSize;

  /// MediaStore content URI returned when the file was saved. Used to delete
  /// the provider row directly instead of resolving it by path.
  final String? contentUri;

  /// Album and duration captured at admission. Persisted so a download that
  /// resumes after a restart still tags with the real album and fetches lyrics
  /// with the right duration instead of falling back to "Unknown Album" / 0:00.
  final String? album;
  final int? durationMs;

  /// Quality this task was admitted with (`low`/`medium`/`high`), persisted so
  /// a pause/restart/retry keeps the user's picker choice instead of silently
  /// reverting to the global default.
  final YtmAudioQuality? quality;

  const DownloadTask({
    required this.id,
    required this.videoId,
    required this.title,
    required this.artist,
    this.status = DownloadStatus.queued,
    this.progress = 0.0,
    this.speedKbps,
    this.etaSeconds,
    this.filePath,
    this.format,
    this.bitrate,
    this.error,
    required this.createdAt,
    this.artworkUrl,
    this.sourceSongId,
    this.localSongId,
    this.fileSize,
    this.contentUri,
    this.album,
    this.durationMs,
    this.quality,
  });

  DownloadTask copyWith({
    String? id,
    String? videoId,
    String? title,
    String? artist,
    DownloadStatus? status,
    double? progress,
    double? speedKbps,
    int? etaSeconds,
    String? filePath,
    String? format,
    int? bitrate,
    String? error,
    DateTime? createdAt,
    String? artworkUrl,
    int? sourceSongId,
    int? localSongId,
    int? fileSize,
    String? contentUri,
    String? album,
    int? durationMs,
    YtmAudioQuality? quality,
    bool clearError = false, // FIX-A09: support clearing error via copyWith
    bool clearSpeedKbps = false,
    bool clearEtaSeconds = false,
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
      filePath: filePath ?? this.filePath,
      format: format ?? this.format,
      bitrate: bitrate ?? this.bitrate,
      error: clearError
          ? null
          : (error ?? this.error), // FIX-A09: clear error if requested
      createdAt: createdAt ?? this.createdAt,
      artworkUrl: artworkUrl ?? this.artworkUrl,
      sourceSongId: sourceSongId ?? this.sourceSongId,
      localSongId: localSongId ?? this.localSongId,
      fileSize: fileSize ?? this.fileSize,
      contentUri: contentUri ?? this.contentUri,
      album: album ?? this.album,
      durationMs: durationMs ?? this.durationMs,
      quality: quality ?? this.quality,
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
      'filePath': filePath,
      'format': format,
      'bitrate': bitrate,
      'error': error,
      'createdAt': createdAt.toIso8601String(),
      'artworkUrl': artworkUrl,
      'sourceSongId': sourceSongId,
      'localSongId': localSongId,
      'fileSize': fileSize,
      'contentUri': contentUri,
      'album': album,
      'durationMs': durationMs,
      'quality': quality?.name,
    };
  }

  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    return DownloadTask(
      id: json['id'] as String? ?? json['videoId'] as String? ?? '',
      videoId: json['videoId'] as String? ?? '',
      title: json['title'] as String? ?? 'Unknown Title',
      artist: json['artist'] as String? ?? 'Unknown Artist',
      status: DownloadStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => DownloadStatus.failed,
      ),
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      speedKbps: (json['speedKbps'] as num?)?.toDouble(),
      etaSeconds: json['etaSeconds'] as int?,
      filePath: json['filePath'] as String?,
      format: json['format'] as String?,
      bitrate: json['bitrate'] as int?,
      error: json['error'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      artworkUrl: json['artworkUrl'] as String?,
      sourceSongId: (json['sourceSongId'] as num?)?.toInt(),
      localSongId: (json['localSongId'] as num?)?.toInt(),
      fileSize: (json['fileSize'] as num?)?.toInt(),
      contentUri: json['contentUri'] as String?,
      album: json['album'] as String?,
      durationMs: (json['durationMs'] as num?)?.toInt(),
      quality: _qualityFromName(json['quality']),
    );
  }

  static YtmAudioQuality? _qualityFromName(Object? raw) {
    if (raw is! String) return null;
    for (final quality in YtmAudioQuality.values) {
      if (quality.name == raw) return quality;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DownloadTask &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          videoId == other.videoId &&
          title == other.title &&
          artist == other.artist &&
          status == other.status &&
          progress == other.progress &&
          filePath == other.filePath &&
          format == other.format &&
          bitrate == other.bitrate &&
          error == other.error &&
          sourceSongId == other.sourceSongId &&
          localSongId == other.localSongId &&
          fileSize == other.fileSize &&
          contentUri == other.contentUri &&
          album == other.album &&
          durationMs == other.durationMs &&
          quality == other.quality;

  @override
  int get hashCode => Object.hashAll([
        id,
        videoId,
        title,
        artist,
        status,
        progress,
        filePath,
        format,
        bitrate,
        error,
        sourceSongId,
        localSongId,
        fileSize,
        contentUri,
        album,
        durationMs,
        quality,
      ]);
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
  int get hashCode =>
      Object.hash(usedBytes, freeBytes, totalBytes, downloadedSongsCount);
}
