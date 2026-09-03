// lib/data/audio/stream_pre_resolver.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../db/app_database.dart';
import '../../data/services/ytm_url_cache.dart';
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
/// - 2-track lookahead on WiFi (pre-resolves N+1 and N+2 to eliminate skip latency)
class StreamPreResolver {
  final StreamUrlResolver resolveUrl;
  final YtmUrlCache urlCache;
  final Duration debounceDuration;

  /// Optional callback returning whether the device is currently on WiFi.
  /// When null or returning false, only 1 track is pre-resolved.
  final Future<bool> Function()? isWifi;

  Timer? _debounceTimer;
  Completer<void>? _activeResolution;
  String? _inFlightVideoId;
  bool _disposed = false;
  // Cooldown after a block signal (429/bot/403): prefetch must not hammer
  // the ladder while interactive playback is cooling down.
  DateTime? _coolingUntil;

  bool get _isCooling =>
      _coolingUntil != null && DateTime.now().isBefore(_coolingUntil!);

  void _noteBlockSignal(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('429') ||
        s.contains('rate_limit') ||
        s.contains('bot') ||
        s.contains('recaptcha') ||
        s.contains('403') ||
        s.contains('forbidden') ||
        s.contains('sign in to confirm')) {
      _coolingUntil = DateTime.now().add(const Duration(seconds: 60));
    }
  }

  Future<void> _resolveBestEffort(String videoId) async {
    if (_disposed || _isCooling) return;
    try {
      final stream = await resolveUrl(videoId).timeout(
        const Duration(seconds: 15),
      );
      if (!_disposed) urlCache.putStream(stream);
    } catch (e) {
      _noteBlockSignal(e);
    }
  }

  StreamPreResolver({
    required this.resolveUrl,
    required this.urlCache,
    this.debounceDuration = const Duration(milliseconds: 300),
    this.isWifi,
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
      if (curVid != null && curVid.isNotEmpty && !_isCooling) {
        final cached = urlCache.get(curVid);
        if (cached == null || cached.isStaleWhileRevalidate()) {
          unawaited(_resolveBestEffort(curVid));
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
    if (queue.isEmpty || currentIndex < 0 || _isCooling) return;

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
      // N+1 is already cached — opportunistically pre-resolve N+2 on WiFi.
      _preResolveSecond(
        queue: queue,
        currentIndex: currentIndex,
        isShuffle: isShuffle,
        shuffleIndices: shuffleIndices,
      );
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

    resolveUrl(videoId).timeout(const Duration(seconds: 15)).then((stream) {
      if (_disposed || !identical(_activeResolution, completer)) return;
      urlCache.putStream(stream);
      debugPrint('[StreamPreResolver] Successfully pre-resolved next track ($videoId)');
      // After N+1 lands, opportunistically kick off N+2 on WiFi.
      _preResolveSecond(
        queue: queue,
        currentIndex: currentIndex,
        isShuffle: isShuffle,
        shuffleIndices: shuffleIndices,
      );
    }).catchError((Object e) {
      if (_disposed || !identical(_activeResolution, completer)) return;
      _noteBlockSignal(e);
      debugPrint('[StreamPreResolver] Pre-resolution failed for $videoId non-fatally: $e');
    }).whenComplete(() {
      if (identical(_activeResolution, completer)) {
        _inFlightVideoId = null;
        _activeResolution = null;
      }
    });
  }

  /// Pre-resolves track N+2 (the one after next) on WiFi to eliminate
  /// back-to-back skip latency. Silently no-ops if not on WiFi, if N+2
  /// is already cached, or if [isWifi] is not provided.
  void _preResolveSecond({
    required List<SongsTableData> queue,
    required int currentIndex,
    required bool isShuffle,
    List<int>? shuffleIndices,
  }) {
    if (_disposed || isWifi == null || _isCooling) return;

    // Determine N+1 index first, then N+2 from there.
    final nextSong = _determineNextSong(
      queue: queue,
      currentIndex: currentIndex,
      isShuffle: isShuffle,
      shuffleIndices: shuffleIndices,
    );
    if (nextSong == null) return;

    // Compute the index of nextSong without O(n) indexOf (equality-fragile
    // on Drift rows): derive arithmetically.
    int nextIndex = -1;
    if (isShuffle && shuffleIndices != null && shuffleIndices.isNotEmpty) {
      final pos = shuffleIndices.indexOf(currentIndex);
      if (pos >= 0 && pos + 1 < shuffleIndices.length) {
        nextIndex = shuffleIndices[pos + 1];
      }
    } else {
      nextIndex = currentIndex + 1;
    }
    if (nextIndex < 0 || nextIndex >= queue.length) return;

    final secondNextSong = _determineNextSong(
      queue: queue,
      currentIndex: nextIndex,
      isShuffle: isShuffle,
      shuffleIndices: shuffleIndices,
    );
    final vid2 = secondNextSong?.remoteId;
    if (vid2 == null || vid2.isEmpty) return;
    if (urlCache.contains(vid2) || vid2 == _inFlightVideoId) return;

    // Only consume bandwidth for N+2 on WiFi.
    isWifi!().then((wifi) {
      if (!wifi || _disposed || _isCooling) return;
      if (urlCache.contains(vid2)) return;
      debugPrint('[StreamPreResolver] WiFi detected — pre-resolving N+2 track ($vid2)');
      resolveUrl(vid2).timeout(const Duration(seconds: 15)).then((stream) {
        if (_disposed) return;
        urlCache.putStream(stream);
        debugPrint('[StreamPreResolver] N+2 pre-resolved ($vid2)');
      }).catchError((Object e) {
        _noteBlockSignal(e);
      });
    }).catchError((Object _) {});
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

    // Normal linear queue order — do NOT loop to head: pre-resolving
    // queue.first at the end of the queue warms the wrong track and burns
    // a PLAYER permit for a song the user likely won't play next.
    final nextIndex = currentIndex + 1;
    if (nextIndex < queue.length) {
      return queue[nextIndex];
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
