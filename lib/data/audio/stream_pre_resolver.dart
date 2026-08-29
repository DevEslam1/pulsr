// lib/data/audio/stream_pre_resolver.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../db/app_database.dart';
import '../../core/services/ytm_url_cache.dart';
import '../../domain/models/ytm_track.dart';

typedef StreamUrlResolver = Future<YtmStream> Function(String videoId, {String quality});

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
  final Duration debounceDuration;

  Timer? _debounceTimer;
  Completer<void>? _activeResolution;
  String? _inFlightVideoId;
  bool _disposed = false;

  StreamPreResolver({
    required this.resolveUrl,
    required this.urlCache,
    this.debounceDuration = const Duration(milliseconds: 300),
  });

  /// Current video ID actively resolving in background, if any.
  String? get inFlightVideoId => _inFlightVideoId;

  /// Called on startup, track change, connectivity change, and app resume.
  /// Pre-resolves current item (if needed/stale) and next item without resolving whole queue.
  void preResolveCurrentAndNext({
    required List<SongsTableData> queue,
    required int currentIndex,
    required bool isShuffle,
    List<int>? shuffleIndices,
  }) {
    if (_disposed || queue.isEmpty) return;

    if (currentIndex >= 0 && currentIndex < queue.length) {
      final currentSong = queue[currentIndex];
      final curVid = currentSong.remoteId;
      if (curVid != null && curVid.isNotEmpty) {
        final cached = urlCache.get(curVid);
        if (cached == null || cached.isStaleWhileRevalidate()) {
          resolveUrl(curVid).then((stream) {
            if (!_disposed) urlCache.putStream(stream);
          }).catchError((_) {});
        }
      }
    }

    _planPreResolution(
      queue: queue,
      currentIndex: currentIndex,
      isShuffle: isShuffle,
      shuffleIndices: shuffleIndices,
    );
  }

  /// Called immediately when a track starts playing.
  void onTrackStarted({
    required List<SongsTableData> queue,
    required int currentIndex,
    required bool isShuffle,
    List<int>? shuffleIndices,
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
  }) {
    if (_disposed) return;
    _debounceTimer?.cancel();
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

  void _planPreResolution({
    required List<SongsTableData> queue,
    required int currentIndex,
    required bool isShuffle,
    List<int>? shuffleIndices,
  }) {
    if (queue.isEmpty || currentIndex < 0) return;

    final nextSong = _determineNextSong(
      queue: queue,
      currentIndex: currentIndex,
      isShuffle: isShuffle,
      shuffleIndices: shuffleIndices,
    );

    if (nextSong == null) return;

    // Only YouTube tracks require network URL pre-resolution
    final videoId = nextSong.remoteId;
    if (videoId == null || videoId.isEmpty) return;

    // Idempotent: skip if already valid in URL cache
    if (urlCache.contains(videoId)) {
      return;
    }

    // Skip if already in flight for the same video
    if (_inFlightVideoId == videoId) {
      return;
    }

    _cancelInFlight();
    _inFlightVideoId = videoId;

    final completer = Completer<void>();
    _activeResolution = completer;

    resolveUrl(videoId).then((stream) {
      if (_disposed || !identical(_activeResolution, completer)) return;
      urlCache.putStream(stream);
      debugPrint('[StreamPreResolver] Successfully pre-resolved next track ($videoId)');
    }).catchError((Object e) {
      if (_disposed || !identical(_activeResolution, completer)) return;
      debugPrint('[StreamPreResolver] Pre-resolution failed for $videoId non-fatally: $e');
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
  }) {
    if (queue.isEmpty) return null;

    if (isShuffle && shuffleIndices != null && shuffleIndices.isNotEmpty) {
      final currentPosInShuffle = shuffleIndices.indexOf(currentIndex);
      if (currentPosInShuffle >= 0 && currentPosInShuffle + 1 < shuffleIndices.length) {
        final nextOriginalIndex = shuffleIndices[currentPosInShuffle + 1];
        if (nextOriginalIndex >= 0 && nextOriginalIndex < queue.length) {
          return queue[nextOriginalIndex];
        }
      }
    }

    // Normal linear queue order
    final nextIndex = currentIndex + 1;
    if (nextIndex < queue.length) {
      return queue[nextIndex];
    } else if (queue.length > 1) {
      // Loop around to head if repeat queue or wrap
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
