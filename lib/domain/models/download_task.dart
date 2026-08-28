// lib/domain/models/download_task.dart

enum DownloadStatus {
  queued,
  downloading,
  embedding,
  paused,
  failed,
  complete;

  bool get isTerminal => this == DownloadStatus.complete || this == DownloadStatus.failed;
  bool get isActive => this == DownloadStatus.queued || this == DownloadStatus.downloading || this == DownloadStatus.embedding;
  bool get canPause => this == DownloadStatus.downloading || this == DownloadStatus.queued;
  bool get canResume => this == DownloadStatus.paused;
  bool get canRetry => this == DownloadStatus.failed;
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
  final String? filePath;
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
    this.filePath,
    this.tempFilePath,
    this.expectedChecksum,
    this.format,
    this.bitrate,
    this.error,
    required this.createdAt,
    this.artworkUrl,
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
    String? tempFilePath,
    String? expectedChecksum,
    String? format,
    int? bitrate,
    String? error,
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
      speedKbps: speedKbps ?? this.speedKbps,
      etaSeconds: etaSeconds ?? this.etaSeconds,
      filePath: filePath ?? this.filePath,
      tempFilePath: tempFilePath ?? this.tempFilePath,
      expectedChecksum: expectedChecksum ?? this.expectedChecksum,
      format: format ?? this.format,
      bitrate: bitrate ?? this.bitrate,
      error: error ?? this.error,
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
      'filePath': filePath,
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
