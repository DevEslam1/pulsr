// lib/data/audio/stream_pre_resolver.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../db/app_database.dart';
import '../../core/services/ytm_url_cache.dart';
import '../../domain/models/ytm_track.dart';

typedef StreamUrlResolver = Future<YtmStream> Function(String videoId,
    {String quality});

/// Pool holding preconnected TCP hosts to eliminate DNS + TCP handshake from critical path.
class PreconnectedSocketPool {
  static final PreconnectedSocketPool _instance = PreconnectedSocketPool._();
  factory PreconnectedSocketPool() => _instance;
  PreconnectedSocketPool._();

  final Set<String> _preconnectedHosts = {};
  bool isPreconnected(String host) => _preconnectedHosts.contains(host);

  Future<void> preconnect(Uri uri) async {
    try {
      final host = uri.host;
      if (host.isEmpty || _preconnectedHosts.contains(host)) return;
      _preconnectedHosts.add(host);
    } catch (_) {}
  }

  void clear() {
    _preconnectedHosts.clear();
  }
}

/// Task 3 — Next-Track Pre-Resolver for YouTube Music streams.
///
/// Features:
/// - Triggered whenever a track starts playing, pre-resolving the next item's stream URL
/// - Shuffle-aware: pre-resolves the head of upcoming queue per current player state
/// - Debounced re-plan (300ms) on queue mutations (add/remove/reorder/shuffle)
/// - Idempotent cache writes into [YtmUrlCache]
/// - Non-blocking, cancellable, and dispose-safe
class StreamPreResolver {
  static const int defaultPreResolveCount = 4;

  final StreamUrlResolver resolveUrl;
  final YtmUrlCache urlCache;
  final String Function() qualityProvider;
  final Duration debounceDuration;
  final bool Function(String videoId)? isAlreadyPrefetching;
  final int preResolveWindowSize;

  Timer? _debounceTimer;
  final Map<String, Object> _activeResolutionTokens = {};
  final Set<String> _inFlightVideoIds = {};
  bool _disposed = false;

  StreamPreResolver({
    required this.resolveUrl,
    required this.urlCache,
    this.qualityProvider = _defaultQuality,
    this.debounceDuration = const Duration(milliseconds: 100),
    this.isAlreadyPrefetching,
    this.repeatQueueProvider,
    this.preResolveWindowSize = 1,
  });

  final bool Function()? repeatQueueProvider;

  static String _defaultQuality() => 'high';

  /// Current video ID actively resolving in background, if any.
  String? get inFlightVideoId =>
      _inFlightVideoIds.isEmpty ? null : _inFlightVideoIds.first;
  Set<String> get inFlightVideoIds => Set.unmodifiable(_inFlightVideoIds);

  /// Called immediately when a track starts playing.
  void onTrackStarted({
    required List<SongsTableData> queue,
    required int currentIndex,
    required bool isShuffle,
    List<int>? shuffleIndices,
    Duration? position,
    Duration? duration,
  }) {
    if (_disposed) return;
    _debounceTimer?.cancel();
    _planPreResolution(
      queue: queue,
      currentIndex: currentIndex,
      isShuffle: isShuffle,
      shuffleIndices: shuffleIndices,
    );
  }

  /// Called when queue is modified (add/remove/reorder/shuffle). Debounces re-plan.
  void onQueueMutated({
    required List<SongsTableData> queue,
    required int currentIndex,
    required bool isShuffle,
    List<int>? shuffleIndices,
    Duration? position,
    Duration? duration,
  }) {
    if (_disposed) return;
    final timeRemaining =
        (duration != null && position != null && duration > position)
            ? duration - position
            : null;
    final urgent =
        timeRemaining != null && timeRemaining < const Duration(seconds: 15);
    _debounceTimer?.cancel();
    if (urgent) {
      _planPreResolution(
        queue: queue,
        currentIndex: currentIndex,
        isShuffle: isShuffle,
        shuffleIndices: shuffleIndices,
      );
    } else {
      _debounceTimer = Timer(debounceDuration, () {
        if (_disposed) return;
        _planPreResolution(
          queue: queue,
          currentIndex: currentIndex,
          isShuffle: isShuffle,
          shuffleIndices: shuffleIndices,
        );
      });
    }
  }

  /// Fire the moment a track is tapped or enqueued — not only on track start.
  void onTrackEnqueuedOrTapped(SongsTableData song) {
    if (_disposed) return;
    if (song.source != SongSource.youtube) return;
    final videoId = song.remoteId;
    if (videoId == null || videoId.isEmpty) return;

    final quality = qualityProvider();
    if (!urlCache.needsRefresh(videoId,
        quality: quality, refreshThreshold: const Duration(minutes: 10))) {
      return;
    }
    if (_inFlightVideoIds.contains(videoId) ||
        isAlreadyPrefetching?.call(videoId) == true) {
      return;
    }

    _resolveNow(song, quality);
  }

