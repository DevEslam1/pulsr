// lib/data/audio/collaborators/stream_resolution_pipeline.dart
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/core/telemetry/playback_latency_tracker.dart';
import 'package:pulsr/data/audio/hedged_stream_resolver.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/models/ytm_track.dart';

class CachedStreamUrl {
  final String url;
  final String? userAgent;
  final String? cookies;
  final DateTime expires;
  CachedStreamUrl(this.url, this.expires, {this.userAgent, this.cookies});
}

/// Pipeline resolving YouTube Music stream URLs, integrating multi-layer caching,
/// in-flight deduplication, and error classification.
class StreamResolutionPipeline {
  final YtmService ytmService;
  final PlaybackLatencyTracker? Function()? getLatencyTracker;
  /// F3: when true, race two resolve attempts and take the first success.
  bool hedgedEnabled;

  final Map<String, CachedStreamUrl> _streamCache = {};
  final Map<String, Future<({String url, String? userAgent, String? cookies, String quality})>> _inFlightResolves = {};

  StreamResolutionPipeline({
    required this.ytmService,
    this.getLatencyTracker,
    this.hedgedEnabled = true,
  });

  Map<String, CachedStreamUrl> get streamCache => _streamCache;

  void invalidateCache(String videoId) {
    _streamCache.removeWhere((k, _) => k.startsWith(videoId));
  }

  Future<({String url, String? userAgent, String? cookies, String quality})> resolveStreamUrl(
    SongsTableData song, {
    bool forceRefresh = false,
    required SharedPreferences prefs,
  }) async {
    try {
      getLatencyTracker?.call()?.markStage(PlaybackStage.resolutionRequested);
    } catch (_) {}

    final videoId = song.remoteId;
    if (videoId == null || videoId.isEmpty) {
      throw const YtmException('YTM_UNAVAILABLE', 'Missing video id');
    }
    if (!RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(videoId) || videoId.startsWith('n_')) {
      throw const YtmException('YTM_UNAVAILABLE', 'Invalid video id');
    }

    final offlineOnly = prefs.getBool('setting_offline_only_mode') ?? false;
    if (offlineOnly) {
      throw const YtmException('OFFLINE_ONLY', 'Offline Only Mode is enabled in Settings');
    }
    final wifiOnly = prefs.getBool('setting_wifi_only_mode') ?? false;
    if (wifiOnly) {
      final isWifi = await ytmService.isWifiConnected();
      if (!isWifi) {
        throw const YtmException('WIFI_ONLY', 'Wi-Fi Only Mode is enabled. Connect to Wi-Fi to stream');
      }
    }
    final quality = prefs.getString('setting_streaming_quality') ?? 'high';
    final cacheKey = '$videoId:${quality.toLowerCase()}';

    if (!forceRefresh) {
      final cached = _streamCache[cacheKey];
      if (cached != null && cached.expires.isAfter(DateTime.now())) {
        try {
          getLatencyTracker?.call()?.markStage(PlaybackStage.urlObtained);
        } catch (_) {}
        return (
          url: cached.url,
          userAgent: cached.userAgent,
          cookies: cached.cookies,
          quality: quality,
        );
      }
      final inFlight = _inFlightResolves[cacheKey];
      if (inFlight != null) {
        return await inFlight;
      }
    }

    final future = () async {
      try {
        getLatencyTracker?.call()?.markStage(PlaybackStage.pluginEntered);
        getLatencyTracker?.call()?.markStage(PlaybackStage.clientRequestSent);
      } catch (_) {}

      Future<YtmStream> doResolve() =>
          ytmService.resolveStream(videoId, quality: quality, forceRefresh: forceRefresh);
      // F3: hedged resolution — staggered duplicate race.
      final YtmStream stream = hedgedEnabled
          ? await HedgedStreamResolver.raceDuplicate<YtmStream>(doResolve,
              hedgeDelay: const Duration(milliseconds: 300))
          : await doResolve();
      if (stream.url.trim().isEmpty) {
        throw const YtmException('YTM_UNAVAILABLE', 'Resolved stream URL is empty');
      }

      final expireParam = Uri.tryParse(stream.url)?.queryParameters['expire'];
      final expires = expireParam != null
          ? DateTime.fromMillisecondsSinceEpoch(int.parse(expireParam) * 1000)
          : DateTime.now().add(const Duration(hours: 5));

      _streamCache[cacheKey] = CachedStreamUrl(
        stream.url,
        expires,
        userAgent: stream.userAgent,
        cookies: stream.cookies,
      );

      try {
        getLatencyTracker?.call()?.markStage(PlaybackStage.urlObtained);
      } catch (_) {}

      return (
        url: stream.url,
        userAgent: stream.userAgent,
        cookies: stream.cookies,
        quality: quality,
      );
    }();

    _inFlightResolves[cacheKey] = future;
    try {
      return await future;
    } finally {
      _inFlightResolves.remove(cacheKey);
    }
  }

  Future<void> warmStreamCache(SongsTableData song, SharedPreferences prefs) async {
    final videoId = song.remoteId;
    if (videoId == null || videoId.isEmpty) return;
    try {
      await resolveStreamUrl(song, forceRefresh: false, prefs: prefs);
    } catch (_) {}
  }
}
