// lib/data/audio/collaborators/stream_resolution_pipeline.dart
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/core/telemetry/playback_latency_tracker.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/ytm_track.dart';

/// Pipeline resolving YouTube Music stream URLs, gating playback-time checks
/// and classifying errors. Resolved URLs are cached by [YtmUrlCache] under
/// [YtmService]; single-flight for identical resolves lives there too, so this
/// class keeps no state of its own.
class StreamResolutionPipeline {
  final YtmService ytmService;
  final PlaybackLatencyTracker? Function()? getLatencyTracker;
  final String Function()? qualityProvider;
  final void Function(SongsTableData song, int? bitrateKbps, String? codec)?
      onStreamResolved;

  StreamResolutionPipeline({
    required this.ytmService,
    this.getLatencyTracker,
    this.qualityProvider,
    this.onStreamResolved,
  });

  /// Drops any in-flight resolve for [videoId].
  ///
  /// The URL cache is left alone: the new quality has its own slot, and the
  /// resolver invalidates a burned URL itself. Clearing the cache here made an
  /// adaptive-quality step re-resolve a URL that was still valid.
  void invalidateCache(String videoId) {
    ytmService.forgetInFlightResolve(videoId);
  }

  Future<({String url, String? userAgent, String? cookies, String quality})>
      resolveStreamUrl(
    SongsTableData song, {
    bool forceRefresh = false,
    SharedPreferences? prefs,
    String? quality,
  }) async {
    try {
      getLatencyTracker?.call()?.markStage(PlaybackStage.resolutionRequested);
    } catch (_) {}

    final videoId = song.remoteId;
    if (videoId == null || videoId.isEmpty) {
      throw const YtmException('YTM_UNAVAILABLE', 'Missing video id');
    }
    if (!RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(videoId)) {
      throw const YtmException('YTM_UNAVAILABLE', 'Invalid video id');
    }

    final effectivePrefs = prefs ?? await SharedPreferences.getInstance();
    final offlineOnly =
        effectivePrefs.getBool(PrefsKeys.offlineOnlyMode) ?? false;
    if (offlineOnly) {
      throw const YtmException(
          'OFFLINE_ONLY', 'Offline Only Mode is enabled in Settings');
    }
    final wifiOnly = effectivePrefs.getBool(PrefsKeys.wifiOnlyMode) ?? false;
    if (wifiOnly) {
      final isWifi = await ytmService.isWifiConnected();
      if (!isWifi) {
        throw const YtmException('WIFI_ONLY',
            'Wi-Fi Only Mode is enabled. Connect to Wi-Fi to stream');
      }
    }
    final effectiveQuality = quality ??
        qualityProvider?.call() ??
        effectivePrefs.getString(PrefsKeys.streamingQuality) ??
        'high';
    // Single-flight for identical (videoId, quality) resolves belongs to
    // YtmService, where the in-flight map and the URL cache share one owner.
    // A second map here only made invalidation ambiguous: clearing one copy
    // left the other serving the URL that had just been declared dead (BUG-06).
    try {
      getLatencyTracker?.call()?.markStage(PlaybackStage.pluginEntered);
      getLatencyTracker?.call()?.markStage(PlaybackStage.clientRequestSent);
    } catch (_) {}

    // The native extractor already hedges its top two clients and bounds each
    // call, so racing a second independent chain here only doubled native
    // load for no tail-latency gain. One chain; the extractor owns the hedge.
    final YtmStream stream = await ytmService.resolveStream(
      videoId,
      quality: effectiveQuality,
      forceRefresh: forceRefresh,
      title: song.title,
      artist: song.artist,
      duration:
          song.durationMs > 0 ? Duration(milliseconds: song.durationMs) : null,
    );
    if (stream.url.trim().isEmpty) {
      throw const YtmException(
          'YTM_UNAVAILABLE', 'Resolved stream URL is empty');
    }

    // Unknown stays unknown. The old fallback stamped 64/128/160 kbps onto
    // the song row whenever the resolver reported no bitrate, so the library
    // asserted a technical property the stream had never claimed.
    final int? realBitrate = stream.bitrateKbps > 0 ? stream.bitrateKbps : null;
    final containerUpper = stream.container.toUpperCase();
    final mimeLower = stream.mimeType.toLowerCase();
    final String? realCodec = containerUpper == 'WEBM' ||
            mimeLower.contains('webm') ||
            mimeLower.contains('opus')
        ? 'OPUS'
        : (containerUpper == 'M4A' ||
                mimeLower.contains('mp4') ||
                mimeLower.contains('m4a') ||
                mimeLower.contains('aac')
            ? 'AAC'
            : null);

    onStreamResolved?.call(song, realBitrate, realCodec);

    try {
      getLatencyTracker?.call()?.markStage(PlaybackStage.urlObtained);
    } catch (_) {}

    return (
      url: stream.url,
      userAgent: stream.userAgent,
      cookies: stream.cookies,
      quality: effectiveQuality,
    );
  }

  Future<void> warmStreamCache(
      SongsTableData song, SharedPreferences prefs) async {
    final videoId = song.remoteId;
    if (videoId == null || videoId.isEmpty) return;
    try {
      await resolveStreamUrl(song, forceRefresh: false, prefs: prefs);
    } catch (_) {}
  }
}