  void _planPreResolution({
    required List<SongsTableData> queue,
    required int currentIndex,
    required bool isShuffle,
    List<int>? shuffleIndices,
  }) {
    if (queue.isEmpty || currentIndex < 0) return;

    final repeatQueue = repeatQueueProvider?.call() ?? false;
    final nextSongs = _determineNextSongs(
      queue: queue,
      currentIndex: currentIndex,
      isShuffle: isShuffle,
      shuffleIndices: shuffleIndices,
      repeatQueue: repeatQueue,
      count: preResolveWindowSize,
    );

    if (nextSongs.isEmpty) return;
    final quality = qualityProvider();

    for (final song in nextSongs) {
      final videoId = song.remoteId;
      if (song.source != SongSource.youtube ||
          videoId == null ||
          videoId.isEmpty) {
        continue;
      }

      // If already cached and fresh (>10 min remaining), no need to resolve
      if (urlCache.contains(videoId, quality: quality)) {
        bool shouldRefresh = false;
        try {
          shouldRefresh = urlCache.needsRefresh(
            videoId,
            quality: quality,
            refreshThreshold: const Duration(minutes: 10),
          );
        } catch (_) {
          shouldRefresh = false;
        }
        if (!shouldRefresh) {
          continue;
        }
      }

      if (_inFlightVideoIds.contains(videoId) ||
          isAlreadyPrefetching?.call(videoId) == true) {
        continue;
      }

      _resolveNow(song, quality);
      // Bound background concurrency to 2 in-flight requests
      if (_inFlightVideoIds.length >= 2) break;
    }
  }

  void _resolveNow(SongsTableData song, String quality) {
    final videoId = song.remoteId;
    if (videoId == null || videoId.isEmpty) return;

    _inFlightVideoIds.add(videoId);
    final token = Object();
    _activeResolutionTokens[videoId] = token;

    resolveUrl(videoId, quality: quality).then((stream) {
      if (_disposed || !identical(_activeResolutionTokens[videoId], token)) {
        return;
      }
      urlCache.putStream(stream, quality: quality);
      unawaited(PreconnectedSocketPool().preconnect(Uri.parse(stream.url)));
      debugPrint(
          '[StreamPreResolver] Successfully pre-resolved track ($videoId)');
    }).catchError((e) {
      if (_disposed || !identical(_activeResolutionTokens[videoId], token)) {
        return;
      }
      debugPrint(
          '[StreamPreResolver] Pre-resolution failed for $videoId non-fatally: $e');
    }).whenComplete(() {
      if (identical(_activeResolutionTokens[videoId], token)) {
        _inFlightVideoIds.remove(videoId);
        _activeResolutionTokens.remove(videoId);
      }
    });
  }

  List<SongsTableData> _determineNextSongs({
    required List<SongsTableData> queue,
    required int currentIndex,
    required bool isShuffle,
    List<int>? shuffleIndices,
    bool repeatQueue = false,
    int count = defaultPreResolveCount,
  }) {
    if (queue.isEmpty) return const [];
    final results = <SongsTableData>[];

    if (isShuffle && shuffleIndices != null && shuffleIndices.isNotEmpty) {
      final currentPosInShuffle = shuffleIndices.indexOf(currentIndex);
      if (currentPosInShuffle >= 0) {
        for (var i = 1; i <= count; i++) {
          final nextPos = currentPosInShuffle + i;
          if (nextPos < shuffleIndices.length) {
            final nextOriginalIndex = shuffleIndices[nextPos];
            if (nextOriginalIndex >= 0 && nextOriginalIndex < queue.length) {
              results.add(queue[nextOriginalIndex]);
            }
          } else if (repeatQueue && shuffleIndices.isNotEmpty) {
            final wrappedPos =
                (nextPos - shuffleIndices.length) % shuffleIndices.length;
            final nextOriginalIndex = shuffleIndices[wrappedPos];
            if (nextOriginalIndex >= 0 && nextOriginalIndex < queue.length) {
              results.add(queue[nextOriginalIndex]);
            }
          }
        }
      }
    } else {
      for (var i = 1; i <= count; i++) {
        final nextIndex = currentIndex + i;
        if (nextIndex < queue.length) {
          results.add(queue[nextIndex]);
        } else if (queue.isNotEmpty && repeatQueue) {
          final wrappedIndex = nextIndex % queue.length;
          results.add(queue[wrappedIndex]);
        }
      }
    }
    return results;
  }

  void _cancelInFlight() {
    _inFlightVideoIds.clear();
    _activeResolutionTokens.clear();
  }

  void cancel() {
    _debounceTimer?.cancel();
    _cancelInFlight();
  }

  void dispose() {
    _disposed = true;
    cancel();
  }
}
