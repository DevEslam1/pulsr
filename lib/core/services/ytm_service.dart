// lib/core/services/ytm_service.dart
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';

import '../../domain/models/ytm_track.dart';
import '../utils/error_logger.dart';

/// A failed YTM call.
///
/// Unlike [LrclibService], which swallows failures because lyrics are optional,
/// these have to surface: the user typed a query and needs to see the difference
/// between "no results" and "offline", and the playback path has to stop
/// immediately on a network error instead of skipping through the queue.
class YtmException implements Exception {
  final String code;
  final String? details;

  const YtmException(this.code, [this.details]);

  /// Retrying later may work; retrying the rest of the queue now will not.
  bool get isNetwork => code == 'YTM_NETWORK' || code == 'YTM_TIMEOUT';

  /// This one video cannot be played, but others still can.
  bool get isUnavailable => code == 'YTM_UNAVAILABLE';

  /// The build has no extractor compiled in.
  bool get isDisabled => code == 'YTM_DISABLED' || code == 'YTM_UNSUPPORTED';

  @override
  String toString() => 'YtmException($code${details == null ? '' : ': $details'})';
}

@singleton
class YtmService {
  static const String channelName = 'com.pulsr.music/ytm';
  static const Duration _searchTimeout = Duration(seconds: 20);
  static const Duration _resolveTimeout = Duration(seconds: 25);

  final MethodChannel _channel = const MethodChannel(channelName);

  bool? _available;

  /// False in the Play Store build, where the native extractor is replaced by a
  /// stub. Cached because the answer is fixed at compile time.
  Future<bool> isAvailable() async {
    final cached = _available;
    if (cached != null) return cached;
    try {
      final value = await _guard(
        () => _channel.invokeMethod<bool>('isAvailable'),
        timeout: const Duration(seconds: 5),
      );
      return _available = value ?? false;
    } on YtmException {
      return _available = false;
    }
  }

  Future<bool> isWifiConnected() async {
    try {
      final value = await _guard(
        () => _channel.invokeMethod<bool>('isWifiConnected'),
        timeout: const Duration(seconds: 3),
      );
      return value ?? true;
    } on YtmException {
      return true;
    }
  }

  Future<List<YtmTrack>> search(String query, {int limit = 30}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final raw = await _guard(
      () => _channel.invokeMethod<List<Object?>>('search', {
        'query': trimmed,
        'limit': limit,
      }),
      timeout: _searchTimeout,
    );

    return _parseTracks(raw);
  }

  /// The YouTube "Trending" chart. Not query-driven and not music-filtered, so
  /// it can include non-music videos; used to seed the Home discovery section.
  Future<List<YtmTrack>> trending({int limit = 30}) async {
    final raw = await _guard(
      () => _channel.invokeMethod<List<Object?>>('trending', {'limit': limit}),
      timeout: _searchTimeout,
    );

    return _parseTracks(raw);
  }

  /// Fetches all tracks from a YouTube or YouTube Music playlist link or ID.
  Future<List<YtmTrack>> getPlaylistTracks(String urlOrId, {int limit = 100}) async {
    final raw = await _guard(
      () => _channel.invokeMethod<Map<Object?, Object?>>('getPlaylist', {
        'url': urlOrId.trim(),
        'limit': limit,
      }),
      timeout: const Duration(seconds: 40),
    );

    if (raw == null) return const [];
    final rawTracks = raw['tracks'] as List<Object?>?;
    return _parseTracks(rawTracks);
  }

  List<YtmTrack> _parseTracks(List<Object?>? raw) {
    if (raw == null) return const [];
    final tracks = <YtmTrack>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final track = YtmTrack.fromChannel(entry);
      if (track != null) tracks.add(track);
    }
    return tracks;
  }

  /// Resolves a currently-valid audio URL. The result expires, so callers must
  /// resolve at playback time and never store the URL.
  Future<YtmStream> resolveStream(String videoId, {String quality = 'high'}) async {
    final raw = await _guard(
      () => _channel.invokeMethod<Map<Object?, Object?>>('resolveStream', {
        'videoId': videoId,
        'quality': quality,
      }),
      timeout: _resolveTimeout,
    );

    final stream = raw == null ? null : YtmStream.fromChannel(raw);
    if (stream == null) {
      throw const YtmException('YTM_FAILED', 'No stream returned');
    }
    return stream;
  }

  Future<T?> _guard<T>(Future<T?> Function() call, {required Duration timeout}) async {
    try {
      return await call().timeout(timeout);
    } on TimeoutException {
      throw const YtmException('YTM_TIMEOUT');
    } on MissingPluginException {
      throw const YtmException('YTM_UNSUPPORTED');
    } on PlatformException catch (e) {
      ErrorLogger.log('YTM call failed: ${e.code} ${e.message}', category: 'YTM');
      throw YtmException(e.code, e.message);
    }
  }
}
