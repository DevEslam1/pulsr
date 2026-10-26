// lib/data/audio/collaborators/stream_resolution_pipeline.dart
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/core/telemetry/playback_latency_tracker.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/ytm_track.dart';

/// BUG-06: an in-flight resolve together with a completion marker, so a
/// superseded future whose identity no longer matches the map cannot be left
/// dangling (and can be pruned once complete).
class _InFlightResolve {
  _InFlightResolve(this.future);
  final Future<
          ({String url, String? userAgent, String? cookies, String quality})>
      future;
  bool done = false;
}

/// Pipeline resolving YouTube Music stream URLs, gating playback-time checks,
/// deduplicating in-flight resolves, and classifying errors. Resolved URLs are
/// cached by [YtmUrlCache] under [YtmService]; this class keeps no second copy.
class StreamResolutionPipeline {
  final YtmService ytmService;
  final PlaybackLatencyTracker? Function()? getLatencyTracker;
  final String Function()? qualityProvider;
  final void Function(SongsTableData song, int bitrateKbps, String codec)?
      onStreamResolved;

  /// Retained for call-site compatibility. Hedging now lives entirely in the
  /// native extractor, which races its top two clients and bounds each call;
  /// racing a second Dart-level chain here only doubled native load.
  bool hedgedEnabled;

  final Map<String, _InFlightResolve> _inFlightResolves = {};

  StreamResolutionPipeline({
    required this.ytmService,
    this.getLatencyTracker,
    this.hedgedEnabled = true,
    this.qualityProvider,
    this.onStreamResolved,
  });

  void invalidateCache(String videoId) {
    // Keys are `videoId:quality`; anchor the prefix to the separator so a
    // shorter id can never match a sibling key.
    _inFlightResolves.removeWhere((k, _) => k.startsWith('$videoId:'));
  }

  /// Drops in-flight resolves bound to the old network path.
  void clearNetworkCaches() {
    _inFlightResolves.clear();
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
        effectivePrefs.getBool('setting_offline_only_mode') ?? false;
    if (offlineOnly) {
      throw const YtmException(
          'OFFLINE_ONLY', 'Offline Only Mode is enabled in Settings');
    }
    final wifiOnly = effectivePrefs.getBool('setting_wifi_only_mode') ?? false;
    if (wifiOnly) {
      final isWifi = await ytmService.isWifiConnected();
      if (!isWifi) {
        throw const YtmException('WIFI_ONLY',
            'Wi-Fi Only Mode is enabled. Connect to Wi-Fi to stream');
      }
    }
    final effectiveQuality = quality ??
        qualityProvider?.call() ??
        effectivePrefs.getString('setting_streaming_quality') ??
        'high';
    final cacheKey = '$videoId:${effectiveQuality.toLowerCase()}';

    if (!forceRefresh) {
      final inFlight = _inFlightResolves[cacheKey];
      if (inFlight != null && !inFlight.done) {
        return await inFlight.future;
      }
      _inFlightResolves.remove(cacheKey);
      _pruneInFlight();
    }

    final future = () async {
      try {
        getLatencyTracker?.call()?.markStage(PlaybackStage.pluginEntered);
        getLatencyTracker?.call()?.markStage(PlaybackStage.clientRequestSent);
      } catch (_) {}

      Future<YtmStream> doResolve() => ytmService.resolveStream(videoId,
          quality: effectiveQuality,
          forceRefresh: forceRefresh,
          title: song.title,
          artist: song.artist);
      // The native extractor already hedges its top two clients and bounds each
      // call, so racing a second independent chain here only doubled native
      // load for no tail-latency gain. One chain; the extractor owns the hedge.
      final YtmStream stream = await doResolve();
      if (stream.url.trim().isEmpty) {
        throw const YtmException(
            'YTM_UNAVAILABLE', 'Resolved stream URL is empty');
      }

      final realBitrate = stream.bitrateKbps > 0
          ? stream.bitrateKbps
          : (effectiveQuality == 'low'
              ? 64
              : effectiveQuality == 'medium'
                  ? 128
                  : 160);
      final realCodec = stream.container.toUpperCase() == 'WEBM' ||
              stream.mimeType.contains('webm') ||
              stream.mimeType.contains('opus')
          ? 'OPUS'
          : (stream.container.toUpperCase() == 'M4A' ||
                  stream.mimeType.contains('mp4') ||
                  stream.mimeType.contains('aac')
              ? 'AAC'
              : 'OPUS');

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
    }();

    // Only register non-force resolves for dedup, and remove by identity. A
    // force-refresh must not overwrite an in-flight normal resolve's entry,
    // and a completing resolve must not evict a *different* future that
    // replaced it in the map (which left later callers un-deduped).
    _InFlightResolve? entry;
    if (!forceRefresh) {
      // Race close (BUG-06): another resolve may have registered while we were
      // awaiting the offline/wifi probes. Prefer theirs rather than overwriting
      // it, so neither future is orphaned in the map.
      final existing = _inFlightResolves[cacheKey];
      if (existing != null && !existing.done) {
        return await existing.future;
      }
      entry = _InFlightResolve(future);
      _inFlightResolves[cacheKey] = entry;
      final captured = entry;
      // Mark completion and drop the entry as soon as the future settles,
      // regardless of whether its identity still matches the map. `then` with
      // an onError handler keeps a failed resolve from surfacing as an
      // unhandled async error on this side channel.
      void settle() {
        captured.done = true;
        if (identical(_inFlightResolves[cacheKey], captured)) {
          _inFlightResolves.remove(cacheKey);
        }
      }

      unawaited(
          future.then<void>((_) => settle(), onError: (_, __) => settle()));
    }
    try {
      return await future;
    } finally {
      if (entry != null && identical(_inFlightResolves[cacheKey], entry)) {
        _inFlightResolves.remove(cacheKey);
      }
    }
  }

  /// BUG-06: drop completed in-flight entries whose identity was superseded
  /// before their own cleanup could run.
  void _pruneInFlight() {
    if (_inFlightResolves.isEmpty) return;
    _inFlightResolves.removeWhere((_, v) => v.done);
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
