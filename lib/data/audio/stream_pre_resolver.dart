// lib/data/audio/stream_pre_resolver.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../db/app_database.dart';
import '../../core/services/ytm_url_cache.dart';
import '../../domain/models/ytm_track.dart';

typedef StreamUrlResolver = Future<YtmStream> Function(String videoId,
    {String quality});

/// Task 3 — Next-Track Pre-Resolver for YouTube Music streams.
///
/// Features:
/// - Triggered whenever a track starts playing, pre-resolving the next item's stream URL
/// - Shuffle-aware: pre-resolves the head of upcoming queue per current player state
/// - Debounced re-plan (300ms) on queue mutations (add/remove/reorder/shuffle)
/// - Idempotent cache writes into [YtmUrlCache]
/// - Non-blocking, cancellable, and dispose-safe
class StreamPreResolver {
  final StreamUrlResolver resolveUrl;
  final YtmUrlCache urlCache;
  final String Function() qualityProvider;
  final Duration debounceDuration;
  final bool Function(String videoId)? isAlreadyPrefetching;

  Timer? _debounceTimer;
  Completer<void>? _activeResolution;
  String? _inFlightVideoId;
  bool _disposed = false;

  StreamPreResolver({
    required this.resolveUrl,
    required this.urlCache,
    this.qualityProvider = _defaultQuality,
    this.debounceDuration = const Duration(milliseconds: 100),
    this.isAlreadyPrefetching,
    this.repeatQueueProvider,
  });

  final bool Function()? repeatQueueProvider;

  static String _defaultQuality() => 'high';

  /// Current video ID actively resolving in background, if any.
  String? get inFlightVideoId => _inFlightVideoId;

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
    final timeRemaining = (duration != null && position != null && duration > position)
        ? duration - position
        : null;
    final urgent = timeRemaining != null && timeRemaining < const Duration(seconds: 15);
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
    if (urlCache.contains(videoId, quality: quality)) return;
    if (_inFlightVideoId == videoId ||
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
    final nextSong = _determineNextSong(
      queue: queue,
      currentIndex: currentIndex,
      isShuffle: isShuffle,
      shuffleIndices: shuffleIndices,
      repeatQueue: repeatQueue,
    );

    if (nextSong == null) return;

    // Only YouTube tracks require network URL pre-resolution
    final videoId = nextSong.remoteId;
    if (nextSong.source != SongSource.youtube ||
        videoId == null ||
        videoId.isEmpty) {
      return;
    }

    final quality = qualityProvider();

    // Idempotent: skip if already valid in URL cache
    if (urlCache.contains(videoId, quality: quality)) {
      return;
    }

    // Skip if already in flight for the same video
    if (_inFlightVideoId == videoId ||
        isAlreadyPrefetching?.call(videoId) == true) {
      return;
    }

    _resolveNow(nextSong, quality);
  }

  void _resolveNow(SongsTableData song, String quality) {
    final videoId = song.remoteId;
    if (videoId == null || videoId.isEmpty) return;

    _cancelInFlight();
    _inFlightVideoId = videoId;

    final completer = Completer<void>();
    _activeResolution = completer;

    resolveUrl(videoId, quality: quality).then((stream) {
      if (_disposed || !identical(_activeResolution, completer)) return;
      urlCache.putStream(stream, quality: quality);
      debugPrint(
          '[StreamPreResolver] Successfully pre-resolved track ($videoId)');
    }).catchError((e) {
      if (_disposed || !identical(_activeResolution, completer)) return;
      debugPrint(
          '[StreamPreResolver] Pre-resolution failed for $videoId non-fatally: $e');
    }).whenComplete(() {
      if (identical(_activeResolution, completer)) {
        _inFlightVideoId = null;
        _activeResolution = null;
      }
    });
  }

  SongsTableData? _determineNextSong({
    required List<SongsTableData> queue,
    required int currentIndex,
    required bool isShuffle,
    List<int>? shuffleIndices,
    bool repeatQueue = false,
  }) {
    if (queue.isEmpty) return null;

    if (isShuffle && shuffleIndices != null && shuffleIndices.isNotEmpty) {
      final currentPosInShuffle = shuffleIndices.indexOf(currentIndex);
      if (currentPosInShuffle >= 0 &&
          currentPosInShuffle + 1 < shuffleIndices.length) {
        final nextOriginalIndex = shuffleIndices[currentPosInShuffle + 1];
        if (nextOriginalIndex >= 0 && nextOriginalIndex < queue.length) {
          return queue[nextOriginalIndex];
        }
      } else if (repeatQueue && shuffleIndices.isNotEmpty) {
        final firstOriginalIndex = shuffleIndices.first;
        if (firstOriginalIndex >= 0 && firstOriginalIndex < queue.length) {
          return queue[firstOriginalIndex];
        }
      }
    }

    // Normal linear queue order
    final nextIndex = currentIndex + 1;
    if (nextIndex < queue.length) {
      return queue[nextIndex];
    } else if (queue.length > 1 && repeatQueue) {
      // Loop around to head only if repeat queue is enabled
      return queue.first;
    }
    return null;
  }

  void _cancelInFlight() {
    _inFlightVideoId = null;
    _activeResolution = null;
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
