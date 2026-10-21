// lib/core/services/yt_download_transfer_math.dart
import 'package:pulsr/domain/models/ytm_track.dart';

/// Pure transfer arithmetic for a download: the body size a [YtmStream]
/// implies, the disk and URL lifetime that body needs, and the resume stamps
/// that keep partial bytes tied to the URL that wrote them.
class YtDownloadTransferMath {
  /// No connection sustains less than this for long; used to turn a byte count
  /// into a pessimistic transfer time so a URL that cannot outlive the download
  /// is replaced before the first byte rather than mid-transfer.
  static const int pessimisticBytesPerSecond = 48 * 1024; // ~384 kbps

  /// Gap between two received chunks after which the transfer is treated as
  /// dead. Without it a silently half-open socket held a download — and one of
  /// the three concurrency slots — until the OS eventually gave up, which on
  /// mobile can be many minutes.
  static const Duration stallTimeout = Duration(seconds: 45);

  /// Bytes [stream] is expected to occupy on disk, from its own metadata.
  static int estimateBytes(YtmStream stream) {
    final bitrate = stream.bitrateKbps > 0 ? stream.bitrateKbps : 160;
    final seconds =
        stream.duration.inSeconds > 0 ? stream.duration.inSeconds : 240;
    return seconds * bitrate * 1000 ~/ 8;
  }

  /// Disk space a download insists on before starting for [stream], including
  /// the scratch the parallel path needs (F3).
  ///
  /// The true peak is two copies of the body: all four `.partN` chunks exist
  /// while `.part` is being merged, which is the same 2x bar that the parallel
  /// path checks against. The old `chunks + 1` (= 5x) pre-flight refused
  /// downloads that would have completed — a 40-minute 256kbps track asked for
  /// ~394MB free when ~154MB is enough.
  static int requiredPreflightBytes(YtmStream stream) =>
      estimateBytes(stream) * 2 + (10 * 1024 * 1024);

  /// Stamp value written beside a partial so a resume can tell whether those
  /// bytes belong to the body it is about to request (F6).
  ///
  /// Identity is the video id, container, and expected body size, not the URL.
  /// YouTube re-mints googlevideo URLs for the same body (403 recovery, URL
  /// expiry), and a URL-derived stamp discarded every resumed byte in exactly
  /// the case resume exists for. A different quality or format changes the
  /// container and/or size; a different video shares neither the scratch path
  /// nor the video-id segment, so genuinely different bytes are always refused.
  static String resumeStampFor({
    required String container,
    int? expectedBytes,
    String? videoId,
  }) {
    final size = expectedBytes != null && expectedBytes > 0
        ? expectedBytes.toString()
        : 'unknown';
    final id = videoId?.trim() ?? '';
    return 'v2|$id|${container.trim().toLowerCase()}|$size';
  }

  /// Whether a `.part` carrying [stampContents] may be resumed against
  /// [urlStamp]. Anything else — a different URL, a missing stamp, or a stamp
  /// written by a build that did not write one — means the bytes on disk are
  /// not known to line up with the body about to be requested.
  static bool resumeStampMatches(String? stampContents, String urlStamp) =>
      stampContents != null && stampContents.trim() == urlStamp;

  /// How much life a URL needs left for this download to finish on it.
  ///
  /// A download is not a seek: it has to survive from the first byte to the
  /// last, so [YtmStream.isExpiringSoon]'s 5-minute playback default is the
  /// wrong bar — a 40-minute mix on a slow link outlives it and dies at 403
  /// with the bytes already on disk.
  static Duration requiredLifetime(YtmStream stream) {
    final seconds = (estimateBytes(stream) / pessimisticBytesPerSecond).ceil();
    return Duration(seconds: seconds.clamp(60, 1800)) +
        const Duration(minutes: 2);
  }
}
