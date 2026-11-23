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
  static int _nextRunId = 0;

  final int runId = ++_nextRunId;
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

class _TransferOutcome {
  final int? verifiedHttpBytes;
  final bool hasVerifiedHttpLength;

  const _TransferOutcome({
    this.verifiedHttpBytes,
    this.hasVerifiedHttpLength = false,
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
        !m.contains('missing') &&
        !m.contains('416') &&
        !m.contains('resume range');
  }
  return true;
}

// ── Artifact and tagging bodies ──────────────────────────────────────────────
// These live in the part file so the service facade keeps shrinking (01-4).
// The facade keeps public wrappers, so mock-based callers are unchanged.

Future<void> _sweepOrphanDownloadParts({
  required Set<String> busyVideoIds,
  Set<String>? activePartNames,
}) async {
  try {
    await YtDownloadArtifactStore.sweepOrphans(
      await getTemporaryDirectory(),
      busyVideoIds: busyVideoIds,
      activePartNames: activePartNames,
    );
  } catch (_) {
    // Best-effort: failure intentionally ignored on this non-critical path.
  }
}

Future<void> _deleteDownloadArtifacts(String videoId) async {
  try {
    await YtDownloadArtifactStore.deleteFor(
        await getTemporaryDirectory(), videoId);
  } catch (_) {
    // Best-effort: failure intentionally ignored on this non-critical path.
  }
}

Future<bool> _writeDownloadedSongTags(
  String path,
  SongsTableData song, {
  String? artworkPath,
  String? lyrics,
}) {
  return DownloadService.writeAudioTags(
    filePath: path,
    title: song.title,
    artist: song.artist,
    album: song.album.isNotEmpty ? song.album : 'Unknown Album',
    genre: song.genre,
    year: song.year,
    trackNumber: song.trackNumber ?? 1,
    artworkPath: artworkPath,
    lyrics: lyrics,
  );
}
