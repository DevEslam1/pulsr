// Download queue value types and the failure-classification predicate, extracted
// so yt_download_service.dart keeps shrinking (ratchet 01-4). Part of that
// library, so the private types stay visible to the service and its call sites
// are unchanged.
part of 'yt_download_service.dart';

/// Where a download currently is, for driving progress UI.
enum YtDownloadStage {
  queued,
  resolving,
  downloading,
  tagging,
  saving,
  indexing,
  done,
  canceled
}

class YtDownloadProgress {
  final YtDownloadStage stage;

  /// 0..1 during [YtDownloadStage.downloading], null when indeterminate.
  final double? fraction;
  final double? speedKbps;
  final int? etaSeconds;

  const YtDownloadProgress(this.stage,
      [this.fraction, this.speedKbps, this.etaSeconds]);
}

class _QueuedDownload {
  final SongsTableData song;
  final void Function(YtDownloadProgress)? onProgress;
  final Completer<Result<int>> completer;

  /// Per-download quality requested by the caller (the long-press picker), or
  /// null to fall back to the persisted download-quality default.
  final YtmAudioQuality? quality;
  bool isCanceled = false;

  _QueuedDownload({
    required this.song,
    required this.onProgress,
    required this.completer,
    this.quality,
  });
}

/// Raised when a server answers a ranged chunk request with `200 OK`, i.e. it
/// is sending the whole body and the four-way split cannot be honoured. Private
/// and never surfaced to callers: the parallel path catches it and retries the
/// transfer as a single request.
class _RangeIgnored implements Exception {
  const _RangeIgnored();

  @override
  String toString() => 'Server ignored the Range header';
}

bool _partsWorthKeeping(Object e) {
  // Range-ignored means the `.partN` files hold whole-body duplicates, not
  // the ranged chunks; nothing in them can be resumed or merged.
  if (e is _RangeIgnored) return false;
  if (e is StorageFailure) return false;
  if (e is DownloadFailure) {
    final m = e.message.toLowerCase();
    return !m.contains('mismatch') &&
        !m.contains('incomplete') &&
        !m.contains('missing');
  }
  return true;
}
