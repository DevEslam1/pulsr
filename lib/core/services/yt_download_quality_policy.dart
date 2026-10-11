// lib/core/services/yt_download_quality_policy.dart
import 'package:pulsr/domain/models/ytm_audio_quality.dart';

/// Per-download quality overrides requested from the search row's picker, and
/// the rule that turns them plus the persisted settings into the quality string
/// a transfer asks the resolver for.
class YtDownloadQualityPolicy {
  /// Bounded so an abandoned request cannot leak an entry for the process
  /// lifetime.
  static const int maxPendingOverrides = 32;

  final Map<String, YtmAudioQuality> _pendingOverrides = {};

  /// Records the quality the user picked for the next download of [videoId].
  void setPending(String videoId, YtmAudioQuality quality) {
    if (videoId.isEmpty) return;
    while (_pendingOverrides.length >= maxPendingOverrides &&
        !_pendingOverrides.containsKey(videoId)) {
      _pendingOverrides.remove(_pendingOverrides.keys.first);
    }
    _pendingOverrides[videoId] = quality;
  }

  /// Consumes the pending override for [videoId], if any.
  YtmAudioQuality? takePending(String videoId) =>
      _pendingOverrides.remove(videoId);

  /// Drops any pending override for [videoId] without returning it.
  void discardPending(String videoId) {
    _pendingOverrides.remove(videoId);
  }

  /// Quality a transfer should request. An explicit per-download [override]
  /// wins; otherwise the persisted download-quality default, then the
  /// streaming-quality fallback, then `high`. The download setting is checked
  /// first so the separate Download Quality row actually governs downloads.
  static String resolve({
    YtmAudioQuality? override,
    String? downloadQuality,
    String? streamingQuality,
  }) {
    final requested = override?.name;
    if (requested != null) return requested;
    for (final value in [downloadQuality, streamingQuality]) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return 'high';
  }
}
